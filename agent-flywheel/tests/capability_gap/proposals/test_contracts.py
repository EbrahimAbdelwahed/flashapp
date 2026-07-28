from __future__ import annotations

import base64
import json
from datetime import UTC, datetime, timedelta
from hashlib import sha256

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
from study_agent.feedback.outbox import GapOutboxDimensions, GapOutboxRecord
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    ActiveWorkKind,
    ActiveWorkSnapshot,
    CandidateSnapshot,
    CapabilityGapCorruptionError,
    ContributionSnapshot,
    ReproductionEvidence,
    ReproductionStatus,
)
from study_agent_devkit.capability_gap.proposal_contracts import (
    CohortMergeReceiptV1,
    DecisionStatus,
    DraftArtifactKind,
    DraftArtifactState,
    DraftArtifactV1,
    ImprovementProposalV1,
    ProposalContractError,
    ProposalContributionV1,
    ProposalDecisionPackageV1,
    ProposalDraftV1,
    ProposalEvidenceV1,
    ProposalOptionV1,
    RequestedAuthority,
)


def make_dimensions(seed: str = "a") -> GapOutboxDimensions:
    return GapOutboxDimensions(
        category=GapCategory.INPUT_FORMAT,
        requested_operation_kind=RequestedOperationKind.INGEST_SOURCE,
        safe_target_kind=SafeTargetKind.PDF,
        limitation_code=TrustedLimitationCode.UNSUPPORTED_FORMAT,
        contract_major=1,
        contract_identity_fingerprint=seed * 64,
    )


def make_candidate(key: str = "a" * 64, *, seed: str = "a", count: int = 2) -> CandidateSnapshot:
    dimensions = make_dimensions(seed)
    first = datetime(2026, 1, 1, tzinfo=UTC)
    record = GapOutboxRecord(
        gap_key=GapKeyV1(key),
        dimensions=dimensions,
        verification_kind=VerificationKind.VERIFIED_RUNTIME_FAILURE,
        impact_kind=ImpactKind.BLOCKED,
        first_seen=first,
        last_seen=first + timedelta(days=1),
        occurrence_count=count,
    )
    contribution = ContributionSnapshot(
        key,
        dimensions,
        record.to_bytes(),
        ReproductionEvidence(ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT, None, None),
    )
    return CandidateSnapshot(
        key,
        dimensions,
        (contribution,),
        count,
        record.first_seen,
        record.last_seen,
        (ActiveWorkSnapshot(key, ActiveWorkKind.BEAD, "GAP-TEST"),),
    )


def make_draft() -> ProposalDraftV1:
    return ProposalDraftV1(
        schema_version=1,
        options=(
            ProposalOptionV1("safe", "Keep the current boundary", ("slower",)),
            ProposalOptionV1("small", "Add a narrow implementation", ("review cost",)),
        ),
        recommended_option_id="safe",
        artifacts=(
            DraftArtifactV1(
                DraftArtifactKind.ADR, "ADR-TEST", DraftArtifactState.DRAFT, "decision", ()
            ),
            DraftArtifactV1(
                DraftArtifactKind.SPEC, "SPEC-TEST", DraftArtifactState.DRAFT, "contract", ()
            ),
            DraftArtifactV1(
                DraftArtifactKind.BEAD, "GAP-TEST", DraftArtifactState.DRAFT, "work", ()
            ),
        ),
        verification=("Run the focused tests",),
        non_goals=("No promotion",),
        requested_authority=RequestedAuthority.PLANNING_ONLY,
    )


def make_package(key: str = "a" * 64) -> ProposalDecisionPackageV1:
    evidence = ProposalEvidenceV1.from_snapshots((make_candidate(key),))
    proposal = ImprovementProposalV1.create(
        evidence, make_draft(), datetime(2026, 1, 2, tzinfo=UTC)
    )
    return ProposalDecisionPackageV1.create(proposal)


def test_evidence_and_package_have_closed_canonical_fieldsets() -> None:
    evidence = ProposalEvidenceV1.from_snapshots((make_candidate(),))
    assert set(json.loads(evidence.to_bytes())) == {"schema_version", "candidates", "merge_review"}
    assert ProposalEvidenceV1.from_bytes(evidence.to_bytes()) == evidence
    package = make_package()
    assert ProposalDecisionPackageV1.from_bytes(package.to_bytes()).to_bytes() == package.to_bytes()
    assert package.decision.status is DecisionStatus.UNRESOLVED
    assert package.decision.created_at == package.proposal.created_at


def test_domain_hashes_are_recomputed_and_record_base64_is_standard() -> None:
    evidence = ProposalEvidenceV1.from_snapshots((make_candidate(),))
    expected_evidence = sha256(
        b"study-agent-devkit-gap05c-evidence-v1\0" + evidence.to_bytes()
    ).hexdigest()
    assert evidence.evidence_fingerprint == expected_evidence
    contribution = evidence.candidates[0].contributions[0]
    assert base64.b64encode(contribution.record_bytes).decode("ascii") == contribution.record_b64
    with pytest.raises((ProposalContractError, ValueError)):
        ProposalContributionV1("!", contribution.reproduction)


def test_merge_receipt_is_exact_and_fingerprint_is_domain_separated() -> None:
    keys = ("a" * 64, "b" * 64)
    receipt = CohortMergeReceiptV1(keys, "review@1")
    expected = sha256(
        b"study-agent-devkit-gap05c-merge-review-v1\0"
        + canonical_json_bytes({"candidate_gap_keys": keys, "review_id": "review@1"})
    ).hexdigest()
    assert receipt.merge_review_fingerprint == expected
    assert CohortMergeReceiptV1.from_bytes(receipt.to_bytes()) == receipt
    with pytest.raises(ProposalContractError):
        CohortMergeReceiptV1((keys[1], keys[0]), "review@1")


def test_bool_schema_timestamp_and_control_values_are_rejected() -> None:
    evidence = ProposalEvidenceV1.from_snapshots((make_candidate(),))
    raw = json.loads(evidence.to_bytes())
    raw["schema_version"] = True
    with pytest.raises(CapabilityGapCorruptionError):
        ProposalEvidenceV1.from_bytes(canonical_json_bytes(raw))
    with pytest.raises(ProposalContractError):
        ProposalOptionV1("bad", "contains\x00control", ("x",))
    with pytest.raises(ProposalContractError):
        ProposalOptionV1("bad", "contains\ud800surrogate", ("x",))
    proposal = make_package().proposal
    raw_proposal = json.loads(proposal.to_bytes())
    raw_proposal["created_at"] = "2026-01-02T00:00:00Z"
    with pytest.raises(CapabilityGapCorruptionError):
        ImprovementProposalV1.from_bytes(canonical_json_bytes(raw_proposal))


def test_draft_bounds_recommendation_state_and_dependency_dag() -> None:
    draft = make_draft()
    assert ProposalDraftV1.from_bytes(draft.to_bytes()) == draft
    with pytest.raises(ProposalContractError):
        ProposalDraftV1(
            1,
            (ProposalOptionV1("one", "x", ("y",)),),
            "one",
            draft.artifacts,
            ("v",),
            ("n",),
            RequestedAuthority.PLANNING_ONLY,
        )
    with pytest.raises(ProposalContractError):
        ProposalDraftV1(
            1,
            draft.options,
            "missing",
            draft.artifacts,
            ("v",),
            ("n",),
            RequestedAuthority.PLANNING_ONLY,
        )
    with pytest.raises(ProposalContractError):
        DraftArtifactV1(
            DraftArtifactKind.ADR, "ADR-TEST", DraftArtifactState("draft"), "x", ("GAP-TEST",)
        )
    cycle = (
        draft.artifacts[0],
        draft.artifacts[1],
        DraftArtifactV1(DraftArtifactKind.BEAD, "GAP-A", DraftArtifactState.DRAFT, "x", ("GAP-B",)),
        DraftArtifactV1(DraftArtifactKind.BEAD, "GAP-B", DraftArtifactState.DRAFT, "x", ("GAP-A",)),
    )
    with pytest.raises(ProposalContractError):
        ProposalDraftV1(
            1, draft.options, "safe", cycle, ("v",), ("n",), RequestedAuthority.PLANNING_ONLY
        )


def test_recomputed_ids_reject_tampered_cross_links() -> None:
    package = make_package()
    raw = json.loads(package.to_bytes())
    raw["decision"]["proposal_id"] = "f" * 64
    with pytest.raises(CapabilityGapCorruptionError):
        ProposalDecisionPackageV1.from_bytes(canonical_json_bytes(raw))
    raw_proposal = json.loads(package.proposal.to_bytes())
    raw_proposal["proposal_id"] = "f" * 64
    with pytest.raises(CapabilityGapCorruptionError):
        ImprovementProposalV1.from_bytes(canonical_json_bytes(raw_proposal))
