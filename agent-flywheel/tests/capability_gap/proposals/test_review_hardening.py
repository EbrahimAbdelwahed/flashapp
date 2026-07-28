from __future__ import annotations

import json
import threading
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path

import pytest
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    CandidateSnapshot,
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
    ProposalService,
)
from study_agent_devkit.capability_gap.proposal_contracts import (
    CohortMergeReceiptV1,
    MaintainerDecisionRequestV1,
    ProposalDecisionPackageV1,
    ProposalDraftV1,
    ProposalEvidenceV1,
    RequestedAuthority,
)
from study_agent_devkit.capability_gap.proposal_store import _SQLiteProposalStore

from .test_contracts import make_candidate, make_draft, make_package


class _Builder:
    def __init__(
        self,
        draft: ProposalDraftV1 | None = None,
        barrier: threading.Barrier | None = None,
    ):
        self.calls = 0
        self._draft = draft or make_draft()
        self._barrier = barrier

    def build(self, _evidence: ProposalEvidenceV1) -> ProposalDraftV1:
        self.calls += 1
        if self._barrier is not None:
            self._barrier.wait(timeout=10)
        return self._draft


class _Authority:
    def __init__(self, result: CohortMergeReceiptV1 | None = None) -> None:
        self.calls = 0
        self._result = result

    def authorize(self, _keys: tuple[str, ...]) -> CohortMergeReceiptV1 | None:
        self.calls += 1
        return self._result


class _Clock:
    def __init__(self, value: datetime) -> None:
        self.calls = 0
        self._value = value

    def now(self) -> datetime:
        self.calls += 1
        return self._value


def test_racing_different_builders_return_the_persisted_winner(tmp_path: Path) -> None:
    database = tmp_path / "different-winners.sqlite3"
    with ProposalService(database):
        pass
    barrier = threading.Barrier(2)
    first_draft = make_draft()
    second_draft = replace(
        first_draft,
        options=(
            replace(first_draft.options[0], summary="a different generated draft"),
            *first_draft.options[1:],
        ),
    )

    def create_one(args: tuple[ProposalDraftV1, datetime]) -> bytes:
        draft, created_at = args
        builder = _Builder(draft, barrier)
        with ProposalService(database, clock=_Clock(created_at)) as service:
            package = service.create((make_candidate(),), builder)
            assert builder.calls == 1
            return package.to_bytes()

    with ThreadPoolExecutor(max_workers=2) as pool:
        values = tuple(
            pool.map(
                create_one,
                (
                    (first_draft, datetime(2026, 1, 6, tzinfo=UTC)),
                    (second_draft, datetime(2026, 1, 7, tzinfo=UTC)),
                ),
            )
        )
    assert values[0] == values[1]
    with _SQLiteProposalStore(database) as store:
        assert store.connection.execute("SELECT COUNT(*) FROM proposal_packages").fetchone()[0] == 1
        assert store.connection.execute("SELECT COUNT(*) FROM proposal_members").fetchone()[0] == 1


def test_decision_authority_cannot_escalate_with_recomputed_ids() -> None:
    package = make_package()
    raw = json.loads(package.to_bytes())
    authority = RequestedAuthority.PLANNING_AND_IMPLEMENTATION_GOAL
    raw["decision"]["requested_authority"] = authority.value
    raw["decision"]["decision_id"] = MaintainerDecisionRequestV1.derive_id(
        package.proposal.proposal_id, authority, package.decision.created_at
    )
    with pytest.raises(CapabilityGapCorruptionError):
        ProposalDecisionPackageV1.from_bytes(canonical_json_bytes(raw))


def test_member_lookup_returns_multi_key_package_without_changing_exact_lookup(
    tmp_path: Path,
) -> None:
    candidates = (make_candidate(), make_candidate("b" * 64, seed="b"))
    keys = tuple(sorted(item.gap_key for item in candidates))
    authority = _Authority(CohortMergeReceiptV1(keys, "review@member-lookup"))
    with ProposalService(tmp_path / "member-lookup.sqlite3", authority=authority) as service:
        package = service.create(candidates, _Builder())
        assert service.get_by_gap_key(keys[0]) == package
        assert service.get_by_gap_key(keys[1]) == package
        assert service.get_by_gap_key("c" * 64) is None
        with pytest.raises(CapabilityGapValidationError, match="gap_keys"):
            service.get_by_gap_key("A" * 64)
        with pytest.raises(CapabilityGapCollisionError, match="cohort_collision"):
            service.lookup((keys[0],))


@pytest.mark.parametrize("stored_value", (1, 2**63 - 1, "not-bytes", b"x" * (2 * 1024 * 1024 + 1)))
def test_invalid_package_storage_type_or_size_is_closed_and_skips_callbacks(
    tmp_path: Path, stored_value: object
) -> None:
    database = tmp_path / "invalid-storage.sqlite3"
    package = make_package()
    with _SQLiteProposalStore(database) as store:
        store._create_or_get(package)
        store.connection.execute(
            "UPDATE proposal_packages SET package_bytes = ? WHERE proposal_id = ?",
            (stored_value, package.proposal.proposal_id),
        )
        authority = _Authority()
        builder = _Builder()
        clock = _Clock(datetime(2026, 1, 8, tzinfo=UTC))
        with pytest.raises(CapabilityGapCorruptionError), ProposalService(
            database, authority=authority, clock=clock
        ) as service:
            service.create((make_candidate(),), builder)
    assert authority.calls == 0
    assert builder.calls == 0
    assert clock.calls == 0


def test_candidate_iterable_is_consumed_only_to_the_bound_before_callbacks(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    consumed = 0

    def candidates() -> Iterable[CandidateSnapshot]:
        nonlocal consumed
        for index in range(100):
            consumed += 1
            yield make_candidate(f"{index:064x}", seed="a")

    authority = _Authority()
    builder = _Builder()
    clock = _Clock(datetime(2026, 1, 8, tzinfo=UTC))
    lookup_calls: list[object] = []
    original_lookup = _SQLiteProposalStore.lookup

    def counting_lookup(
        store: _SQLiteProposalStore, keys: Iterable[str]
    ) -> ProposalDecisionPackageV1 | None:
        lookup_calls.append(keys)
        return original_lookup(store, keys)

    monkeypatch.setattr(_SQLiteProposalStore, "lookup", counting_lookup)
    with ProposalService(tmp_path / "bounded.sqlite3", authority=authority, clock=clock) as service:
        with pytest.raises(CapabilityGapValidationError, match="candidates"):
            service.create(candidates(), builder)
        assert consumed == 17
        assert lookup_calls == []
        assert authority.calls == 0
        assert builder.calls == 0
        assert clock.calls == 0


def test_aggregate_contribution_bound_skips_callbacks(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    first = make_candidate("a" * 64)
    second = make_candidate("b" * 64, seed="b")
    first = replace(
        first,
        contributions=first.contributions * 129,
        occurrence_count=first.occurrence_count * 129,
    )
    second = replace(
        second,
        contributions=second.contributions * 129,
        occurrence_count=second.occurrence_count * 129,
    )
    authority = _Authority()
    builder = _Builder()
    clock = _Clock(datetime(2026, 1, 8, tzinfo=UTC))
    lookup_calls: list[object] = []
    original_lookup = _SQLiteProposalStore.lookup

    def counting_lookup(
        store: _SQLiteProposalStore, keys: Iterable[str]
    ) -> ProposalDecisionPackageV1 | None:
        lookup_calls.append(keys)
        return original_lookup(store, keys)

    monkeypatch.setattr(_SQLiteProposalStore, "lookup", counting_lookup)
    with ProposalService(
        tmp_path / "aggregate-bound.sqlite3", authority=authority, clock=clock
    ) as service:
        with pytest.raises(CapabilityGapValidationError, match="evidence_bounds"):
            service.create((first, second), builder)
        assert lookup_calls == []
        assert authority.calls == 0
        assert builder.calls == 0
        assert clock.calls == 0
