from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from study_agent.adapters.sqlite.capability_gap_store import (
    SQLiteCapabilityGapStore as PublicCapabilityGapStore,
)
from study_agent.feedback import (
    CapabilityGapObservation,
    CapabilityGapService,
    CapabilityGapWriteContext,
    GapCategory,
    GapOutboxExportService,
    GapOutboxRecord,
    ImpactKind,
    RequestedOperationKind,
    SafeTargetKind,
    TrustedLimitationCode,
    TrustedLimitationReceipt,
)
from study_agent.feedback.outbox import GapOutboxBundle

from study_agent_devkit.capability_gap import (
    CandidateSnapshot,
    DecisionViewV1,
    DeliveryImportContext,
    DraftArtifactKind,
    DraftArtifactState,
    DraftArtifactV1,
    GrillReceiptV1,
    GrillSubjectKind,
    ProposalDecisionPackageV1,
    ProposalDraftV1,
    ProposalOptionV1,
    ProposalService,
    ReproductionRegistry,
    ReproductionResult,
    ReproductionStatus,
    RequestedAuthority,
    ResolutionCommandV1,
    ResolutionOutcome,
    SQLiteCapabilityGapStore,
)

NOW = datetime(2026, 7, 25, 12, 0, tzinfo=UTC)

SPEC_BODY = """# Feature Spec: Capability gap closure

## Grilling Evidence
- Reviewed redacted evidence.

## Goal
Prove a bounded local chain.

## Problem
The local chain needs closure evidence.

## In Scope
- Deterministic local materialization.

## Out of Scope
- Dispatch and publication.

## Acceptance Criteria
- [ ] The run is self-contained.

## Verification
- pytest -q tests/capability_gap/e2e
"""

TASK_BODY = """# Task Bead: GAP-E2E closure

Status: Approved
Depends On: none

## Outcome
Prove local closure.

## Slice Strategy
tracer-bullet
Fresh Context Fit: yes

## Spec Coverage
- Covers the local chain.

## Grilling Evidence
- Reviewed.

## Worker Profile
none needed

## Context
Bounded offline context.

## What To Do
- Verify the chain.

## Likely Files / Packages
- tests/capability_gap/e2e

## Acceptance Criteria
- [ ] No dispatch occurs.

## Verification
- pytest -q tests/capability_gap/e2e

## Out Of Scope
- Product behavior.
"""


class Publisher:
    def __init__(self) -> None:
        self.payloads: list[bytes] = []

    def publish(self, payload: bytes) -> None:
        self.payloads.append(payload)


class Source:
    def __init__(self, *packages: ProposalDecisionPackageV1) -> None:
        self._by_decision = {item.decision.decision_id: item for item in packages}
        self._by_proposal = {item.proposal.proposal_id: item for item in packages}
        self.calls: list[str] = []

    def get_by_decision_id(self, decision_id: str) -> ProposalDecisionPackageV1 | None:
        self.calls.append("decision")
        return self._by_decision.get(decision_id)

    def get_by_proposal_id(self, proposal_id: str) -> ProposalDecisionPackageV1 | None:
        self.calls.append("proposal")
        return self._by_proposal.get(proposal_id)


class Clock:
    def __init__(self) -> None:
        self.calls = 0

    def now(self) -> datetime:
        self.calls += 1
        return NOW


class Authority:
    def __init__(self, outcome: ResolutionOutcome) -> None:
        self.outcome = outcome
        self.calls = 0

    def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
        self.calls += 1
        if self.outcome is ResolutionOutcome.ACCEPTED:
            receipts = tuple(
                [
                    GrillReceiptV1(
                        GrillSubjectKind.BEAD, bead_id, f"grill@{bead_id}", "2" * 64
                    )
                    for bead_id in view.bead_ids
                ]
                + [
                    GrillReceiptV1(
                        GrillSubjectKind.PROPOSAL,
                        view.proposal_id,
                        "grill@proposal",
                        "1" * 64,
                    )
                ]
            )
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                self.outcome,
                view.option_ids[0],
                None,
                None,
                receipts,
            )
        return ResolutionCommandV1(
            1,
            view.proposal_id,
            view.decision_id,
            self.outcome,
            None,
            "later" if self.outcome is ResolutionOutcome.DEFERRED else None,
            None,
            (),
        )


def make_draft(authority: RequestedAuthority) -> ProposalDraftV1:
    return ProposalDraftV1(
        1,
        (
            ProposalOptionV1("safe", "Keep the current boundary", ("review",)),
            ProposalOptionV1("small", "Add a narrow implementation", ("cost",)),
        ),
        "safe",
        (
            DraftArtifactV1(
                DraftArtifactKind.ADR,
                "ADR-E2E",
                DraftArtifactState.DRAFT,
                "# ADR-E2E\n\nStatus: Accepted\n",
                (),
            ),
            DraftArtifactV1(
                DraftArtifactKind.SPEC,
                "SPEC-E2E",
                DraftArtifactState.DRAFT,
                SPEC_BODY,
                (),
            ),
            DraftArtifactV1(
                DraftArtifactKind.BEAD,
                "GAP-E2E",
                DraftArtifactState.DRAFT,
                TASK_BODY,
                (),
            ),
        ),
        ("Run the focused tests",),
        ("No dispatch or publication",),
        authority,
    )


def public_export(
    tmp_path: Path,
    *,
    operation: RequestedOperationKind = RequestedOperationKind.INGEST_SOURCE,
    database_name: str = "public.sqlite3",
) -> tuple[bytes, str, GapOutboxRecord]:
    public_store = PublicCapabilityGapStore(tmp_path / database_name)
    service = CapabilityGapService(public_store)
    observation = CapabilityGapObservation(
        GapCategory.INPUT_FORMAT,
        operation,
        SafeTargetKind.PDF,
        ImpactKind.BLOCKED,
    )
    receipt = TrustedLimitationReceipt(
        "contract@e2e", 1, TrustedLimitationCode.UNSUPPORTED_FORMAT, "a" * 64
    )
    service.record(
        observation,
        CapabilityGapWriteContext("harness@1", "corr@e2e", "a" * 64, NOW, receipt),
    )
    publisher = Publisher()
    exported = GapOutboxExportService(public_store, publisher, harness_version="harness@1").export()
    assert len(publisher.payloads) == 1
    bundle = GapOutboxBundle.from_bytes(exported.payload)
    assert len(bundle.records) == 1
    return exported.payload, exported.bundle_fingerprint, bundle.records[0]


def import_to_proposal(
    tmp_path: Path,
    payload: bytes,
    fingerprint: str,
    record: GapOutboxRecord,
    authority: RequestedAuthority = RequestedAuthority.PLANNING_ONLY,
    *,
    database_name: str = "private.sqlite3",
    proposal_database_name: str = "proposal.sqlite3",
    callback_counter: list[int] | None = None,
) -> tuple[SQLiteCapabilityGapStore, ProposalDecisionPackageV1]:
    registry = ReproductionRegistry()

    def reproduce(_record: GapOutboxRecord) -> ReproductionResult:
        if callback_counter is not None:
            callback_counter[0] += 1
        return ReproductionResult(ReproductionStatus.REPRODUCED, "f" * 64)

    registry.register(
        "fixture@e2e",
        record.dimensions,
        reproduce,
    )
    imported = SQLiteCapabilityGapStore(tmp_path / database_name)
    imported.import_bundle(
        payload,
        DeliveryImportContext.for_local_bundle(fingerprint),
        reproduction=registry,
    )
    candidate = imported.get_candidate(record.gap_key.value)
    assert isinstance(candidate, CandidateSnapshot)
    proposals = ProposalService(tmp_path / proposal_database_name, clock=Clock())
    package = proposals.create((candidate,), lambda _e: make_draft(authority))
    proposals.close()
    return imported, package
