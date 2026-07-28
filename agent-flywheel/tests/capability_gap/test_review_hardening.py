from __future__ import annotations

import json
import sqlite3
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from study_agent.feedback.contracts import (
    GapCategory,
    GapKeyV1,
    ImpactKind,
    RequestedOperationKind,
    SafeTargetKind,
    TrustedLimitationCode,
    VerificationKind,
)
from study_agent.feedback.outbox import GapOutboxBundle, GapOutboxDimensions, GapOutboxRecord

from study_agent_devkit.capability_gap import (
    CandidateSnapshot,
    CapabilityGapCorruptionError,
    ContributionSnapshot,
    DeliveryImportContext,
    ImportReceiptV1,
    ReproductionEvidence,
    ReproductionRegistry,
    ReproductionResult,
    ReproductionStatus,
    SQLiteCapabilityGapStore,
)


def dimensions() -> GapOutboxDimensions:
    return GapOutboxDimensions(
        category=GapCategory.INPUT_FORMAT,
        requested_operation_kind=RequestedOperationKind.INGEST_SOURCE,
        safe_target_kind=SafeTargetKind.PDF,
        limitation_code=TrustedLimitationCode.UNSUPPORTED_FORMAT,
        contract_major=1,
        contract_identity_fingerprint="a" * 64,
    )


def record(key: str, *, count: int = 1, offset: int = 0) -> GapOutboxRecord:
    timestamp = datetime(2026, 1, 1, tzinfo=UTC) + timedelta(days=offset)
    return GapOutboxRecord(
        gap_key=GapKeyV1(key),
        dimensions=dimensions(),
        verification_kind=VerificationKind.VERIFIED_RUNTIME_FAILURE,
        impact_kind=ImpactKind.BLOCKED,
        first_seen=timestamp,
        last_seen=timestamp,
        occurrence_count=count,
    )


def bundle(value: GapOutboxRecord) -> tuple[bytes, str]:
    outbox = GapOutboxBundle("e" * 64, (value,))
    return outbox.to_bytes(), outbox.bundle_fingerprint


def context(payload: bytes, fingerprint: str, seed: str = "a") -> DeliveryImportContext:
    del payload
    return DeliveryImportContext(seed * 64, fingerprint)


def test_candidate_snapshot_is_stable_when_delivery_order_reverses(tmp_path: Path) -> None:
    first, first_fingerprint = bundle(record("a" * 64, count=2, offset=0))
    second, second_fingerprint = bundle(record("a" * 64, count=3, offset=1))
    left_path = tmp_path / "left.sqlite3"
    right_path = tmp_path / "right.sqlite3"
    with SQLiteCapabilityGapStore(left_path) as store:
        store.import_bundle(first, context(first, first_fingerprint, "a"))
        store.import_bundle(second, context(second, second_fingerprint, "b"))
        left = store.get_candidate("a" * 64)
    with SQLiteCapabilityGapStore(right_path) as store:
        store.import_bundle(second, context(second, second_fingerprint, "b"))
        store.import_bundle(first, context(first, first_fingerprint, "a"))
        right = store.get_candidate("a" * 64)
    assert left == right


def test_receipt_boolean_schema_version_is_rejected() -> None:
    data = json.dumps(
        {"bundle_fingerprint": "a" * 64, "candidate_gap_keys": [], "schema_version": True},
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    with pytest.raises(CapabilityGapCorruptionError):
        ImportReceiptV1.from_bytes(data)


def test_forged_candidate_aggregate_dimensions_and_count_are_rejected() -> None:
    value = record("b" * 64, count=2)
    contribution = ContributionSnapshot(
        value.gap_key.value,
        value.dimensions,
        value.to_bytes(),
        # A missing fixture is a valid persisted evidence state.
        ReproductionEvidence(ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT, None, None),
    )
    with pytest.raises(CapabilityGapCorruptionError):
        CandidateSnapshot(
            value.gap_key.value,
            value.dimensions,
            (contribution,),
            1,
            value.first_seen,
            value.last_seen,
            (),
        )


def test_corrupt_retry_does_not_invoke_reproduction(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("c" * 64))
    calls = 0
    registry = ReproductionRegistry()

    def callback(_record: GapOutboxRecord) -> ReproductionResult:
        nonlocal calls
        calls += 1
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry.register("fixture@corrupt", dimensions(), callback)
    with SQLiteCapabilityGapStore(tmp_path / "corrupt.sqlite3") as store:
        store.import_bundle(payload, context(payload, fingerprint), reproduction=registry)
        store.connection.execute("UPDATE deliveries SET receipt_bytes = ?", (b"{}",))
        with pytest.raises(CapabilityGapCorruptionError, match="stored_receipt_mismatch"):
            store.import_bundle(payload, context(payload, fingerprint), reproduction=registry)
    assert calls == 1


def test_exact_retry_rejects_corrupt_derived_candidate(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("f" * 64))
    with SQLiteCapabilityGapStore(tmp_path / "candidate-corrupt.sqlite3") as store:
        store.import_bundle(payload, context(payload, fingerprint))
        store.connection.execute(
            "UPDATE candidates SET dimensions_bytes = ? WHERE gap_key = ?",
            (b"{}", "f" * 64),
        )
        with pytest.raises(
            CapabilityGapCorruptionError, match="stored_candidate_dimensions_mismatch"
        ):
            store.import_bundle(payload, context(payload, fingerprint))


def test_retry_validates_reproduction_for_all_candidate_contributions(
    tmp_path: Path,
) -> None:
    payload, fingerprint = bundle(record("0" * 64))
    first_context = context(payload, fingerprint, "a")
    second_context = context(payload, fingerprint, "b")
    calls = 0

    def callback(_record: GapOutboxRecord) -> ReproductionResult:
        nonlocal calls
        calls += 1
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry = ReproductionRegistry()
    registry.register("fixture@retry-all", dimensions(), callback)
    with SQLiteCapabilityGapStore(tmp_path / "retry-all.sqlite3") as store:
        store.import_bundle(payload, first_context)
        store.import_bundle(payload, second_context)
        second_delivery_pk = store.connection.execute(
            "SELECT delivery_pk FROM deliveries WHERE delivery_import_id = ?",
            (second_context.delivery_import_id,),
        ).fetchone()[0]
        store.connection.execute(
            "DELETE FROM reproductions WHERE contribution_pk = "
            "(SELECT contribution_pk FROM contributions WHERE delivery_pk = ?)",
            (second_delivery_pk,),
        )
        with pytest.raises(CapabilityGapCorruptionError, match="stored_reproduction_mismatch"):
            store.import_bundle(payload, first_context, reproduction=registry)
    assert calls == 0


def test_noncanonical_stored_dimensions_are_rejected(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("d" * 64))
    with SQLiteCapabilityGapStore(tmp_path / "dimensions.sqlite3") as store:
        store.import_bundle(payload, context(payload, fingerprint))
        raw = bytes(
            store.connection.execute(
                "SELECT dimensions_bytes FROM candidates WHERE gap_key = ?", ("d" * 64,)
            ).fetchone()[0]
        )
        value = json.loads(raw)
        noncanonical = json.dumps(value, separators=(",", ":")).encode()
        if noncanonical == raw:
            noncanonical = json.dumps(value, indent=1).encode()
        store.connection.execute(
            "UPDATE candidates SET dimensions_bytes = ? WHERE gap_key = ?",
            (noncanonical, "d" * 64),
        )
        with pytest.raises(CapabilityGapCorruptionError):
            store.get_candidate("d" * 64)


def test_keyboard_interrupt_rolls_back_and_connection_remains_usable(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("e" * 64))
    registry = ReproductionRegistry()

    def callback(_record: GapOutboxRecord) -> ReproductionResult:
        raise KeyboardInterrupt

    registry.register("fixture@interrupt", dimensions(), callback)
    with SQLiteCapabilityGapStore(tmp_path / "interrupt.sqlite3") as store:
        with pytest.raises(KeyboardInterrupt):
            store.import_bundle(payload, context(payload, fingerprint), reproduction=registry)
        assert store.list_candidates() == ()
        receipt = store.import_bundle(payload, context(payload, fingerprint))
        assert receipt.bundle_fingerprint == fingerprint


def test_unexpected_schema_objects_are_rejected(tmp_path: Path) -> None:
    database = tmp_path / "schema.sqlite3"
    with SQLiteCapabilityGapStore(database):
        pass
    connection = sqlite3.connect(database)
    try:
        connection.execute("CREATE VIEW unexpected_view AS SELECT 1")
        connection.commit()
    finally:
        connection.close()
    with pytest.raises(CapabilityGapCorruptionError, match="invalid_schema_tables"):
        SQLiteCapabilityGapStore(database)


def test_schema_extra_index_is_rejected(tmp_path: Path) -> None:
    database = tmp_path / "extra-index.sqlite3"
    with SQLiteCapabilityGapStore(database):
        pass
    connection = sqlite3.connect(database)
    try:
        connection.execute("CREATE INDEX extra_contribution_key ON contributions(gap_key)")
        connection.commit()
    finally:
        connection.close()
    with pytest.raises(CapabilityGapCorruptionError, match="invalid_schema_indexes"):
        SQLiteCapabilityGapStore(database)


def test_schema_check_drift_is_rejected(tmp_path: Path) -> None:
    database = tmp_path / "check-drift.sqlite3"
    with SQLiteCapabilityGapStore(database):
        pass
    connection = sqlite3.connect(database)
    try:
        connection.execute("PRAGMA writable_schema = ON")
        connection.execute(
            "UPDATE sqlite_master SET sql = sql || ' CHECK (1)' "
            "WHERE type = 'table' AND name = 'deliveries'"
        )
        connection.commit()
    finally:
        connection.close()
    with pytest.raises(CapabilityGapCorruptionError, match="invalid_schema_ddl"):
        SQLiteCapabilityGapStore(database)
