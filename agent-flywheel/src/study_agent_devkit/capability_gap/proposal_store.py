"""Fail-closed SQLite persistence for immutable proposal packages."""

from __future__ import annotations

import re
import sqlite3
from collections.abc import Callable, Iterable
from contextlib import suppress
from typing import TypeVar

from .contracts import (
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
)
from .proposal_contracts import (
    MAX_CANDIDATES,
    MAX_PACKAGE_BYTES,
    ProposalDecisionPackageV1,
)

SCHEMA_VERSION = 1
_DDL = {
    "proposal_packages": """CREATE TABLE proposal_packages (
        proposal_pk INTEGER PRIMARY KEY,
        proposal_id TEXT NOT NULL UNIQUE,
        decision_id TEXT NOT NULL UNIQUE,
        cohort_fingerprint TEXT NOT NULL UNIQUE,
        package_bytes BLOB NOT NULL
    )""",
    "proposal_members": """CREATE TABLE proposal_members (
        proposal_pk INTEGER NOT NULL REFERENCES proposal_packages(proposal_pk) ON DELETE CASCADE,
        gap_key TEXT NOT NULL UNIQUE
    )""",
}
_COLUMNS = {
    "proposal_packages": (
        ("proposal_pk", "INTEGER", 0, None, 1),
        ("proposal_id", "TEXT", 1, None, 0),
        ("decision_id", "TEXT", 1, None, 0),
        ("cohort_fingerprint", "TEXT", 1, None, 0),
        ("package_bytes", "BLOB", 1, None, 0),
    ),
    "proposal_members": (
        ("proposal_pk", "INTEGER", 1, None, 0),
        ("gap_key", "TEXT", 1, None, 0),
    ),
}
_FKS = {
    "proposal_packages": (),
    "proposal_members": (
        ("proposal_packages", "proposal_pk", "proposal_pk", "NO ACTION", "CASCADE", "NONE"),
    ),
}
_INDEXES = {
    "proposal_packages": frozenset(
        {
            (1, "u", 0, ("cohort_fingerprint",)),
            (1, "u", 0, ("decision_id",)),
            (1, "u", 0, ("proposal_id",)),
        }
    ),
    "proposal_members": frozenset({(1, "u", 0, ("gap_key",))}),
}
_T = TypeVar("_T")


def _ddl_tokens(sql: str) -> tuple[str, ...]:
    pattern = (
        r"'[^']*(?:''[^']*)*'|\"[^\"]*(?:\"\"[^\"]*)*\"|"
        r"[a-z_][a-z0-9_]*|\d+|<>|!=|<=|>=|[(),.;=<>*+\-/]"
    )
    return tuple(re.findall(pattern, sql.lower()))


_GAP_KEY = re.compile(r"^[0-9a-f]{64}$")


class _SQLiteProposalStore:
    """Separate immutable package store; no resolution or update operation exists."""

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

    def __enter__(self) -> _SQLiteProposalStore:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def _initialize_schema(self) -> None:
        try:
            current = self._connection.execute("PRAGMA user_version").fetchone()[0]
        except sqlite3.DatabaseError as error:
            raise CapabilityGapCorruptionError("invalid_schema_version") from error
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
            try:
                self._connection.execute("BEGIN IMMEDIATE")
                self._connection.execute(_DDL["proposal_packages"])
                self._connection.execute(_DDL["proposal_members"])
                self._connection.execute("PRAGMA user_version = 1")
                self._connection.execute("COMMIT")
            except BaseException:
                with suppress(Exception):
                    self._connection.execute("ROLLBACK")
                raise CapabilityGapCorruptionError("schema_initialization_failed") from None
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
            fks = tuple(
                sorted(
                    (
                        str(item[2]),
                        str(item[3]),
                        str(item[4]),
                        str(item[5]).upper(),
                        str(item[6]).upper(),
                        str(item[7]).upper(),
                    )
                    for item in self._connection.execute(
                        f"PRAGMA foreign_key_list({table})"
                    ).fetchall()
                )
            )
            if fks != tuple(sorted(_FKS[table])):
                raise CapabilityGapCorruptionError("invalid_schema_foreign_keys")

    @staticmethod
    def _integrity(connection: sqlite3.Connection) -> None:
        if connection.execute("PRAGMA foreign_key_check").fetchall():
            raise CapabilityGapCorruptionError("stored_foreign_key_violation")
        result = connection.execute("PRAGMA integrity_check").fetchall()
        if len(result) != 1 or str(result[0][0]).lower() != "ok":
            raise CapabilityGapCorruptionError("stored_integrity_violation")

    def _decode_row(
        self, connection: sqlite3.Connection, row: sqlite3.Row
    ) -> ProposalDecisionPackageV1:
        package_value = row["package_bytes"]
        if type(package_value) is not bytes:
            raise CapabilityGapCorruptionError("invalid_stored_package_bytes")
        if len(package_value) > MAX_PACKAGE_BYTES:
            raise CapabilityGapCorruptionError("oversized_stored_package")
        package_bytes = package_value
        package = ProposalDecisionPackageV1.from_bytes(package_bytes)
        if (
            str(row["proposal_id"]) != package.proposal.proposal_id
            or str(row["decision_id"]) != package.decision.decision_id
            or str(row["cohort_fingerprint"]) != package.proposal.cohort_fingerprint
        ):
            raise CapabilityGapCorruptionError("stored_projection_mismatch")
        members = tuple(
            str(item[0])
            for item in connection.execute(
                "SELECT gap_key FROM proposal_members WHERE proposal_pk=? ORDER BY gap_key",
                (int(row["proposal_pk"]),),
            ).fetchall()
        )
        if members != package.proposal.evidence.candidate_gap_keys:
            raise CapabilityGapCorruptionError("stored_membership_mismatch")
        return package

    def _validate_all(self, connection: sqlite3.Connection) -> None:
        """Decode every package and membership row before exposing any result."""
        package_rows = connection.execute(
            "SELECT * FROM proposal_packages ORDER BY proposal_pk"
        ).fetchall()
        package_pks = {int(row["proposal_pk"]) for row in package_rows}
        for row in package_rows:
            self._decode_row(connection, row)
        member_rows = connection.execute(
            "SELECT proposal_pk, gap_key FROM proposal_members ORDER BY proposal_pk, gap_key"
        ).fetchall()
        if any(int(row["proposal_pk"]) not in package_pks for row in member_rows):
            raise CapabilityGapCorruptionError("stored_member_package_missing")
        if package_pks and not member_rows:
            raise CapabilityGapCorruptionError("stored_membership_missing")

    def _read(self, callback: Callable[[sqlite3.Connection], _T]) -> _T:
        self._connection.execute("BEGIN")
        try:
            self._integrity(self._connection)
            self._validate_all(self._connection)
            result = callback(self._connection)
            self._connection.execute("COMMIT")
            return result
        except BaseException:
            with suppress(Exception):
                self._connection.execute("ROLLBACK")
            raise

    def lookup(self, gap_keys: Iterable[str]) -> ProposalDecisionPackageV1 | None:
        try:
            key_iter = iter(gap_keys)
        except TypeError as error:
            raise CapabilityGapValidationError("invalid_gap_keys") from error
        raw_keys: list[str] = []
        for _ in range(MAX_CANDIDATES + 1):
            try:
                key = next(key_iter)
            except StopIteration:
                break
            if type(key) is not str or _GAP_KEY.fullmatch(key) is None:
                raise CapabilityGapValidationError("invalid_gap_keys")
            raw_keys.append(key)
        if not raw_keys or len(raw_keys) > MAX_CANDIDATES:
            raise CapabilityGapValidationError("invalid_gap_keys")
        if len(raw_keys) != len(set(raw_keys)):
            raise CapabilityGapValidationError("invalid_gap_keys")
        keys = tuple(sorted(raw_keys))

        def read(connection: sqlite3.Connection) -> ProposalDecisionPackageV1 | None:
            placeholders = ",".join("?" for _ in keys)
            rows = connection.execute(
                f"SELECT proposal_pk FROM proposal_members WHERE gap_key IN ({placeholders}) "
                "ORDER BY proposal_pk",
                keys,
            ).fetchall()
            if not rows:
                return None
            package_pks = {int(row[0]) for row in rows}
            if len(package_pks) != 1 or len(rows) != len(keys):
                raise CapabilityGapCollisionError("cohort_collision")
            package_row = connection.execute(
                "SELECT * FROM proposal_packages WHERE proposal_pk=?", (next(iter(package_pks)),)
            ).fetchone()
            if package_row is None:
                raise CapabilityGapCorruptionError("stored_package_missing")
            package = self._decode_row(connection, package_row)
            if package.proposal.evidence.candidate_gap_keys != keys:
                raise CapabilityGapCollisionError("cohort_collision")
            return package

        return self._read(read)

    def get_by_gap_key(self, gap_key: str) -> ProposalDecisionPackageV1 | None:
        if type(gap_key) is not str or _GAP_KEY.fullmatch(gap_key) is None:
            raise CapabilityGapValidationError("invalid_gap_keys")

        def read(connection: sqlite3.Connection) -> ProposalDecisionPackageV1 | None:
            member = connection.execute(
                "SELECT proposal_pk FROM proposal_members WHERE gap_key=?", (gap_key,)
            ).fetchone()
            if member is None:
                return None
            package_row = connection.execute(
                "SELECT * FROM proposal_packages WHERE proposal_pk=?", (int(member[0]),)
            ).fetchone()
            if package_row is None:
                raise CapabilityGapCorruptionError("stored_package_missing")
            return self._decode_row(connection, package_row)

        return self._read(read)

    def get_by_decision_id(self, decision_id: str) -> ProposalDecisionPackageV1 | None:
        if type(decision_id) is not str or _GAP_KEY.fullmatch(decision_id) is None:
            raise CapabilityGapValidationError("invalid_decision_id")

        def read(connection: sqlite3.Connection) -> ProposalDecisionPackageV1 | None:
            row = connection.execute(
                "SELECT * FROM proposal_packages WHERE decision_id=?", (decision_id,)
            ).fetchone()
            return None if row is None else self._decode_row(connection, row)

        return self._read(read)

    def get_by_proposal_id(self, proposal_id: str) -> ProposalDecisionPackageV1 | None:
        if type(proposal_id) is not str or _GAP_KEY.fullmatch(proposal_id) is None:
            raise CapabilityGapValidationError("invalid_proposal_id")

        def read(connection: sqlite3.Connection) -> ProposalDecisionPackageV1 | None:
            row = connection.execute(
                "SELECT * FROM proposal_packages WHERE proposal_id=?", (proposal_id,)
            ).fetchone()
            return None if row is None else self._decode_row(connection, row)

        return self._read(read)

    def _create_or_get(self, package: ProposalDecisionPackageV1) -> ProposalDecisionPackageV1:
        if not isinstance(package, ProposalDecisionPackageV1):
            raise CapabilityGapValidationError("invalid_package")
        keys = package.proposal.evidence.candidate_gap_keys
        package_bytes = package.to_bytes()

        def write(connection: sqlite3.Connection) -> ProposalDecisionPackageV1:
            placeholders = ",".join("?" for _ in keys)
            rows = connection.execute(
                f"SELECT proposal_pk FROM proposal_members WHERE gap_key IN ({placeholders}) "
                "ORDER BY proposal_pk",
                keys,
            ).fetchall()
            if rows:
                package_pks = {int(row[0]) for row in rows}
                if len(package_pks) != 1 or len(rows) != len(keys):
                    raise CapabilityGapCollisionError("cohort_collision")
                existing_row = connection.execute(
                    "SELECT * FROM proposal_packages WHERE proposal_pk=?",
                    (next(iter(package_pks)),),
                ).fetchone()
                if existing_row is None:
                    raise CapabilityGapCorruptionError("stored_package_missing")
                existing = self._decode_row(connection, existing_row)
                if existing.proposal.evidence.candidate_gap_keys != keys:
                    raise CapabilityGapCollisionError("cohort_collision")
                return existing
            try:
                cursor = connection.execute(
                    "INSERT INTO proposal_packages "
                    "(proposal_id, decision_id, cohort_fingerprint, package_bytes) "
                    "VALUES (?, ?, ?, ?)",
                    (
                        package.proposal.proposal_id,
                        package.decision.decision_id,
                        package.proposal.cohort_fingerprint,
                        package_bytes,
                    ),
                )
                if cursor.lastrowid is None:
                    raise CapabilityGapCorruptionError("missing_package_rowid")
                package_pk = int(cursor.lastrowid)
                for key in keys:
                    connection.execute(
                        "INSERT INTO proposal_members (proposal_pk, gap_key) VALUES (?, ?)",
                        (package_pk, key),
                    )
            except sqlite3.IntegrityError as error:
                raise CapabilityGapCollisionError("cohort_collision") from error
            return package

        self._connection.execute("BEGIN IMMEDIATE")
        try:
            self._integrity(self._connection)
            self._validate_all(self._connection)
            result = write(self._connection)
            self._connection.execute("COMMIT")
            return result
        except BaseException:
            with suppress(Exception):
                self._connection.execute("ROLLBACK")
            raise


__all__ = ["SCHEMA_VERSION"]
