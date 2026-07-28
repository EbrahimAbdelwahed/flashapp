from __future__ import annotations

from dataclasses import fields
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
    ActiveWorkKind,
    ActiveWorkSnapshot,
    CapabilityGapCollisionError,
    DeliveryImportContext,
    InMemoryActiveWorkIndex,
    ReproductionRegistry,
    ReproductionResult,
    ReproductionStatus,
    SQLiteCapabilityGapStore,
)


def dimensions(
    operation: RequestedOperationKind = RequestedOperationKind.INGEST_SOURCE,
) -> GapOutboxDimensions:
    return GapOutboxDimensions(
        category=GapCategory.INPUT_FORMAT,
        requested_operation_kind=operation,
        safe_target_kind=SafeTargetKind.PDF,
        limitation_code=TrustedLimitationCode.UNSUPPORTED_FORMAT,
        contract_major=1,
        contract_identity_fingerprint="a" * 64,
    )


def record(
    key: str,
    *,
    operation: RequestedOperationKind = RequestedOperationKind.INGEST_SOURCE,
    count: int = 1,
    offset: int = 0,
) -> GapOutboxRecord:
    at = datetime(2026, 1, 1, tzinfo=UTC) + timedelta(days=offset)
    return GapOutboxRecord(
        gap_key=GapKeyV1(key),
        dimensions=dimensions(operation),
        verification_kind=VerificationKind.VERIFIED_RUNTIME_FAILURE,
        impact_kind=ImpactKind.BLOCKED,
        first_seen=at,
        last_seen=at,
        occurrence_count=count,
    )


def bundle(*records: GapOutboxRecord) -> tuple[bytes, str]:
    value = GapOutboxBundle("e" * 64, tuple(sorted(records, key=lambda item: item.gap_key.value)))
    return value.to_bytes(), value.bundle_fingerprint


def context(payload: bytes, fingerprint: str, seed: str = "f") -> DeliveryImportContext:
    del payload
    return DeliveryImportContext(seed * 64, fingerprint)


def test_import_retry_reopen_does_not_call_callbacks_again(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("1" * 64, count=2))
    active_calls = 0
    reproduction_calls = 0

    class Index(InMemoryActiveWorkIndex):
        def matches(
            self, gap_key: str, dimensions: GapOutboxDimensions
        ) -> tuple[ActiveWorkSnapshot, ...]:
            nonlocal active_calls
            active_calls += 1
            return super().matches(gap_key, dimensions)

    registry = ReproductionRegistry()

    def reproduce(value: GapOutboxRecord) -> ReproductionResult:
        nonlocal reproduction_calls
        reproduction_calls += 1
        assert value.gap_key.value == "1" * 64
        return ReproductionResult(ReproductionStatus.REPRODUCED, "2" * 64)

    registry.register("fixture@1", dimensions(), reproduce)
    database = tmp_path / "gap.sqlite3"
    import_context = context(payload, fingerprint)
    with SQLiteCapabilityGapStore(database) as store:
        first = store.import_bundle(
            payload,
            import_context,
            active_work=Index((ActiveWorkSnapshot("1" * 64, ActiveWorkKind.BEAD, "GAP-1"),)),
            reproduction=registry,
        )
        assert store.get_candidate("1" * 64).occurrence_count == 2
    with SQLiteCapabilityGapStore(database) as reopened:
        second = reopened.import_bundle(
            payload,
            import_context,
            active_work=Index((ActiveWorkSnapshot("1" * 64, ActiveWorkKind.BEAD, "GAP-1"),)),
            reproduction=registry,
        )
        assert second.to_bytes() == first.to_bytes()
        snapshot = reopened.get_candidate("1" * 64)
        assert snapshot.active_work == (ActiveWorkSnapshot("1" * 64, ActiveWorkKind.BEAD, "GAP-1"),)
        assert snapshot.contributions[0].reproduction.status is ReproductionStatus.REPRODUCED
    assert active_calls == 1
    assert reproduction_calls == 1


def test_distinct_deliveries_contribute_once_each(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("2" * 64, count=3))
    database = tmp_path / "gap.sqlite3"
    with SQLiteCapabilityGapStore(database) as store:
        store.import_bundle(payload, context(payload, fingerprint, "a"))
        store.import_bundle(payload, context(payload, fingerprint, "b"))
        store.import_bundle(payload, context(payload, fingerprint, "a"))
        candidate = store.get_candidate("2" * 64)
        assert candidate.occurrence_count == 6
        assert len(candidate.contributions) == 2


def test_delivery_claim_collision_does_not_mutate_store(tmp_path: Path) -> None:
    first_payload, first_fingerprint = bundle(record("2" * 64, count=1))
    second_payload, second_fingerprint = bundle(record("3" * 64, count=1))
    database = tmp_path / "gap.sqlite3"
    claim = context(first_payload, first_fingerprint, "a")
    with SQLiteCapabilityGapStore(database) as store:
        store.import_bundle(first_payload, claim)
        with pytest.raises(CapabilityGapCollisionError, match="delivery_import_collision"):
            store.import_bundle(
                second_payload,
                DeliveryImportContext(claim.delivery_import_id, second_fingerprint),
            )
        assert tuple(item.gap_key for item in store.list_candidates()) == ("2" * 64,)


def test_candidate_dimension_collision_rolls_back_whole_delivery(tmp_path: Path) -> None:
    original, original_fp = bundle(record("3" * 64))
    changed, changed_fp = bundle(record("3" * 64, operation=RequestedOperationKind.EXTRACT_TEXT))
    database = tmp_path / "gap.sqlite3"
    with SQLiteCapabilityGapStore(database) as store:
        store.import_bundle(original, context(original, original_fp, "a"))
        with pytest.raises(CapabilityGapCollisionError, match="candidate_dimensions_collision"):
            store.import_bundle(changed, context(changed, changed_fp, "b"))
        assert len(store.get_candidate("3" * 64).contributions) == 1


def test_fixture_exception_rolls_back_every_record(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("4" * 64), record("5" * 64))
    calls = 0
    registry = ReproductionRegistry()

    def fail(value: GapOutboxRecord) -> ReproductionResult:
        nonlocal calls
        calls += 1
        if value.gap_key.value == "5" * 64:
            raise RuntimeError("fixture failed")
        return ReproductionResult(ReproductionStatus.NOT_REPRODUCED, "6" * 64)

    registry.register("fixture@1", dimensions(), fail)
    database = tmp_path / "gap.sqlite3"
    with SQLiteCapabilityGapStore(database) as store:
        with pytest.raises(RuntimeError, match="fixture failed"):
            store.import_bundle(payload, context(payload, fingerprint), reproduction=registry)
        assert store.list_candidates() == ()
    assert calls == 2


def test_huge_occurrence_count_is_aggregated_in_python(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("7" * 64, count=2**63 + 9))
    with SQLiteCapabilityGapStore(tmp_path / "gap.sqlite3") as store:
        store.import_bundle(payload, context(payload, fingerprint))
        assert store.get_candidate("7" * 64).occurrence_count == 2**63 + 9


def test_different_operation_kinds_remain_separate_candidates(tmp_path: Path) -> None:
    payload, fingerprint = bundle(
        record("8" * 64, operation=RequestedOperationKind.INGEST_SOURCE),
        record("9" * 64, operation=RequestedOperationKind.EXTRACT_TEXT),
    )
    with SQLiteCapabilityGapStore(tmp_path / "gap.sqlite3") as store:
        store.import_bundle(payload, context(payload, fingerprint))
        values = store.list_candidates()
        assert len(values) == 2
        assert {item.dimensions.requested_operation_kind for item in values} == {
            RequestedOperationKind.INGEST_SOURCE,
            RequestedOperationKind.EXTRACT_TEXT,
        }


def test_snapshots_do_not_expose_delivery_identity(tmp_path: Path) -> None:
    payload, fingerprint = bundle(record("a" * 64))
    with SQLiteCapabilityGapStore(tmp_path / "gap.sqlite3") as store:
        store.import_bundle(payload, context(payload, fingerprint))
        snapshot = store.get_candidate("a" * 64)
        assert all(field.name != "delivery_import_id" for field in fields(snapshot))
