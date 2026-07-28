from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

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
    ImportReceiptV1,
    SQLiteCapabilityGapStore,
)


def _payload() -> bytes:
    dimensions = GapOutboxDimensions(
        category=GapCategory.INPUT_FORMAT,
        requested_operation_kind=RequestedOperationKind.INGEST_SOURCE,
        safe_target_kind=SafeTargetKind.PDF,
        limitation_code=TrustedLimitationCode.UNSUPPORTED_FORMAT,
        contract_major=1,
        contract_identity_fingerprint="a" * 64,
    )
    record = GapOutboxRecord(
        gap_key=GapKeyV1("c" * 64),
        dimensions=dimensions,
        verification_kind=VerificationKind.VERIFIED_RUNTIME_FAILURE,
        impact_kind=ImpactKind.BLOCKED,
        first_seen=datetime(2026, 1, 1, tzinfo=UTC),
        last_seen=datetime(2026, 1, 1, tzinfo=UTC),
        occurrence_count=1,
    )
    return GapOutboxBundle("e" * 64, (record,)).to_bytes()


def test_local_delivery_context_matches_bundle_fingerprint(tmp_path: Path) -> None:
    payload = _payload()
    from study_agent.feedback.outbox import GapOutboxBundle

    bundle = GapOutboxBundle.from_bytes(payload)
    context = DeliveryImportContext.for_local_bundle(bundle.bundle_fingerprint)
    with SQLiteCapabilityGapStore(tmp_path / "gaps.sqlite3") as store:
        receipt = store.import_bundle(payload, context)
    assert ImportReceiptV1.from_bytes(receipt.to_bytes()) == receipt
