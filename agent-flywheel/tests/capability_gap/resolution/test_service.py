from __future__ import annotations

import sqlite3
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path

import pytest
from proposals.test_contracts import make_candidate

from study_agent_devkit.capability_gap import (
    DecisionViewV1,
    GapResolutionV1,
    GrillReceiptV1,
    GrillSubjectKind,
    ResolutionCommandV1,
    ResolutionOutcome,
    SQLiteResolutionService,
)
from study_agent_devkit.capability_gap.contracts import (
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
)
from study_agent_devkit.capability_gap.proposal_contracts import (
    DraftArtifactKind,
    DraftArtifactState,
    DraftArtifactV1,
    ImprovementProposalV1,
    ProposalDecisionPackageV1,
    ProposalDraftV1,
    ProposalEvidenceV1,
    ProposalOptionV1,
    RequestedAuthority,
)

SPEC_BODY = """# Feature Spec: Test

## Grilling Evidence
- reviewed

## Goal
A goal.

## Problem
A problem.

## In Scope
- Scope.

## Out of Scope
- Other.

## Acceptance Criteria
- [ ] Works.

## Verification
- pytest -q
"""

TASK_BODY = """# Task Bead: GAP-TEST Test task

Status: Approved
Depends On: none

## Outcome
Implement test.

## Slice Strategy
tracer-bullet
Fresh Context Fit: yes

## Spec Coverage
- Covers test.

## Grilling Evidence
- Reviewed.

## Worker Profile
none needed

## Context
Bounded context.

## What To Do
- Implement test.

## Likely Files / Packages
- src/test.py

## Acceptance Criteria
- [ ] Test passes.

## Verification
- pytest -q

## Out Of Scope
- Product behavior.
"""


class Source:
    def __init__(
        self,
        package: ProposalDecisionPackageV1,
        *others: ProposalDecisionPackageV1,
    ) -> None:
        self.packages = {item.decision.decision_id: item for item in (package, *others)}
        self.by_proposal = {item.proposal.proposal_id: item for item in (package, *others)}
        self.calls: list[str] = []

    def get_by_decision_id(self, decision_id: str) -> ProposalDecisionPackageV1 | None:
        self.calls.append("source-decision")
        return self.packages.get(decision_id)

    def get_by_proposal_id(self, proposal_id: str) -> ProposalDecisionPackageV1 | None:
        self.calls.append("source-proposal")
        return self.by_proposal.get(proposal_id)


class Authority:
    def __init__(self, outcome: ResolutionOutcome) -> None:
        self.outcome = outcome
        self.calls = 0

    def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
        self.calls += 1
        view = view
        return ResolutionCommandV1(
            1,
            view.proposal_id,
            view.decision_id,
            self.outcome,
            None,
            None,
            None,
            (),
        )


class Clock:
    def __init__(self) -> None:
        self.calls = 0

    def now(self) -> datetime:
        self.calls += 1
        return datetime(2026, 1, 3, tzinfo=UTC)


def package(key: str = "a" * 64) -> ProposalDecisionPackageV1:
    evidence = ProposalEvidenceV1.from_snapshots((make_candidate(key),))
    draft = ProposalDraftV1(
        1,
        (
            ProposalOptionV1("safe", "A bounded choice", ("review",)),
            ProposalOptionV1("small", "A small choice", ("work",)),
        ),
        "safe",
        (
            DraftArtifactV1(
                DraftArtifactKind.ADR,
                "ADR-TEST",
                DraftArtifactState.DRAFT,
                "# ADR-TEST\n\nStatus: Accepted\n",
                (),
            ),
            DraftArtifactV1(
                DraftArtifactKind.SPEC,
                "SPEC-TEST",
                DraftArtifactState.DRAFT,
                SPEC_BODY,
                (),
            ),
            DraftArtifactV1(
                DraftArtifactKind.BEAD,
                "GAP-TEST",
                DraftArtifactState.DRAFT,
                TASK_BODY,
                (),
            ),
        ),
        ("pytest -q",),
        ("No dispatch",),
        RequestedAuthority.PLANNING_ONLY,
    )
    return ProposalDecisionPackageV1.create(
        ImprovementProposalV1.create(evidence, draft, datetime(2026, 1, 2, tzinfo=UTC))
    )


def test_rejected_resolution_is_terminal_and_exact_retry_skips_callbacks(tmp_path: Path) -> None:
    pkg = package()
    source = Source(pkg)
    authority = Authority(ResolutionOutcome.REJECTED)
    clock = Clock()
    with SQLiteResolutionService(
        tmp_path / "resolution.sqlite3", source, authority, clock
    ) as service:
        result = service.resolve(pkg.decision.decision_id)
        assert isinstance(result, GapResolutionV1)
        assert result.outcome is ResolutionOutcome.REJECTED
        assert authority.calls == 1 and clock.calls == 1
        source.calls.clear()
        again = service.resolve(pkg.decision.decision_id)
        assert again.to_bytes() == result.to_bytes()
        assert source.calls == [] and authority.calls == 1 and clock.calls == 1


def test_accepted_promotion_requires_exact_grills_and_is_goal_optional(tmp_path: Path) -> None:
    pkg = package()
    source = Source(pkg)

    class AcceptedAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.ACCEPTED,
                "safe",
                None,
                None,
                (
                    GrillReceiptV1(GrillSubjectKind.BEAD, "GAP-TEST", "rb", "2" * 64),
                    GrillReceiptV1(GrillSubjectKind.PROPOSAL, view.proposal_id, "rp", "1" * 64),
                ),
            )

    with SQLiteResolutionService(
        tmp_path / "accepted.sqlite3", source, AcceptedAuthority(), Clock()
    ) as service:
        result = service.resolve(pkg.decision.decision_id)
        assert result.outcome is ResolutionOutcome.ACCEPTED
        promotion = service.get_promotion_by_decision_id(pkg.decision.decision_id)
        assert promotion is not None
        assert promotion.implementation_goal is None
        assert promotion.materialization_plan.run_id == f"gap06-{result.resolution_id[:24]}"


@pytest.mark.parametrize(
    ("outcome", "reference"),
    ((ResolutionOutcome.DEFERRED, "later"), (ResolutionOutcome.DUPLICATE, "target")),
)
def test_nonaccepted_outcomes_have_no_promotion(
    tmp_path: Path, outcome: ResolutionOutcome, reference: str
) -> None:
    current = package()
    target = package("b" * 64)
    source = Source(current, target)

    class NonAcceptedAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                outcome,
                None,
                reference if outcome is ResolutionOutcome.DEFERRED else None,
                target.proposal.proposal_id if outcome is ResolutionOutcome.DUPLICATE else None,
                (),
            )

    with SQLiteResolutionService(
        tmp_path / "nonaccepted.sqlite3", source, NonAcceptedAuthority(), Clock()
    ) as service:
        result = service.resolve(current.decision.decision_id)
        assert result.outcome is outcome
        assert service.get_promotion_by_decision_id(current.decision.decision_id) is None


def test_authority_none_or_raise_leaves_database_empty(tmp_path: Path) -> None:
    pkg = package()

    class NoneAuthority:
        def resolve(self, view: DecisionViewV1) -> None:
            return None

    class RaisingAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            raise RuntimeError("authority failed")

    for authority, expected in (
        (NoneAuthority(), CapabilityGapCollisionError),
        (RaisingAuthority(), RuntimeError),
    ):
        database = tmp_path / f"{authority.__class__.__name__}.sqlite3"
        with SQLiteResolutionService(database, Source(pkg), authority, Clock()) as service:
            with pytest.raises(expected):
                service.resolve(pkg.decision.decision_id)
            assert service.get_by_promotion_id("0" * 64) is None


def test_selected_option_and_grill_mismatch_do_not_commit(tmp_path: Path) -> None:
    pkg = package()

    class BadAuthority:
        def __init__(self, selected: str, receipts: tuple[GrillReceiptV1, ...]) -> None:
            self.selected = selected
            self.receipts = receipts

        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.ACCEPTED,
                self.selected,
                None,
                None,
                self.receipts,
            )

    with SQLiteResolutionService(
        tmp_path / "bad-option.sqlite3",
        Source(pkg),
        BadAuthority("missing", ()),
        Clock(),
    ) as service:
        with pytest.raises((CapabilityGapValidationError, ValueError)):
            service.resolve(pkg.decision.decision_id)
        assert service.get_promotion_by_decision_id(pkg.decision.decision_id) is None


def test_base_exception_rolls_back_and_can_retry(tmp_path: Path) -> None:
    pkg = package()
    database = tmp_path / "rollback.sqlite3"
    with SQLiteResolutionService(
        database, Source(pkg), Authority(ResolutionOutcome.REJECTED), Clock()
    ) as service:
        original = service._store.insert

        def fail(*args: object, **kwargs: object) -> None:
            raise KeyboardInterrupt

        service._store.insert = fail  # type: ignore[method-assign]
        with pytest.raises(KeyboardInterrupt):
            service.resolve(pkg.decision.decision_id)
        service._store.insert = original  # type: ignore[method-assign]
        result = service.resolve(pkg.decision.decision_id)
        assert result.outcome is ResolutionOutcome.REJECTED


def test_projection_corruption_fails_closed(tmp_path: Path) -> None:
    pkg = package()
    database = tmp_path / "corruption.sqlite3"
    with SQLiteResolutionService(
        database, Source(pkg), Authority(ResolutionOutcome.REJECTED), Clock()
    ) as service:
        service.resolve(pkg.decision.decision_id)
    connection = sqlite3.connect(database)
    connection.execute("UPDATE resolution_packages SET outcome='accepted'")
    connection.commit()
    connection.close()
    with (
        SQLiteResolutionService(
            database, Source(pkg), Authority(ResolutionOutcome.REJECTED), Clock()
        ) as service,
        pytest.raises(CapabilityGapCorruptionError),
    ):
        service.resolve(pkg.decision.decision_id)


def test_concurrent_resolution_returns_one_winner(tmp_path: Path) -> None:
    pkg = package()
    database = tmp_path / "race.sqlite3"

    def resolve(_: int) -> bytes:
        with SQLiteResolutionService(
            database, Source(pkg), Authority(ResolutionOutcome.REJECTED), Clock()
        ) as service:
            return service.resolve(pkg.decision.decision_id).to_bytes()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = tuple(pool.map(resolve, (1, 2)))
    assert results[0] == results[1]


def test_concurrent_service_initialization_serializes_schema_creation(tmp_path: Path) -> None:
    pkg = package()
    database = tmp_path / "concurrent-init.sqlite3"

    def open_and_resolve(_: int) -> bytes:
        with SQLiteResolutionService(
            database, Source(pkg), Authority(ResolutionOutcome.REJECTED), Clock()
        ) as service:
            return service.resolve(pkg.decision.decision_id).to_bytes()

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = tuple(pool.map(open_and_resolve, range(4)))
    assert results and all(item == results[0] for item in results)


def test_duplicate_missing_target_is_rejected(tmp_path: Path) -> None:
    current = package()

    class MissingTargetAuthority:
        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.DUPLICATE,
                None,
                None,
                "f" * 64,
                (),
            )

    with (
        SQLiteResolutionService(
            tmp_path / "missing-target.sqlite3",
            Source(current),
            MissingTargetAuthority(),
            Clock(),
        ) as service,
        pytest.raises(CapabilityGapValidationError),
    ):
        service.resolve(current.decision.decision_id)


def test_duplicate_target_already_duplicate_and_inbound_root_are_rejected(
    tmp_path: Path,
) -> None:
    first, second, third = package("a" * 64), package("b" * 64), package("c" * 64)
    source = Source(first, second, third)

    class GraphAuthority:
        def __init__(self, target_by_proposal: dict[str, str]) -> None:
            self.target_by_proposal = target_by_proposal

        def resolve(self, view: DecisionViewV1) -> ResolutionCommandV1:
            return ResolutionCommandV1(
                1,
                view.proposal_id,
                view.decision_id,
                ResolutionOutcome.DUPLICATE,
                None,
                None,
                self.target_by_proposal[view.proposal_id],
                (),
            )

    # First create an inbound duplicate link A -> B. B must remain a root.
    authority = GraphAuthority({first.proposal.proposal_id: second.proposal.proposal_id})
    database = tmp_path / "duplicate-graph.sqlite3"
    with SQLiteResolutionService(database, source, authority, Clock()) as service:
        service.resolve(first.decision.decision_id)


    authority.target_by_proposal = {second.proposal.proposal_id: third.proposal.proposal_id}
    with (
        pytest.raises(CapabilityGapCollisionError),
        SQLiteResolutionService(database, source, authority, Clock()) as service,
    ):
        service.resolve(second.decision.decision_id)

    # A target that already resolved as duplicate cannot be targeted by C.
    fourth = package("d" * 64)
    source2 = Source(first, second, third, fourth)
    database2 = tmp_path / "duplicate-target.sqlite3"
    authority2 = GraphAuthority({second.proposal.proposal_id: third.proposal.proposal_id})
    with SQLiteResolutionService(database2, source2, authority2, Clock()) as service:
        service.resolve(second.decision.decision_id)
    authority2.target_by_proposal = {first.proposal.proposal_id: second.proposal.proposal_id}
    with (
        pytest.raises(CapabilityGapCollisionError),
        SQLiteResolutionService(database2, source2, authority2, Clock()) as service,
    ):
        service.resolve(first.decision.decision_id)
