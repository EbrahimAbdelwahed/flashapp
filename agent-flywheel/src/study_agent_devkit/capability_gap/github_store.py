"""Separate SQLite claim and receipt store for GitHub publications."""

from __future__ import annotations

import math
import re
import secrets
import sqlite3
import time
from collections.abc import Callable
from contextlib import suppress
from typing import TypeVar

from .github_contracts import (
    GitHubPublicationCollisionError,
    GitHubPublicationCorruptionError,
    GitHubPublicationReceiptV1,
    GitHubPublicationRequestV1,
    GitHubPublicationRetryableError,
)

SCHEMA_VERSION = 2
_T = TypeVar("_T")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")


class SQLiteGitHubPublicationStore:
    """One canonical job/claim table; request bytes are the source of truth."""

    def __init__(
        self,
        database: object,
        *,
        clock: Callable[[], float] | None = None,
        lease_ttl: float = 300.0,
    ) -> None:
        if clock is not None and not callable(clock):
            raise GitHubPublicationCorruptionError("invalid_clock")
        if (
            isinstance(lease_ttl, bool)
            or not isinstance(lease_ttl, (int, float))
            or lease_ttl <= 0
            or lease_ttl > 86_400
        ):
            raise GitHubPublicationCorruptionError("invalid_lease_ttl")
        self._owns_connection = not isinstance(database, sqlite3.Connection)
        self._connection = (
            database
            if isinstance(database, sqlite3.Connection)
            else sqlite3.connect(str(database), isolation_level=None)
        )
        self._connection.row_factory = sqlite3.Row
        self._clock = clock or time.time
        self._lease_ttl = float(lease_ttl)
        self._initialize_schema()

    @property
    def connection(self) -> sqlite3.Connection:
        return self._connection

    def close(self) -> None:
        if self._owns_connection:
            self._connection.close()

    def __enter__(self) -> SQLiteGitHubPublicationStore:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def _initialize_schema(self) -> None:
        current = int(self._connection.execute("PRAGMA user_version").fetchone()[0])
        if current not in (0, 1, SCHEMA_VERSION):
            raise GitHubPublicationCorruptionError("invalid_schema_version")
        if current == 1:
            try:
                self._connection.executescript(
                    """
                    BEGIN IMMEDIATE;
                    ALTER TABLE github_publications ADD COLUMN lease_token TEXT;
                    ALTER TABLE github_publications ADD COLUMN lease_until REAL;
                    PRAGMA user_version = 2;
                    COMMIT;
                    """
                )
            except sqlite3.DatabaseError:
                raise GitHubPublicationCorruptionError("invalid_schema_version") from None
            current = SCHEMA_VERSION
        if current == SCHEMA_VERSION:
            self._validate_schema()
            return
        existing = {
            str(row[0])
            for row in self._connection.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table','view','trigger')"
            ).fetchall()
            if row[0] != "sqlite_sequence"
        }
        if existing:
            raise GitHubPublicationCorruptionError("invalid_schema_version")
        self._connection.executescript(
            """
            BEGIN IMMEDIATE;
            CREATE TABLE github_publications (
                publication_pk INTEGER PRIMARY KEY,
                publication_id TEXT NOT NULL UNIQUE,
                promotion_id TEXT NOT NULL UNIQUE,
                sink_id TEXT NOT NULL,
                owner TEXT NOT NULL,
                repository TEXT NOT NULL,
                base_ref TEXT NOT NULL,
                base_oid TEXT NOT NULL,
                request_bytes BLOB NOT NULL,
                receipt_bytes BLOB,
                lease_token TEXT,
                lease_until REAL
            );
            PRAGMA user_version = 2;
            COMMIT;
            """
        )
        self._validate_schema()

    def _validate_schema(self) -> None:
        if int(self._connection.execute("PRAGMA user_version").fetchone()[0]) != SCHEMA_VERSION:
            raise GitHubPublicationCorruptionError("invalid_schema_version")
        tables = {
            str(row[0])
            for row in self._connection.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table','view','trigger')"
            ).fetchall()
            if row[0] != "sqlite_sequence"
        }
        if tables != {"github_publications"}:
            raise GitHubPublicationCorruptionError("invalid_schema_tables")
        expected = (
            ("publication_pk", "INTEGER", 0, None, 1),
            ("publication_id", "TEXT", 1, None, 0),
            ("promotion_id", "TEXT", 1, None, 0),
            ("sink_id", "TEXT", 1, None, 0),
            ("owner", "TEXT", 1, None, 0),
            ("repository", "TEXT", 1, None, 0),
            ("base_ref", "TEXT", 1, None, 0),
            ("base_oid", "TEXT", 1, None, 0),
            ("request_bytes", "BLOB", 1, None, 0),
            ("receipt_bytes", "BLOB", 0, None, 0),
            ("lease_token", "TEXT", 0, None, 0),
            ("lease_until", "REAL", 0, None, 0),
        )
        actual = tuple(
            (str(row[1]), str(row[2]).upper(), int(row[3]), row[4], int(row[5]))
            for row in self._connection.execute("PRAGMA table_info(github_publications)").fetchall()
        )
        if actual != expected:
            raise GitHubPublicationCorruptionError("invalid_schema_columns")
        indexes: set[tuple[str, tuple[str, ...]]] = set()
        for row in self._connection.execute("PRAGMA index_list(github_publications)").fetchall():
            indexes.add(
                (
                    str(row[3]),
                    tuple(
                        str(item[2])
                        for item in self._connection.execute(
                            f"PRAGMA index_info({row[1]!s})"
                        ).fetchall()
                    ),
                )
            )
        if indexes != {("u", ("publication_id",)), ("u", ("promotion_id",))}:
            raise GitHubPublicationCorruptionError("invalid_schema_indexes")

    def _integrity(self) -> None:
        row = self._connection.execute("PRAGMA integrity_check").fetchone()
        if row is None or row[0] != "ok":
            raise GitHubPublicationCorruptionError("sqlite_integrity_failure")

    def _decode(
        self, row: sqlite3.Row
    ) -> tuple[GitHubPublicationRequestV1, GitHubPublicationReceiptV1 | None]:
        request_bytes = row["request_bytes"]
        if type(request_bytes) is not bytes:
            raise GitHubPublicationCorruptionError("invalid_request_bytes")
        request = GitHubPublicationRequestV1.from_bytes(request_bytes)
        projections = (
            "publication_id",
            "promotion_id",
            "sink_id",
            "owner",
            "repository",
            "base_ref",
            "base_oid",
        )
        if any(str(row[field]) != getattr(request, field) for field in projections):
            raise GitHubPublicationCorruptionError("request_projection_mismatch")
        receipt_bytes = row["receipt_bytes"]
        if receipt_bytes is None:
            self._validate_lease_fields(row)
            return request, None
        if type(receipt_bytes) is not bytes:
            raise GitHubPublicationCorruptionError("invalid_receipt_bytes")
        receipt = GitHubPublicationReceiptV1.from_bytes(receipt_bytes)
        if row["lease_token"] is not None or row["lease_until"] is not None:
            raise GitHubPublicationCorruptionError("receipt_has_active_lease")
        if (
            receipt.publication_id != request.publication_id
            or receipt.promotion_id != request.promotion_id
            or receipt.sink_id != request.sink_id
            or receipt.owner != request.owner
            or receipt.repository != request.repository
            or receipt.base_ref != request.base_ref
            or receipt.base_oid != request.base_oid
            or receipt.branch_name != request.branch_name
            or receipt.request_fingerprint != request.request_fingerprint
        ):
            raise GitHubPublicationCorruptionError("receipt_request_mismatch")
        return request, receipt

    @staticmethod
    def _validate_lease_fields(row: sqlite3.Row) -> None:
        token = row["lease_token"]
        until = row["lease_until"]
        if token is None and until is None:
            return
        if (
            not isinstance(token, str)
            or re.fullmatch(r"[0-9a-f]{64}", token) is None
            or type(until) not in (int, float)
            or not math.isfinite(float(until))
        ):
            raise GitHubPublicationCorruptionError("invalid_lease_fields")

    def _read(self, callback: Callable[[sqlite3.Connection], _T]) -> _T:
        self._connection.execute("BEGIN")
        try:
            self._validate_schema()
            self._integrity()
            result = callback(self._connection)
            self._connection.execute("COMMIT")
            return result
        except BaseException:
            with suppress(Exception):
                self._connection.execute("ROLLBACK")
            raise

    def get_by_publication_id(
        self, publication_id: str
    ) -> tuple[GitHubPublicationRequestV1, GitHubPublicationReceiptV1 | None] | None:
        def read(
            connection: sqlite3.Connection,
        ) -> tuple[GitHubPublicationRequestV1, GitHubPublicationReceiptV1 | None] | None:
            row = connection.execute(
                "SELECT * FROM github_publications WHERE publication_id=?", (publication_id,)
            ).fetchone()
            return None if row is None else self._decode(row)

        return self._read(read)

    def get_by_promotion_id(
        self, promotion_id: str
    ) -> tuple[GitHubPublicationRequestV1, GitHubPublicationReceiptV1 | None] | None:
        def read(
            connection: sqlite3.Connection,
        ) -> tuple[GitHubPublicationRequestV1, GitHubPublicationReceiptV1 | None] | None:
            row = connection.execute(
                "SELECT * FROM github_publications WHERE promotion_id=?", (promotion_id,)
            ).fetchone()
            return None if row is None else self._decode(row)

        return self._read(read)

    def claim(
        self, request: GitHubPublicationRequestV1
    ) -> tuple[GitHubPublicationRequestV1, GitHubPublicationReceiptV1 | None, bool]:
        request_bytes = request.to_bytes()
        connection = self._connection
        connection.execute("BEGIN IMMEDIATE")
        try:
            self._validate_schema()
            self._integrity()
            row = connection.execute(
                "SELECT * FROM github_publications WHERE promotion_id=?", (request.promotion_id,)
            ).fetchone()
            if row is not None:
                existing, receipt = self._decode(row)
                if existing.to_bytes() != request_bytes and not self._same_claim_identity(
                    existing, request
                ):
                    raise GitHubPublicationCollisionError("publication_collision")
                connection.execute("COMMIT")
                return existing, receipt, False
            by_publication = connection.execute(
                "SELECT * FROM github_publications WHERE publication_id=?",
                (request.publication_id,),
            ).fetchone()
            if by_publication is not None:
                existing, receipt = self._decode(by_publication)
                if existing.to_bytes() != request_bytes and not self._same_claim_identity(
                    existing, request
                ):
                    raise GitHubPublicationCollisionError("publication_collision")
                connection.execute("COMMIT")
                return existing, receipt, False
            connection.execute(
                "INSERT INTO github_publications "
                "(publication_id,promotion_id,sink_id,owner,repository,base_ref,base_oid,"
                "request_bytes,receipt_bytes) VALUES (?,?,?,?,?,?,?,?,NULL)",
                (
                    request.publication_id,
                    request.promotion_id,
                    request.sink_id,
                    request.owner,
                    request.repository,
                    request.base_ref,
                    request.base_oid,
                    request_bytes,
                ),
            )
            connection.execute("COMMIT")
            return request, None, True
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    @staticmethod
    def _same_claim_identity(
        left: GitHubPublicationRequestV1, right: GitHubPublicationRequestV1
    ) -> bool:
        """Allow concurrent callers with different observed base heads to converge."""
        if left.base_oid == right.base_oid:
            return False
        left_json = left.to_json()
        right_json = right.to_json()
        for key in ("base_oid", "publication_id", "request_fingerprint", "marker"):
            left_json.pop(key, None)
            right_json.pop(key, None)
        # The only base-derived text is the hidden marker embedded in the PR
        # body.  Normalize it before comparing the logical promotion payload.
        marker_pattern = re.compile(
            r"\s*<!-- study-agent-devkit:capability-gap:v1 "
            r"promotion_id=[0-9a-f]{64} request_fingerprint=[0-9a-f]{64} -->"
        )
        for payload in (left_json, right_json):
            body = payload.get("pr_body")
            if isinstance(body, str):
                payload["pr_body"] = marker_pattern.sub("", body).rstrip()
        return left_json == right_json

    def acquire_execution_lease(self, request: GitHubPublicationRequestV1) -> str:
        """Acquire a durable, expiring fencing token without holding a DB lock remotely."""
        connection = self._connection
        connection.execute("BEGIN IMMEDIATE")
        try:
            self._validate_schema()
            self._integrity()
            row = connection.execute(
                "SELECT * FROM github_publications WHERE promotion_id=?", (request.promotion_id,)
            ).fetchone()
            if row is None:
                raise GitHubPublicationCollisionError("claim_missing")
            stored, receipt = self._decode(row)
            if stored.to_bytes() != request.to_bytes():
                raise GitHubPublicationCollisionError("publication_collision")
            if receipt is not None:
                raise GitHubPublicationRetryableError("publication_already_completed")
            now = self._now()
            lease_until = row["lease_until"]
            if (
                isinstance(row["lease_token"], str)
                and type(lease_until) in (int, float)
                and float(lease_until) > now
            ):
                raise GitHubPublicationRetryableError("publication_lease_held")
            token = secrets.token_hex(32)
            connection.execute(
                "UPDATE github_publications SET lease_token=?, lease_until=? WHERE promotion_id=?",
                (token, now + self._lease_ttl, request.promotion_id),
            )
            connection.execute("COMMIT")
            return token
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    def _now(self) -> float:
        try:
            now = float(self._clock())
        except Exception:
            raise GitHubPublicationCorruptionError("invalid_clock") from None
        if not math.isfinite(now):
            raise GitHubPublicationCorruptionError("invalid_clock")
        return now

    def renew_execution_lease(self, request: GitHubPublicationRequestV1, lease_token: str) -> None:
        connection = self._connection
        connection.execute("BEGIN IMMEDIATE")
        try:
            self._validate_schema()
            self._integrity()
            row = connection.execute(
                "SELECT * FROM github_publications WHERE promotion_id=?", (request.promotion_id,)
            ).fetchone()
            if row is None:
                raise GitHubPublicationCollisionError("claim_missing")
            stored, receipt = self._decode(row)
            if stored.to_bytes() != request.to_bytes() or receipt is not None:
                raise GitHubPublicationRetryableError("publication_lease_lost")
            now = self._now()
            until = row["lease_until"]
            if (
                row["lease_token"] != lease_token
                or type(until) not in (int, float)
                or float(until) <= now
            ):
                raise GitHubPublicationRetryableError("publication_lease_lost")
            updated = connection.execute(
                "UPDATE github_publications SET lease_until=? "
                "WHERE promotion_id=? AND lease_token=?",
                (now + self._lease_ttl, request.promotion_id, lease_token),
            )
            if updated.rowcount != 1:
                raise GitHubPublicationRetryableError("publication_lease_lost")
            connection.execute("COMMIT")
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    def persist_receipt(
        self,
        request: GitHubPublicationRequestV1,
        receipt: GitHubPublicationReceiptV1,
        *,
        lease_token: str | None = None,
    ) -> None:
        if (
            receipt.publication_id != request.publication_id
            or receipt.request_fingerprint != request.request_fingerprint
            or receipt.promotion_id != request.promotion_id
            or receipt.sink_id != request.sink_id
            or receipt.owner != request.owner
            or receipt.repository != request.repository
            or receipt.base_ref != request.base_ref
            or receipt.base_oid != request.base_oid
            or receipt.branch_name != request.branch_name
        ):
            raise GitHubPublicationCollisionError("receipt_request_mismatch")
        if lease_token is None:
            raise GitHubPublicationRetryableError("publication_lease_required")
        connection = self._connection
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM github_publications WHERE promotion_id=?", (request.promotion_id,)
            ).fetchone()
            if row is None:
                raise GitHubPublicationCollisionError("claim_missing")
            stored, existing = self._decode(row)
            if stored.to_bytes() != request.to_bytes():
                raise GitHubPublicationCollisionError("publication_collision")
            if existing is not None:
                if existing.to_bytes() != receipt.to_bytes():
                    raise GitHubPublicationCollisionError("receipt_collision")
                connection.execute("COMMIT")
                return
            if lease_token is not None and row["lease_token"] != lease_token:
                raise GitHubPublicationRetryableError("publication_lease_lost")
            updated = connection.execute(
                "UPDATE github_publications SET receipt_bytes=?, lease_token=NULL, "
                "lease_until=NULL WHERE promotion_id=? AND receipt_bytes IS NULL "
                "AND (lease_token=? OR ? IS NULL)",
                (receipt.to_bytes(), request.promotion_id, lease_token, lease_token),
            )
            if updated.rowcount != 1:
                raise GitHubPublicationRetryableError("publication_lease_lost")
            connection.execute("COMMIT")
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    def release_execution_lease(
        self, request: GitHubPublicationRequestV1, lease_token: str
    ) -> None:
        connection = self._connection
        connection.execute("BEGIN IMMEDIATE")
        try:
            self._validate_schema()
            self._integrity()
            row = connection.execute(
                "SELECT * FROM github_publications WHERE promotion_id=?", (request.promotion_id,)
            ).fetchone()
            if row is None:
                raise GitHubPublicationCollisionError("claim_missing")
            self._decode(row)
            updated = connection.execute(
                "UPDATE github_publications SET lease_token=NULL, lease_until=NULL "
                "WHERE promotion_id=? AND lease_token=? AND receipt_bytes IS NULL",
                (request.promotion_id, lease_token),
            )
            if updated.rowcount != 1:
                raise GitHubPublicationRetryableError("publication_lease_lost")
            connection.execute("COMMIT")
        except BaseException:
            with suppress(Exception):
                connection.execute("ROLLBACK")
            raise

    # Friendly aliases used by hosts and scripted tests.
    get = get_by_promotion_id
    put_receipt = persist_receipt


GitHubPublicationStore = SQLiteGitHubPublicationStore

__all__ = ["SCHEMA_VERSION", "GitHubPublicationStore", "SQLiteGitHubPublicationStore"]
