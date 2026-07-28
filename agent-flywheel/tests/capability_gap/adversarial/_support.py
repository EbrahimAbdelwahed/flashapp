from __future__ import annotations

from datetime import UTC, datetime, timedelta
from multiprocessing.synchronize import Event
from pathlib import Path
from typing import Any

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
    DeliveryImportContext,
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
    count: int = 1,
    operation: RequestedOperationKind = RequestedOperationKind.INGEST_SOURCE,
    offset: int = 0,
) -> GapOutboxRecord:
    timestamp = datetime(2026, 1, 1, tzinfo=UTC) + timedelta(days=offset)
    return GapOutboxRecord(
        gap_key=GapKeyV1(key),
        dimensions=dimensions(operation),
        verification_kind=VerificationKind.VERIFIED_RUNTIME_FAILURE,
        impact_kind=ImpactKind.BLOCKED,
        first_seen=timestamp,
        last_seen=timestamp,
        occurrence_count=count,
    )


def bundle(*records: GapOutboxRecord) -> tuple[bytes, str]:
    value = GapOutboxBundle("e" * 64, tuple(sorted(records, key=lambda item: item.gap_key.value)))
    return value.to_bytes(), value.bundle_fingerprint


def context(fingerprint: str, seed: str = "a") -> DeliveryImportContext:
    return DeliveryImportContext(seed * 64, fingerprint)


def blocking_import_worker(
    payload: bytes,
    database: str,
    delivery_import_id: str,
    bundle_fingerprint: str,
    entered: Event,
    release: Event,
) -> None:
    """Enter a callback during BEGIN IMMEDIATE, then wait for parent kill."""

    registry = ReproductionRegistry()

    def callback(_record: GapOutboxRecord) -> ReproductionResult:
        entered.set()
        release.wait(timeout=30)
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry.register("fixture@crash", dimensions(), callback)
    import_context = DeliveryImportContext(delivery_import_id, bundle_fingerprint)
    with SQLiteCapabilityGapStore(Path(database)) as store:
        store.import_bundle(payload, import_context, reproduction=registry)


def healthy_registry() -> ReproductionRegistry:
    registry = ReproductionRegistry()
    registry.register(
        "fixture@healthy",
        dimensions(),
        lambda _record: ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64),
    )
    return registry


def canonical_json(value: Any) -> bytes:
    """Serialize hostile fixture variants without importing the harness codec."""

    import json

    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )
