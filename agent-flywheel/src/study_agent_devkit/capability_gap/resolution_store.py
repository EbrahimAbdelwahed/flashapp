"""Private, fail-closed SQLite persistence for GAP-06 resolutions."""

from __future__ import annotations

import re
import sqlite3
from collections.abc import Callable
from contextlib import suppress
from typing import TypeVar

from .contracts import (
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapUnavailableError,
    CapabilityGapValidationError,
)
from .resolution_contracts import (
    MAX_PROMOTION_BYTES,
    MAX_RESOLUTION_BYTES,
    FlywheelPromotionBundleV1,
    FlywheelPromotionReceiptV1,
    GapResolutionV1,
)

SCHEMA_VERSION = 1
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_DDL = {
    "resolution_packages": """CREATE TABLE resolution_packages (
        resolution_pk INTEGER PRIMARY KEY,
        resolution_id TEXT NOT NULL UNIQUE,
        decision_id TEXT NOT NULL UNIQUE,
        proposal_id TEXT NOT NULL UNIQUE,
        outcome TEXT NOT NULL,
        promotion_id TEXT UNIQUE,
        resolution_bytes BLOB NOT NULL,
        promotion_bytes BLOB
    )""",
    "materialization_claims": """CREATE TABLE materialization_claims (
        claim_pk INTEGER PRIMARY KEY,
        promotion_id TEXT NOT NULL UNIQUE,
        sink_id TEXT NOT NULL,
        receipt_bytes BLOB
    )""",
}
_COLUMNS = {
    "resolution_packages": (
        ("resolution_pk", "INTEGER", 0, None, 1),
        ("resolution_id", "TEXT", 1, None, 0),
        ("decision_id", "TEXT", 1, None, 0),
        ("proposal_id", "TEXT", 1, None, 0),
        ("outcome", "TEXT", 1, None, 0),
        ("promotion_id", "TEXT", 0, None, 0),
        ("resolution_bytes", "BLOB", 1, None, 0),
        ("promotion_bytes", "BLOB", 0, None, 0),
    ),
    "materialization_claims": (
        ("claim_pk", "INTEGER", 0, None, 1),
        ("promotion_id", "TEXT", 1, None, 0),
        ("sink_id", "TEXT", 1, None, 0),
        ("receipt_bytes", "BLOB", 0, None, 0),
    ),
}
_INDEXES = {
    "resolution_packages": frozenset(
        {
            (1, "u", 0, ("resolution_id",)),
            (1, "u", 0, ("decision_id",)),
            (1, "u", 0, ("proposal_id",)),
            (1, "u", 0, ("promotion_id",)),
        }
    ),
    "materialization_claims": frozenset({(1, "u", 0, ("promotion_id",))}),
}
_FKS = {"resolution_packages": (), "materialization_claims": ()}
_T = TypeVar("_T")


def _ddl_tokens(sql: str) -> tuple[str, ...]:
    pattern = (
        r"'[^']*(?:''[^']*)*'|\"[^\"]*(?:\"\"[^\"]*)*\"|"
        r"[a-z_][a-z0-9_]*|\d+|<>|!=|<=|>=|[(),.;=<>*+\-/]"
    )
    return tuple(re.findall(pattern, sql.lower()))


class _SQLiteResolutionStore:
    """Private store; callers can only reach it through the service."""

    def __init__(self, database: object) -> None:
        self._owns_connection = not isinstance(database, sqlite3.Connection)
        self._connection = (
            database
            if isinstance(database, sqlite3.Connection)
            else sqlite3.connect(str(database), isolation_level=None, timeout=30)
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

    def _initialize_schema(self) -> None:
        try:
            self._connection.execute("BEGIN IMMEDIATE")
            current = self._connection.execute("PRAGMA user_version").fetchone()[0]
            if type(current) is not int or current not in (0, SCHEMA_VERSION):
                raise CapabilityGapCorruptionError("invalid_schema_version")
            objects = {
                str(row[0])
                for row in self._connection.execute(
                    "SELECT name FROM sqlite_master WHERE type IN ('table','view','trigger')"
                ).fetchall()
                if row[0] != "sqlite_sequence"
            }
            if current == 0:
                if objects:
                    raise CapabilityGapCorruptionError("invalid_schema_version")
                for ddl in _DDL.values():
                    self._connection.execute(ddl)
                self._connection.execute("PRAGMA user_version = 1")
            self._connection.execute("COMMIT")
        except CapabilityGapCorruptionError:
            with suppress(Exception):
                self._connection.execute("ROLLBACK")
            raise
        except sqlite3.DatabaseError as error:
            with suppress(Exception):
                self._connection.execute("ROLLBACK")
            raise CapabilityGapCorruptionError("schema_initialization_failed") from error
        except BaseException:
            with suppress(Exception):
                self._connection.execute("ROLLBACK")
            raise
        self._validate_schema()

    def _validate_schema(self) -> None:
        if int(self._connection.execute("PRAGMA user_version").fetchone()[0]) != SCHEMA_VERSION:
            raise CapabilityGapCorruptionError("invalid_schema_version")
        if int(self._connection.execute("PRAGMA foreign_keys").fetchone()[0]) != 1:
            raise CapabilityGapCorruptionError("invalid_schema_foreign_keys")
        objects = {
            str(row[0])
            for row in self._connection.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table','view','trigger')"
            ).fetchall()
            if row[0] != "sqlite_sequence"
        }
        if objects != set(_DDL):
            raise CapabilityGapCorruptionError("invalid_schema_tables")
        for table, expected in _COLUMNS.items():
            row = self._connection.execute(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", (table,)
            ).fetchone()
            if (
                row is None
                or not isinstance(row[0], str)
                or _ddl_tokens(row[0]) != _ddl_tokens(_DDL[table])
            ):
                raise CapabilityGapCorruptionError("invalid_schema_ddl")
            actual = tuple(
                (str(item[1]), str(item[2]).upper(), int(item[3]), item[4], int(item[5]))
                for item in self._connection.execute(f"PRAGMA table_info({table})").fetchall()
            )
            if actual != expected:
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
            if indexes != _INDEXES[table]:
                raise CapabilityGapCorruptionError("invalid_schema_indexes")

    @staticmethod
    def _integrity(connection: sqlite3.Connection) -> None:
        result = connection.execute("PRAGMA integrity_check").fetchall()
        if len(result) != 1 or str(result[0][0]).lower() != "ok":
            raise CapabilityGapCorruptionError("stored_integrity_violation")

    def _decode_row(
        self, row: sqlite3.Row
    ) -> tuple[GapResolutionV1, FlywheelPromotionBundleV1 | None]:
        resolution_bytes = row["resolution_bytes"]
        if type(resolution_bytes) is not bytes or len(resolution_bytes) > MAX_RESOLUTION_BYTES:
            raise CapabilityGapCorruptionError("invalid_stored_resolution_bytes")
        resolution = GapResolutionV1.from_bytes(resolution_bytes)
        if (
            any(
                str(row[field]) != getattr(resolution, field)
                for field in ("resolution_id", "decision_id", "proposal_id")
            )
            or str(row["outcome"]) != resolution.outcome.value
        ):
            raise CapabilityGapCorruptionError("stored_resolution_projection_mismatch")
        promotion_bytes = row["promotion_bytes"]
        promotion_id = row["promotion_id"]
        if resolution.outcome.value != "accepted":
            if promotion_bytes is not None or promotion_id is not None:
                raise CapabilityGapCorruptionError("nonaccepted_promotion_present")
            return resolution, None
        if (
            type(promotion_bytes) is not bytes
            or len(promotion_bytes) > MAX_PROMOTION_BYTES
            or not isinstance(promotion_id, str)
        ):
            raise CapabilityGapCorruptionError("missing_accepted_promotion")
        promotion = _decode_promotion(promotion_bytes)
        if (
            promotion.promotion_id != promotion_id
            or promotion.resolution_id != resolution.resolution_id
            or promotion.proposal_id != resolution.proposal_id
            or promotion.decision_id != resolution.decision_id
            or promotion.selected_option_id != resolution.selected_option_id
            or promotion.requested_authority != resolution.requested_authority
            or promotion.grill_receipts != resolution.grill_receipts
        ):
            raise CapabilityGapCorruptionError("stored_promotion_projection_mismatch")
        return resolution, promotion

    def _validate_all(self, connection: sqlite3.Connection) -> None:
        rows = connection.execute(
            "SELECT * FROM resolution_packages ORDER BY resolution_pk"
        ).fetchall()
        seen_decisions: set[str] = set()
        by_proposal: dict[str, GapResolutionV1] = {}
        duplicate_edges: dict[str, str] = {}
        promotion_ids: set[str] = set()
        for row in rows:
            resolution, promotion = self._decode_row(row)
            if resolution.decision_id in seen_decisions:
                raise CapabilityGapCorruptionError("duplicate_resolution_decision")
            seen_decisions.add(resolution.decision_id)
            if resolution.proposal_id in by_proposal:
                raise CapabilityGapCorruptionError("duplicate_resolution_proposal")
            by_proposal[resolution.proposal_id] = resolution
            if promotion is not None:
                promotion_ids.add(promotion.promotion_id)
            if resolution.duplicate_of_proposal_id is not None:
                target = resolution.duplicate_of_proposal_id
                if target == resolution.proposal_id:
                    raise CapabilityGapCorruptionError("invalid_duplicate_graph")
                duplicate_edges[resolution.proposal_id] = target
        for proposal_id, resolution in by_proposal.items():
            if (
                proposal_id in {target for target in duplicate_edges.values()}
                and resolution.outcome.value == "duplicate"
            ):
                raise CapabilityGapCorruptionError("duplicate_graph_not_rooted")
        for source in duplicate_edges:
            seen: set[str] = set()
            current = source
            while current in duplicate_edges:
                if current in seen:
                    raise CapabilityGapCorruptionError("duplicate_graph_cycle")
                seen.add(current)
                current = duplicate_edges[current]
        claims = connection.execute(
            "SELECT * FROM materialization_claims ORDER BY claim_pk"
        ).fetchall()
        for claim in claims:
            if not _DIGEST.fullmatch(str(claim["promotion_id"])) or not _DIGEST.fullmatch(
                str(claim["sink_id"])
            ):
                raise CapabilityGapCorruptionError("invalid_materialization_claim")
            if str(claim["promotion_id"]) not in promotion_ids:
                raise CapabilityGapCorruptionError("claim_promotion_missing")
            receipt = claim["receipt_bytes"]
            if receipt is not None:
                if type(receipt) is not bytes:
                    raise CapabilityGapCorruptionError("invalid_materialization_receipt")
                promotion_row = connection.execute(
                    "SELECT * FROM resolution_packages WHERE promotion_id=?",
                    (str(claim["promotion_id"]),),
                ).fetchone()
                if promotion_row is None:
                    raise CapabilityGapCorruptionError("claim_promotion_missing")
                _, promotion = self._decode_row(promotion_row)
                if promotion is None:
                    raise CapabilityGapCorruptionError("claim_promotion_missing")
                try:
                    stored_receipt = FlywheelPromotionReceiptV1.from_bytes(receipt)
                    expected = FlywheelPromotionReceiptV1.for_bundle(
                        promotion, str(claim["sink_id"])
                    )
                except (TypeError, ValueError, CapabilityGapCorruptionError):
                    raise CapabilityGapCorruptionError("invalid_materialization_receipt") from None
                if stored_receipt.to_bytes() != expected.to_bytes():
                    raise CapabilityGapCorruptionError("materialization_receipt_mismatch")

    def _read(self, callback: Callable[[sqlite3.Connection], _T]) -> _T:
        self._connection.execute("BEGIN")
        try:
            self._validate_schema()
            self._integrity(self._connection)
            self._validate_all(self._connection)
            result = callback(self._connection)
            self._connection.execute("COMMIT")
            return result
        except BaseException:
            with suppress(Exception):
                self._connection.execute("ROLLBACK")
            raise

    def get_by_decision_id(
        self, decision_id: str
    ) -> tuple[GapResolutionV1, FlywheelPromotionBundleV1 | None] | None:
        return self._read(
            lambda connection: (
                self._decode_row(row)
                if (
                    row := connection.execute(
                        "SELECT * FROM resolution_packages WHERE decision_id=?", (decision_id,)
                    ).fetchone()
                )
                is not None
                else None
            )
        )

    def get_by_proposal_id(
        self, proposal_id: str
    ) -> tuple[GapResolutionV1, FlywheelPromotionBundleV1 | None] | None:
        return self._read(
            lambda connection: (
                self._decode_row(row)
                if (
                    row := connection.execute(
                        "SELECT * FROM resolution_packages WHERE proposal_id=?", (proposal_id,)
                    ).fetchone()
                )
                is not None
                else None
            )
        )

    def get_by_promotion_id(
        self, promotion_id: str
    ) -> tuple[GapResolutionV1, FlywheelPromotionBundleV1] | None:
        def read(
            connection: sqlite3.Connection,
        ) -> tuple[GapResolutionV1, FlywheelPromotionBundleV1] | None:
            row = connection.execute(
                "SELECT * FROM resolution_packages WHERE promotion_id=?", (promotion_id,)
            ).fetchone()
            if row is None:
                return None
            resolution, promotion = self._decode_row(row)
            return None if promotion is None else (resolution, promotion)

        return self._read(read)

    def has_inbound_duplicate(
        self, proposal_id: str, connection: sqlite3.Connection | None = None
    ) -> bool:
        def read(conn: sqlite3.Connection) -> bool:
            rows = conn.execute(
                "SELECT resolution_bytes FROM resolution_packages WHERE outcome='duplicate'"
            ).fetchall()
            for row in rows:
                resolution = GapResolutionV1.from_bytes(bytes(row[0]))
                if resolution.duplicate_of_proposal_id == proposal_id:
                    return True
            return False

        if connection is not None:
            return read(connection)
        return self._read(read)

    def insert(
        self,
        connection: sqlite3.Connection,
        resolution: GapResolutionV1,
        promotion: FlywheelPromotionBundleV1 | None,
    ) -> None:
        resolution_bytes = resolution.to_bytes()
        promotion_bytes = None if promotion is None else promotion.to_bytes()
        connection.execute(
            "INSERT INTO resolution_packages "
            "(resolution_id, decision_id, proposal_id, outcome, promotion_id, "
            "resolution_bytes, promotion_bytes) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                resolution.resolution_id,
                resolution.decision_id,
                resolution.proposal_id,
                resolution.outcome.value,
                None if promotion is None else promotion.promotion_id,
                resolution_bytes,
                promotion_bytes,
            ),
        )

    def get_materialization_receipt(self, promotion_id: str) -> FlywheelPromotionReceiptV1 | None:
        def read(connection: sqlite3.Connection) -> FlywheelPromotionReceiptV1 | None:
            row = connection.execute(
                "SELECT receipt_bytes FROM materialization_claims WHERE promotion_id=?",
                (promotion_id,),
            ).fetchone()
            if row is None or row[0] is None:
                return None
            try:
                return FlywheelPromotionReceiptV1.from_bytes(bytes(row[0]))
            except (TypeError, ValueError, CapabilityGapCorruptionError):
                raise CapabilityGapCorruptionError("invalid_materialization_receipt") from None

        return self._read(read)

    def claim_materialization(
        self, promotion_id: str, sink_id: str
    ) -> tuple[FlywheelPromotionBundleV1, FlywheelPromotionReceiptV1 | None]:
        if not _DIGEST.fullmatch(promotion_id) or not _DIGEST.fullmatch(sink_id):
            raise CapabilityGapValidationError("invalid_materialization_claim")
        connection = self._connection
        try:
            connection.execute("BEGIN IMMEDIATE")
            self._validate_schema()
            self._integrity(connection)
            self._validate_all(connection)
            row = connection.execute(
                "SELECT * FROM resolution_packages WHERE promotion_id=?", (promotion_id,)
            ).fetchone()
            if row is None:
                raise CapabilityGapUnavailableError("unknown_promotion")
            _, promotion = self._decode_row(row)
            if promotion is None:
                raise CapabilityGapUnavailableError("nonaccepted_promotion")
            claim = connection.execute(
                "SELECT * FROM materialization_claims WHERE promotion_id=?", (promotion_id,)
            ).fetchone()
            if claim is not None:
                if str(claim["sink_id"]) != sink_id:
                    raise CapabilityGapCollisionError("materialization_sink_collision")
                raw_receipt = claim["receipt_bytes"]
                receipt = None
                if raw_receipt is not None:
                    try:
                        receipt = FlywheelPromotionReceiptV1.from_bytes(bytes(raw_receipt))
                    except (TypeError, ValueError, CapabilityGapCorruptionError):
                        raise CapabilityGapCorruptionError(
                            "invalid_materialization_receipt"
                        ) from None
                connection.execute("COMMIT")
                return promotion, receipt
            connection.execute(
                "INSERT INTO materialization_claims (promotion_id, sink_id, receipt_bytes) "
                "VALUES (?, ?, NULL)",
                (promotion_id, sink_id),
            )
            self._validate_all(connection)
            connection.execute("COMMIT")
            return promotion, None
        except sqlite3.IntegrityError:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise CapabilityGapCollisionError("materialization_claim_collision") from None
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    def commit_materialization_receipt(
        self,
        promotion_id: str,
        sink_id: str,
        expected_receipt: FlywheelPromotionReceiptV1,
    ) -> FlywheelPromotionReceiptV1:
        if not _DIGEST.fullmatch(promotion_id) or not _DIGEST.fullmatch(sink_id):
            raise CapabilityGapValidationError("invalid_materialization_claim")
        if not isinstance(expected_receipt, FlywheelPromotionReceiptV1):
            raise CapabilityGapValidationError("invalid_materialization_receipt")
        connection = self._connection
        try:
            connection.execute("BEGIN IMMEDIATE")
            self._validate_schema()
            self._integrity(connection)
            self._validate_all(connection)
            row = connection.execute(
                "SELECT * FROM resolution_packages WHERE promotion_id=?", (promotion_id,)
            ).fetchone()
            if row is None:
                raise CapabilityGapUnavailableError("unknown_promotion")
            _, promotion = self._decode_row(row)
            if promotion is None:
                raise CapabilityGapUnavailableError("nonaccepted_promotion")
            expected = FlywheelPromotionReceiptV1.for_bundle(promotion, sink_id)
            if expected_receipt.to_bytes() != expected.to_bytes():
                raise CapabilityGapCollisionError("materialization_receipt_collision")
            claim = connection.execute(
                "SELECT * FROM materialization_claims WHERE promotion_id=?", (promotion_id,)
            ).fetchone()
            if claim is None:
                raise CapabilityGapCollisionError("materialization_claim_missing")
            if str(claim["sink_id"]) != sink_id:
                raise CapabilityGapCollisionError("materialization_sink_collision")
            raw_receipt = claim["receipt_bytes"]
            if raw_receipt is not None:
                try:
                    existing = FlywheelPromotionReceiptV1.from_bytes(bytes(raw_receipt))
                except (TypeError, ValueError, CapabilityGapCorruptionError):
                    raise CapabilityGapCorruptionError("invalid_materialization_receipt") from None
                if existing.to_bytes() != expected_receipt.to_bytes():
                    raise CapabilityGapCollisionError("materialization_receipt_collision")
                connection.execute("COMMIT")
                return existing
            updated = connection.execute(
                "UPDATE materialization_claims SET receipt_bytes=? "
                "WHERE promotion_id=? AND sink_id=? AND receipt_bytes IS NULL",
                (expected_receipt.to_bytes(), promotion_id, sink_id),
            ).rowcount
            if updated != 1:
                raise CapabilityGapCollisionError("materialization_receipt_collision")
            self._validate_all(connection)
            connection.execute("COMMIT")
            return expected_receipt
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise


def _decode_promotion(data: bytes) -> FlywheelPromotionBundleV1:
    return FlywheelPromotionBundleV1.from_bytes(data)


__all__ = ["SCHEMA_VERSION"]
