from __future__ import annotations

from study_agent.feedback.contracts import (
    GapCategory,
    RequestedOperationKind,
    SafeTargetKind,
    TrustedLimitationCode,
)
from study_agent.feedback.outbox import GapOutboxDimensions

from study_agent_devkit.capability_gap import (
    DeliveryImportContext,
    ImportReceiptV1,
    ReproductionEvidence,
    ReproductionStatus,
)


def _dimensions() -> GapOutboxDimensions:
    return GapOutboxDimensions(
        category=GapCategory.INPUT_FORMAT,
        requested_operation_kind=RequestedOperationKind.INGEST_SOURCE,
        safe_target_kind=SafeTargetKind.PDF,
        limitation_code=TrustedLimitationCode.UNSUPPORTED_FORMAT,
        contract_major=1,
        contract_identity_fingerprint="a" * 64,
    )


def test_local_context_uses_exact_domain_separated_preimage() -> None:
    context = DeliveryImportContext.for_local_bundle("c" * 64)
    assert context.delivery_import_id == (
        "44d2975ee89143b5ed40ada11a9771a6240d4823915709160b9cd3d221e616e5"
    )


def test_receipt_has_exact_canonical_fields_and_roundtrips() -> None:
    receipt = ImportReceiptV1("d" * 64, ("a" * 64, "b" * 64))
    assert ImportReceiptV1.from_bytes(receipt.to_bytes()) == receipt
    import json

    assert set(json.loads(receipt.to_bytes())) == {
        "schema_version",
        "bundle_fingerprint",
        "candidate_gap_keys",
    }


def test_reproduction_missing_fixture_has_no_evidence() -> None:
    value = ReproductionEvidence(ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT, None, None)
    assert value.fixture_id is None
    assert value.evidence_digest is None
