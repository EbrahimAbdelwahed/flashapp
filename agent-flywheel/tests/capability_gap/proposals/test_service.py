from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path
from typing import cast

import pytest

from study_agent_devkit.capability_gap import (
    CapabilityGapCollisionError,
    CapabilityGapValidationError,
    ProposalService,
)
from study_agent_devkit.capability_gap.proposal_contracts import (
    CohortMergeReceiptV1,
    ProposalDecisionPackageV1,
    ProposalDraftBuilder,
    ProposalDraftV1,
    ProposalEvidenceV1,
)

from .test_contracts import make_candidate, make_draft


class CountingBuilder:
    def __init__(self, *, fail: bool = False) -> None:
        self.calls = 0
        self.fail = fail

    def build(self, evidence: ProposalEvidenceV1) -> ProposalDraftV1:
        self.calls += 1
        if self.fail:
            raise RuntimeError("builder failed")
        assert evidence.candidate_gap_keys
        return make_draft()


class CountingAuthority:
    def __init__(self, result: CohortMergeReceiptV1 | None = None) -> None:
        self.calls = 0
        self.result = result

    def authorize(self, keys: tuple[str, ...]) -> CohortMergeReceiptV1 | None:
        self.calls += 1
        return self.result


class CountingClock:
    def __init__(self) -> None:
        self.calls = 0

    def now(self) -> datetime:
        self.calls += 1
        return datetime(2026, 1, 3, tzinfo=UTC)


def test_single_candidate_needs_no_authority_and_is_exactly_retryable(tmp_path: Path) -> None:
    authority = CountingAuthority()
    builder = CountingBuilder()
    clock = CountingClock()
    with ProposalService(
        tmp_path / "proposal.sqlite3", authority=authority, clock=clock
    ) as service:
        first = service.create((make_candidate(),), builder)
        second = service.create((make_candidate(count=99),), builder)
        assert isinstance(first, ProposalDecisionPackageV1)
        assert second.to_bytes() == first.to_bytes()
        assert authority.calls == 0
        assert builder.calls == 1
        assert clock.calls == 1


def test_multi_candidate_requires_exact_merge_authority(tmp_path: Path) -> None:
    candidates = (make_candidate("a" * 64), make_candidate("b" * 64, seed="b"))
    with pytest.raises(CapabilityGapCollisionError, match="required"), ProposalService(
        tmp_path / "missing.sqlite3", clock=CountingClock()
    ) as service:
        service.create(candidates, CountingBuilder())
    keys = tuple(sorted(item.gap_key for item in candidates))
    rejecting = CountingAuthority(None)
    with pytest.raises(CapabilityGapCollisionError, match="rejected"), ProposalService(
        tmp_path / "reject.sqlite3", authority=rejecting, clock=CountingClock()
    ) as service:
        service.create(candidates, CountingBuilder())
    mismatched = CountingAuthority(CohortMergeReceiptV1((keys[0],), "review@1"))
    with pytest.raises(CapabilityGapCollisionError, match="mismatch"), ProposalService(
        tmp_path / "mismatch.sqlite3", authority=mismatched, clock=CountingClock()
    ) as service:
        service.create(candidates, CountingBuilder())


def test_authorized_multi_and_overlap_are_deterministic(tmp_path: Path) -> None:
    candidates = (make_candidate("a" * 64), make_candidate("b" * 64, seed="b"))
    keys = tuple(sorted(item.gap_key for item in candidates))
    authority = CountingAuthority(CohortMergeReceiptV1(keys, "review@1"))
    with ProposalService(
        tmp_path / "authorized.sqlite3", authority=authority, clock=CountingClock()
    ) as service:
        builder = CountingBuilder()
        package = service.create(candidates, builder)
        assert package.proposal.evidence.merge_review is not None
        assert authority.calls == 1
        with pytest.raises(CapabilityGapCollisionError, match="cohort_collision"):
            service.create((make_candidate("a" * 64), make_candidate("c" * 64, seed="c")), builder)
        assert authority.calls == 1


def test_builder_failure_and_invalid_output_leave_store_empty(tmp_path: Path) -> None:
    database = tmp_path / "failure.sqlite3"
    with ProposalService(database) as service:
        failing = CountingBuilder(fail=True)
        with pytest.raises(RuntimeError):
            service.create((make_candidate(),), failing)
        assert service.get_by_gap_key("a" * 64) is None

        class InvalidBuilder:
            def build(self, evidence: ProposalEvidenceV1) -> object:
                return object()

        with pytest.raises(CapabilityGapValidationError):
            service.create(
                (make_candidate(),), cast(ProposalDraftBuilder, InvalidBuilder())
            )
        assert service.get_by_gap_key("a" * 64) is None


def test_identical_concurrent_creations_return_one_canonical_winner(tmp_path: Path) -> None:
    database = tmp_path / "concurrent.sqlite3"
    candidates = (make_candidate(),)
    with ProposalService(database):
        pass

    def run(_: int) -> bytes:
        with ProposalService(database, clock=lambda: datetime(2026, 1, 4, tzinfo=UTC)) as service:
            return service.create(candidates, CountingBuilder()).to_bytes()

    with ThreadPoolExecutor(max_workers=2) as pool:
        values = tuple(pool.map(run, (1, 2)))
    assert values[0] == values[1]
    with ProposalService(database) as service:
        assert service.get_by_gap_key("a" * 64) is not None
