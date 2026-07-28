"""SQLite persistence for deterministic capability-gap intake."""

from __future__ import annotations

import re
import sqlite3
from collections.abc import Callable, Iterable
from contextlib import suppress
from datetime import datetime
from typing import Any, TypeVar, cast

from study_agent.feedback.outbox import OUTBOX_SCHEMA_VERSION, GapOutboxBundle, GapOutboxRecord
from study_agent.state import canonical_json_object

from .contracts import (
    ActiveWorkIndex,
    ActiveWorkKind,
    ActiveWorkSnapshot,
    CandidateSnapshot,
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapUnavailableError,
    CapabilityGapValidationError,
    ContributionSnapshot,
    DeliveryImportContext,
    ImportReceiptV1,
    ReproductionEvidence,
    ReproductionRegistry,
    ReproductionStatus,
)

SCHEMA_VERSION = 1
_T = TypeVar("_T")

_EXPECTED_COLUMNS: dict[str, tuple[tuple[str, str, int, str | None, int], ...]] = {
    "deliveries": (
        ("delivery_pk", "INTEGER", 0, None, 1),
        ("delivery_import_id", "TEXT", 1, None, 0),
        ("bundle_fingerprint", "TEXT", 1, None, 0),
        ("receipt_bytes", "BLOB", 1, None, 0),
    ),
    "candidates": (("gap_key", "TEXT", 0, None, 1), ("dimensions_bytes", "BLOB", 1, None, 0)),
    "contributions": (
        ("contribution_pk", "INTEGER", 0, None, 1),
        ("delivery_pk", "INTEGER", 1, None, 0),
        ("gap_key", "TEXT", 1, None, 0),
        ("record_bytes", "BLOB", 1, None, 0),
    ),
    "candidate_active_work": (
        ("gap_key", "TEXT", 1, None, 1),
        ("work_kind", "TEXT", 1, None, 2),
        ("work_id", "TEXT", 1, None, 3),
    ),
    "reproductions": (
        ("contribution_pk", "INTEGER", 0, None, 1),
        ("status", "TEXT", 1, None, 0),
        ("fixture_id", "TEXT", 0, None, 0),
        ("evidence_digest", "TEXT", 0, None, 0),
    ),
}
_EXPECTED_FKS: dict[str, tuple[tuple[str, str, str, str, str, str], ...]] = {
    "deliveries": (),
    "candidates": (),
    "contributions": (
        ("deliveries", "delivery_pk", "delivery_pk", "NO ACTION", "CASCADE", "NONE"),
        ("candidates", "gap_key", "gap_key", "NO ACTION", "CASCADE", "NONE"),
    ),
    "candidate_active_work": (
        ("candidates", "gap_key", "gap_key", "NO ACTION", "CASCADE", "NONE"),
    ),
    "reproductions": (
        ("contributions", "contribution_pk", "contribution_pk", "NO ACTION", "CASCADE", "NONE"),
    ),
}
_EXPECTED_DDL = {
    "deliveries": """CREATE TABLE deliveries (
        delivery_pk INTEGER PRIMARY KEY,
        delivery_import_id TEXT NOT NULL UNIQUE,
        bundle_fingerprint TEXT NOT NULL,
        receipt_bytes BLOB NOT NULL
    )""",
    "candidates": """CREATE TABLE candidates (
        gap_key TEXT PRIMARY KEY,
        dimensions_bytes BLOB NOT NULL
    )""",
    "contributions": """CREATE TABLE contributions (
        contribution_pk INTEGER PRIMARY KEY,
        delivery_pk INTEGER NOT NULL REFERENCES deliveries(delivery_pk) ON DELETE CASCADE,
        gap_key TEXT NOT NULL REFERENCES candidates(gap_key) ON DELETE CASCADE,
        record_bytes BLOB NOT NULL,
        UNIQUE (delivery_pk, gap_key)
    )""",
    "candidate_active_work": """CREATE TABLE candidate_active_work (
        gap_key TEXT NOT NULL REFERENCES candidates(gap_key) ON DELETE CASCADE,
        work_kind TEXT NOT NULL,
        work_id TEXT NOT NULL,
        PRIMARY KEY (gap_key, work_kind, work_id)
    )""",
    "reproductions": """CREATE TABLE reproductions (
        contribution_pk INTEGER PRIMARY KEY REFERENCES contributions(contribution_pk)
            ON DELETE CASCADE,
        status TEXT NOT NULL,
        fixture_id TEXT,
        evidence_digest TEXT
    )""",
}
_EXPECTED_INDEXES: dict[str, frozenset[tuple[int, str, int, tuple[str, ...]]]] = {
    "deliveries": frozenset({(1, "u", 0, ("delivery_import_id",))}),
    "candidates": frozenset({(1, "pk", 0, ("gap_key",))}),
    "contributions": frozenset({(1, "u", 0, ("delivery_pk", "gap_key"))}),
    "candidate_active_work": frozenset(
        {(1, "pk", 0, ("gap_key", "work_kind", "work_id"))}
    ),
    "reproductions": frozenset(),
}


def _canonical_ddl(sql: str) -> tuple[str, ...]:
    """Normalize SQLite DDL into a whitespace-independent token sequence."""
    token_pattern = (
        r"'[^']*(?:''[^']*)*'|\"[^\"]*(?:\"\"[^\"]*)*\"|"
        r"[a-z_][a-z0-9_]*|\d+(?:\.\d+)?|<>|!=|<=|>=|[(),.;=<>*+\-/]"
    )
    return tuple(re.findall(token_pattern, sql.lower()))


class SQLiteCapabilityGapStore:
    """A small transactional repository for imported, redacted evidence.

    The only operational identifier held here is the delivery claim in the
    ``deliveries`` table.  All candidate-facing reads are deliberately
    reconstructed without that claim.
    """

    def __init__(self, database: object) -> None:
        self._owns_connection = not isinstance(database, sqlite3.Connection)
        self._connection = (
            database
            if isinstance(database, sqlite3.Connection)
            else sqlite3.connect(str(database), isolation_level=None)
        )
        self._connection.row_factory = sqlite3.Row
        self._connection.execute("PRAGMA foreign_keys = ON")
        self._initialize_schema()

    @property
    def connection(self) -> sqlite3.Connection:
        return self._connection

    def close(self) -> None:
        if self._owns_connection:
            self._connection.close()

    def __enter__(self) -> SQLiteCapabilityGapStore:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def _initialize_schema(self) -> None:
        current = int(self._connection.execute("PRAGMA user_version").fetchone()[0])
        if current not in (0, SCHEMA_VERSION):
            raise CapabilityGapCorruptionError("invalid_schema_version")
        if current == SCHEMA_VERSION:
            try:
                self._validate_schema()
            except sqlite3.DatabaseError as error:
                raise CapabilityGapCorruptionError("invalid_schema_ddl") from error
            return
        existing_objects = {
            str(row[0])
            for row in self._connection.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'view', 'trigger')"
            ).fetchall()
            if row[0] != "sqlite_sequence"
        }
        if existing_objects:
            raise CapabilityGapCorruptionError("invalid_schema_version")
        self._connection.executescript(
            """
            BEGIN IMMEDIATE;
            CREATE TABLE IF NOT EXISTS deliveries (
                delivery_pk INTEGER PRIMARY KEY,
                delivery_import_id TEXT NOT NULL UNIQUE,
                bundle_fingerprint TEXT NOT NULL,
                receipt_bytes BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS candidates (
                gap_key TEXT PRIMARY KEY,
                dimensions_bytes BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS contributions (
                contribution_pk INTEGER PRIMARY KEY,
                delivery_pk INTEGER NOT NULL REFERENCES deliveries(delivery_pk)
                    ON DELETE CASCADE,
                gap_key TEXT NOT NULL REFERENCES candidates(gap_key)
                    ON DELETE CASCADE,
                record_bytes BLOB NOT NULL,
                UNIQUE (delivery_pk, gap_key)
            );
            CREATE TABLE IF NOT EXISTS candidate_active_work (
                gap_key TEXT NOT NULL REFERENCES candidates(gap_key)
                    ON DELETE CASCADE,
                work_kind TEXT NOT NULL,
                work_id TEXT NOT NULL,
                PRIMARY KEY (gap_key, work_kind, work_id)
            );
            CREATE TABLE IF NOT EXISTS reproductions (
                contribution_pk INTEGER PRIMARY KEY REFERENCES contributions(contribution_pk)
                    ON DELETE CASCADE,
                status TEXT NOT NULL,
                fixture_id TEXT,
                evidence_digest TEXT
            );
            PRAGMA user_version = 1;
            COMMIT;
            """
        )
        try:
            self._validate_schema()
        except sqlite3.DatabaseError as error:
            raise CapabilityGapCorruptionError("invalid_schema_ddl") from error

    def _validate_schema(self) -> None:
        if int(self._connection.execute("PRAGMA foreign_keys").fetchone()[0]) != 1:
            raise CapabilityGapCorruptionError("invalid_schema_foreign_keys")
        tables = {
            str(row[0])
            for row in self._connection.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'view', 'trigger')"
            ).fetchall()
            if row[0] != "sqlite_sequence"
        }
        if tables != set(_EXPECTED_COLUMNS):
            raise CapabilityGapCorruptionError("invalid_schema_tables")
        for table, expected_columns in _EXPECTED_COLUMNS.items():
            ddl_row = self._connection.execute(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)
            ).fetchone()
            if ddl_row is None or not isinstance(ddl_row[0], str):
                raise CapabilityGapCorruptionError("invalid_schema_ddl")
            if _canonical_ddl(ddl_row[0]) != _canonical_ddl(_EXPECTED_DDL[table]):
                raise CapabilityGapCorruptionError("invalid_schema_ddl")
            actual = tuple(
                (str(row[1]), str(row[2]).upper(), int(row[3]), row[4], int(row[5]))
                for row in self._connection.execute(f"PRAGMA table_info({table})").fetchall()
            )
            if actual != expected_columns:
                raise CapabilityGapCorruptionError("invalid_schema_columns")
            indexes: set[tuple[int, str, int, tuple[str, ...]]] = set()
            for index in self._connection.execute(f"PRAGMA index_list({table})").fetchall():
                columns = tuple(
                    str(item[2])
                    for item in self._connection.execute(
                        f"PRAGMA index_info({index[1]!s})"
                    ).fetchall()
                )
                indexes.add((int(index[2]), str(index[3]), int(index[4]), columns))
            if indexes != _EXPECTED_INDEXES[table]:
                raise CapabilityGapCorruptionError("invalid_schema_indexes")
            actual_fks = tuple(
                sorted(
                    (
                        str(row[2]),
                        str(row[3]),
                        str(row[4]),
                        str(row[5]).upper(),
                        str(row[6]).upper(),
                        str(row[7]).upper(),
                    )
                    for row in self._connection.execute(f"PRAGMA foreign_key_list({table})")
                )
            )
            if actual_fks != tuple(sorted(_EXPECTED_FKS[table])):
                raise CapabilityGapCorruptionError("invalid_schema_foreign_keys")

    def import_bundle(
        self,
        payload: bytes,
        context: DeliveryImportContext,
        *,
        active_work: ActiveWorkIndex | None = None,
        reproduction: ReproductionRegistry | None = None,
    ) -> ImportReceiptV1:
        """Validate and atomically import one exact canonical outbox bundle."""
        registry = reproduction
        if not isinstance(context, DeliveryImportContext):
            raise CapabilityGapValidationError("invalid_import_context")
        if not isinstance(payload, bytes):
            raise CapabilityGapCorruptionError("invalid_bundle_payload")
        try:
            bundle = GapOutboxBundle.from_bytes(payload)
        except Exception as error:
            raise CapabilityGapCorruptionError("invalid_bundle_payload") from error
        if bundle.schema_version != OUTBOX_SCHEMA_VERSION or OUTBOX_SCHEMA_VERSION != 2:
            raise CapabilityGapCorruptionError("unsupported_outbox_schema")
        if bundle.to_bytes() != payload:
            raise CapabilityGapCorruptionError("noncanonical_bundle_payload")
        fingerprint = bundle.bundle_fingerprint
        if fingerprint != context.bundle_fingerprint:
            raise CapabilityGapCollisionError("bundle_fingerprint_mismatch")
        candidate_keys = tuple(sorted(record.gap_key.value for record in bundle.records))
        expected_receipt = ImportReceiptV1(fingerprint, candidate_keys)

        connection = self._connection
        connection.execute("BEGIN IMMEDIATE")
        try:
            existing = connection.execute(
                "SELECT delivery_pk, bundle_fingerprint, receipt_bytes "
                "FROM deliveries WHERE delivery_import_id = ?",
                (context.delivery_import_id,),
            ).fetchone()
            if existing is not None:
                if existing["bundle_fingerprint"] != fingerprint:
                    raise CapabilityGapCollisionError("delivery_import_collision")
                self._validate_sqlite_integrity(connection)
                self._validate_existing_candidates(connection, bundle.records)
                stored_receipt_bytes = bytes(existing["receipt_bytes"])
                if stored_receipt_bytes != expected_receipt.to_bytes():
                    raise CapabilityGapCorruptionError("stored_receipt_mismatch")
                contribution_rows = connection.execute(
                    "SELECT gap_key, record_bytes, contribution_pk FROM contributions "
                    "WHERE delivery_pk = ? ORDER BY gap_key",
                    (int(existing["delivery_pk"]),),
                ).fetchall()
                incoming = tuple(
                    (record.gap_key.value, record.to_bytes())
                    for record in bundle.records
                )
                stored = tuple(
                    (str(row["gap_key"]), bytes(row["record_bytes"]))
                    for row in contribution_rows
                )
                if stored != incoming or len(stored) != len(incoming):
                    raise CapabilityGapCorruptionError("stored_contributions_mismatch")
                for row in contribution_rows:
                    self._validate_reproduction_row(connection, int(row["contribution_pk"]))
                connection.execute("COMMIT")
                return expected_receipt

            # Validate every candidate claim before writing any durable row.
            for record in bundle.records:
                existing_candidate = connection.execute(
                    "SELECT dimensions_bytes FROM candidates WHERE gap_key = ?",
                    (record.gap_key.value,),
                ).fetchone()
                if existing_candidate is not None and bytes(
                    existing_candidate["dimensions_bytes"]
                ) != record.dimensions.to_bytes():
                    raise CapabilityGapCollisionError("candidate_dimensions_collision")

            cursor = connection.execute(
                "INSERT INTO deliveries "
                "(delivery_import_id, bundle_fingerprint, receipt_bytes) VALUES (?, ?, ?)",
                (context.delivery_import_id, fingerprint, expected_receipt.to_bytes()),
            )
            if cursor.lastrowid is None:
                raise CapabilityGapCorruptionError("delivery_insert_missing_rowid")
            delivery_pk = int(cursor.lastrowid)

            for record in bundle.records:
                key = record.gap_key.value
                dimensions = record.dimensions.to_bytes()
                connection.execute(
                    "INSERT OR IGNORE INTO candidates (gap_key, dimensions_bytes) VALUES (?, ?)",
                    (key, dimensions),
                )
                cursor = connection.execute(
                    "INSERT INTO contributions "
                    "(delivery_pk, gap_key, record_bytes) VALUES (?, ?, ?)",
                    (delivery_pk, key, record.to_bytes()),
                )
                if cursor.lastrowid is None:
                    raise CapabilityGapCorruptionError("contribution_insert_missing_rowid")
                contribution_pk = int(cursor.lastrowid)
                evidence = (
                    registry.evaluate(record)
                    if registry is not None
                    else ReproductionEvidence(
                        ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT, None, None
                    )
                )
                connection.execute(
                    "INSERT INTO reproductions "
                    "(contribution_pk, status, fixture_id, evidence_digest) "
                    "VALUES (?, ?, ?, ?)",
                    (
                        contribution_pk,
                        evidence.status.value,
                        evidence.fixture_id,
                        evidence.evidence_digest,
                    ),
                )
                if active_work is not None:
                    links = active_work.matches(key, record.dimensions)
                    for link in _validate_active_work_links(key, links):
                        connection.execute(
                            "INSERT OR IGNORE INTO candidate_active_work "
                            "(gap_key, work_kind, work_id) VALUES (?, ?, ?)",
                            (link.gap_key, link.kind.value, link.work_id),
                        )

            connection.execute("COMMIT")
            return expected_receipt
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    @staticmethod
    def _validate_sqlite_integrity(connection: sqlite3.Connection) -> None:
        if connection.execute("PRAGMA foreign_key_check").fetchall():
            raise CapabilityGapCorruptionError("stored_foreign_key_violation")
        result = connection.execute("PRAGMA integrity_check").fetchall()
        if len(result) != 1 or str(result[0][0]).lower() != "ok":
            raise CapabilityGapCorruptionError("stored_integrity_violation")

    @staticmethod
    def _validate_existing_candidates(
        connection: sqlite3.Connection, records: tuple[GapOutboxRecord, ...]
    ) -> None:
        expected = {record.gap_key.value: record.dimensions.to_bytes() for record in records}
        if not expected:
            return
        placeholders = ", ".join("?" for _ in expected)
        candidate_rows = connection.execute(
            f"SELECT gap_key, dimensions_bytes FROM candidates WHERE gap_key IN ({placeholders})",
            tuple(expected),
        ).fetchall()
        if {str(row["gap_key"]) for row in candidate_rows} != set(expected):
            raise CapabilityGapCorruptionError("stored_candidates_mismatch")
        for row in candidate_rows:
            key = str(row["gap_key"])
            if bytes(row["dimensions_bytes"]) != expected[key]:
                raise CapabilityGapCorruptionError("stored_candidate_dimensions_mismatch")
            try:
                work_rows = connection.execute(
                    "SELECT work_kind, work_id FROM candidate_active_work WHERE gap_key = ?",
                    (key,),
                ).fetchall()
                for work_row in work_rows:
                    ActiveWorkSnapshot(
                        key, ActiveWorkKind(str(work_row["work_kind"])), str(work_row["work_id"])
                    )
            except (TypeError, ValueError, CapabilityGapValidationError) as error:
                raise CapabilityGapCorruptionError("stored_candidate_work_mismatch") from error
            contribution_rows = connection.execute(
                "SELECT contribution_pk, record_bytes FROM contributions WHERE gap_key = ?",
                (key,),
            ).fetchall()
            if not contribution_rows:
                raise CapabilityGapCorruptionError("stored_candidate_contributions_missing")
            for contribution_row in contribution_rows:
                SQLiteCapabilityGapStore._validate_reproduction_row(
                    connection, int(contribution_row["contribution_pk"])
                )
                record_bytes = bytes(contribution_row["record_bytes"])
                try:
                    record = GapOutboxRecord.from_bytes(record_bytes)
                except Exception as error:
                    raise CapabilityGapCorruptionError(
                        "stored_candidate_contribution_invalid"
                    ) from error
                if (
                    record.gap_key.value != key
                    or record.dimensions.to_bytes() != expected[key]
                    or record.to_bytes() != record_bytes
                ):
                    raise CapabilityGapCorruptionError("stored_candidate_link_mismatch")

    @staticmethod
    def _validate_reproduction_row(
        connection: sqlite3.Connection, contribution_pk: int
    ) -> None:
        rows = connection.execute(
            "SELECT status, fixture_id, evidence_digest FROM reproductions "
            "WHERE contribution_pk = ?",
            (contribution_pk,),
        ).fetchall()
        if len(rows) != 1:
            raise CapabilityGapCorruptionError("stored_reproduction_mismatch")
        row = rows[0]
        status = row["status"]
        fixture_id = row["fixture_id"]
        evidence_digest = row["evidence_digest"]
        if not isinstance(status, str):
            raise CapabilityGapCorruptionError("stored_reproduction_mismatch")
        if fixture_id is not None and not isinstance(fixture_id, str):
            raise CapabilityGapCorruptionError("stored_reproduction_mismatch")
        if evidence_digest is not None and not isinstance(evidence_digest, str):
            raise CapabilityGapCorruptionError("stored_reproduction_mismatch")
        try:
            ReproductionEvidence(
                ReproductionStatus(status),
                fixture_id,
                evidence_digest,
            )
        except (TypeError, ValueError, CapabilityGapValidationError) as error:
            raise CapabilityGapCorruptionError("stored_reproduction_mismatch") from error

    def get_candidate(self, gap_key: str) -> CandidateSnapshot:
        def read(connection: sqlite3.Connection) -> CandidateSnapshot:
            row = connection.execute(
                "SELECT gap_key, dimensions_bytes FROM candidates WHERE gap_key = ?", (gap_key,)
            ).fetchone()
            if row is None:
                raise CapabilityGapUnavailableError("candidate_not_found")
            return self._snapshot(
                connection, str(row["gap_key"]), bytes(row["dimensions_bytes"])
            )

        return self._read_snapshot(read)

    def list_candidates(self) -> tuple[CandidateSnapshot, ...]:
        def read(connection: sqlite3.Connection) -> tuple[CandidateSnapshot, ...]:
            rows = connection.execute(
                "SELECT gap_key, dimensions_bytes FROM candidates ORDER BY gap_key"
            ).fetchall()
            return tuple(
                self._snapshot(connection, str(row["gap_key"]), bytes(row["dimensions_bytes"]))
                for row in rows
            )

        return self._read_snapshot(read)

    def _read_snapshot(self, reader: Callable[[sqlite3.Connection], _T]) -> _T:
        connection = self._connection
        connection.execute("BEGIN")
        try:
            result = reader(connection)
            connection.execute("COMMIT")
            return result
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    def _snapshot(
        self, connection: sqlite3.Connection, gap_key: str, dimensions_bytes: bytes
    ) -> CandidateSnapshot:
        from study_agent.feedback.outbox import GapOutboxDimensions, GapOutboxRecord

        try:
            dimensions = GapOutboxDimensions.from_json(
                cast(Any, canonical_json_object(dimensions_bytes))
            )
            if dimensions.to_bytes() != dimensions_bytes:
                raise CapabilityGapCorruptionError("stored_candidate_noncanonical")
        except Exception as error:
            raise CapabilityGapCorruptionError("stored_candidate_invalid") from error
        rows = connection.execute(
            "SELECT contribution_pk, record_bytes FROM contributions "
            "WHERE gap_key = ?",
            (gap_key,),
        ).fetchall()
        contributions: list[ContributionSnapshot] = []
        occurrences = 0
        first_seen: datetime | None = None
        last_seen: datetime | None = None
        for row in rows:
            contribution_pk = int(row["contribution_pk"])
            record_bytes = bytes(row["record_bytes"])
            try:
                record = GapOutboxRecord.from_bytes(record_bytes)
            except Exception as error:
                raise CapabilityGapCorruptionError("stored_contribution_invalid") from error
            reproduction_row = connection.execute(
                "SELECT status, fixture_id, evidence_digest FROM reproductions "
                "WHERE contribution_pk = ?",
                (contribution_pk,),
            ).fetchone()
            if reproduction_row is None:
                raise CapabilityGapCorruptionError("stored_reproduction_missing")
            try:
                evidence = ReproductionEvidence(
                    ReproductionStatus(str(reproduction_row["status"])),
                    (
                        None
                        if reproduction_row["fixture_id"] is None
                        else str(reproduction_row["fixture_id"])
                    ),
                    (
                        None
                        if reproduction_row["evidence_digest"] is None
                        else str(reproduction_row["evidence_digest"])
                    ),
                )
            except (TypeError, ValueError, CapabilityGapValidationError) as error:
                raise CapabilityGapCorruptionError("stored_reproduction_invalid") from error
            contributions.append(
                ContributionSnapshot(gap_key, dimensions, record_bytes, evidence)
            )
            occurrences += record.occurrence_count
            first_seen = (
                record.first_seen
                if first_seen is None
                else min(first_seen, record.first_seen)
            )
            last_seen = (
                record.last_seen if last_seen is None else max(last_seen, record.last_seen)
            )
        if not contributions or first_seen is None or last_seen is None:
            raise CapabilityGapCorruptionError("stored_candidate_empty")
        contributions.sort(
            key=lambda item: (
                item.record_bytes,
                item.reproduction.status.value,
                item.reproduction.fixture_id or "",
                item.reproduction.evidence_digest or "",
            )
        )
        work_rows = connection.execute(
            "SELECT work_kind, work_id FROM candidate_active_work "
            "WHERE gap_key = ? ORDER BY work_kind, work_id",
            (gap_key,),
        ).fetchall()
        try:
            active_work = tuple(
                ActiveWorkSnapshot(
                    gap_key, ActiveWorkKind(str(row["work_kind"])), str(row["work_id"])
                )
                for row in work_rows
            )
        except (TypeError, ValueError, CapabilityGapValidationError) as error:
            raise CapabilityGapCorruptionError("stored_active_work_invalid") from error
        return CandidateSnapshot(
            gap_key,
            dimensions,
            tuple(contributions),
            occurrences,
            first_seen,
            last_seen,
            active_work,
        )

def _validate_active_work_links(
    gap_key: str, links: Iterable[ActiveWorkSnapshot]
) -> tuple[ActiveWorkSnapshot, ...]:
    validated: list[ActiveWorkSnapshot] = []
    for link in links:
        if not isinstance(link, ActiveWorkSnapshot):
            raise CapabilityGapValidationError("invalid_active_work_link")
        if link.gap_key != gap_key:
            raise CapabilityGapValidationError("active_work_gap_key_mismatch")
        validated.append(link)
    return tuple(sorted(set(validated), key=lambda item: (item.kind.value, item.work_id)))


__all__ = [
    "SCHEMA_VERSION",
    "SQLiteCapabilityGapStore",
]
