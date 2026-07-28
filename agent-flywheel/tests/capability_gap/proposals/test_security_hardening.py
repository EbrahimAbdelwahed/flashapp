from __future__ import annotations

from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path

import pytest

import study_agent_devkit.capability_gap as capability_gap
from study_agent_devkit.capability_gap import (
    ActiveWorkKind,
    ActiveWorkSnapshot,
    CandidateSnapshot,
    CapabilityGapCollisionError,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
    ProposalService,
)
from study_agent_devkit.capability_gap.proposal_contracts import (
    MAX_DRAFT_BYTES,
    MAX_EVIDENCE_BYTES,
    MAX_PACKAGE_BYTES,
    CohortMergeReceiptV1,
    ProposalDecisionPackageV1,
    ProposalDraftV1,
    ProposalEvidenceV1,
)
from study_agent_devkit.capability_gap.proposal_store import _SQLiteProposalStore

from .test_contracts import make_candidate, make_package


class _CountingAuthority:
    def __init__(self) -> None:
        self.calls = 0

    def authorize(self, _keys: tuple[str, ...]) -> CohortMergeReceiptV1 | None:
        self.calls += 1
        return None


class _CountingBuilder:
    def __init__(self) -> None:
        self.calls = 0

    def build(self, _evidence: ProposalEvidenceV1) -> object:
        self.calls += 1
        return object()


class _CountingClock:
    def __init__(self) -> None:
        self.calls = 0

    def now(self) -> datetime:
        self.calls += 1
        return datetime(2026, 1, 1, tzinfo=UTC)


def test_store_and_mutator_are_not_public_and_service_is_the_write_boundary(
    tmp_path: Path,
) -> None:
    assert "SQLiteProposalStore" not in capability_gap.__all__
    assert not hasattr(capability_gap, "SQLiteProposalStore")
    assert "create_or_get" not in capability_gap.__all__

    database = tmp_path / "boundary.sqlite3"
    candidates = (make_candidate(), make_candidate("b" * 64, seed="b"))
    with _SQLiteProposalStore(database) as private_store, pytest.raises(
        CapabilityGapValidationError, match="database"
    ):
        ProposalService(private_store)
    with ProposalService(database) as service:
        with pytest.raises(CapabilityGapCollisionError, match="required"):
            service.create(candidates, _CountingBuilder())  # type: ignore[arg-type]
        assert service.get_by_gap_key("a" * 64) is None
        assert service.get_by_gap_key("b" * 64) is None


class _CandidateSubclass(CandidateSnapshot):
    pass


@pytest.mark.parametrize("forged", (object(),))
def test_preflight_rejects_subclass_and_forged_candidates_before_callbacks(
    tmp_path: Path, forged: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    authority = _CountingAuthority()
    builder = _CountingBuilder()
    clock = _CountingClock()
    lookup_calls: list[object] = []

    def blocked_lookup(*args: object) -> None:
        lookup_calls.append(args)

    monkeypatch.setattr(
        _SQLiteProposalStore,
        "lookup",
        blocked_lookup,
    )
    candidates = (forged,)
    with pytest.raises(
        CapabilityGapValidationError, match="candidate_snapshot"
    ), ProposalService(tmp_path / "forged.sqlite3", authority=authority, clock=clock) as service:
        service.create(candidates, builder)  # type: ignore[arg-type]
    assert authority.calls == 0
    assert builder.calls == 0
    assert clock.calls == 0
    assert lookup_calls == []


def test_preflight_rejects_exact_candidate_subclass_before_decoding(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    base = make_candidate()
    subclass = _CandidateSubclass(
        base.gap_key,
        base.dimensions,
        base.contributions,
        base.occurrence_count,
        base.first_seen,
        base.last_seen,
        base.active_work,
    )
    authority = _CountingAuthority()
    builder = _CountingBuilder()
    clock = _CountingClock()
    lookup_calls: list[object] = []

    def blocked_lookup(*args: object) -> None:
        lookup_calls.append(args)

    monkeypatch.setattr(
        _SQLiteProposalStore,
        "lookup",
        blocked_lookup,
    )
    with pytest.raises(
        CapabilityGapValidationError, match="candidate_snapshot"
    ), ProposalService(tmp_path / "subclass.sqlite3", authority=authority, clock=clock) as service:
        service.create((subclass,), builder)  # type: ignore[arg-type]
    assert authority.calls == 0
    assert builder.calls == 0
    assert clock.calls == 0
    assert lookup_calls == []


@pytest.mark.parametrize("field", ("contributions", "active_work"))
def test_preflight_rejects_oversized_candidate_container_before_callbacks(
    tmp_path: Path, field: str
) -> None:
    from dataclasses import replace

    base = make_candidate()
    if field == "contributions":
        candidate = replace(
            base,
            contributions=base.contributions * 257,
            occurrence_count=base.occurrence_count * 257,
        )
    else:
        candidate = replace(
            base,
            active_work=tuple(
                ActiveWorkSnapshot(base.gap_key, ActiveWorkKind.BEAD, f"GAP-{index:03d}")
                for index in range(257)
            ),
        )
    authority = _CountingAuthority()
    builder = _CountingBuilder()
    clock = _CountingClock()
    with pytest.raises(
        CapabilityGapValidationError, match="evidence_bounds"
    ), ProposalService(tmp_path / f"{field}.sqlite3", authority=authority, clock=clock) as service:
        service.create((candidate,), builder)  # type: ignore[arg-type]
    assert authority.calls == 0
    assert builder.calls == 0
    assert clock.calls == 0


@pytest.mark.parametrize(
    ("codec", "bound"),
    (
        (ProposalEvidenceV1.from_bytes, MAX_EVIDENCE_BYTES),
        (ProposalDraftV1.from_bytes, MAX_DRAFT_BYTES),
        (ProposalDecisionPackageV1.from_bytes, MAX_PACKAGE_BYTES),
    ),
)
def test_codecs_reject_oversized_payload_before_json_decode(codec: object, bound: int) -> None:
    payload = b"{" + b"x" * bound + b"}"
    with pytest.raises(CapabilityGapCorruptionError):
        codec(payload)  # type: ignore[operator]


def test_lookup_rejects_noncanonical_keys_and_duplicates_before_read(tmp_path: Path) -> None:
    with _SQLiteProposalStore(tmp_path / "lookup.sqlite3") as store:
        with pytest.raises(CapabilityGapValidationError):
            store.lookup(("A" * 64,))
        with pytest.raises(CapabilityGapValidationError):
            store.lookup(("a" * 64, "a" * 64))


def test_lookup_infinite_iterable_is_bounded_to_seventeen_items(tmp_path: Path) -> None:
    consumed = 0

    def keys() -> Iterable[str]:
        nonlocal consumed
        while True:
            consumed += 1
            yield f"{consumed:064x}"

    with pytest.raises(
        CapabilityGapValidationError, match="gap_keys"
    ), _SQLiteProposalStore(tmp_path / "infinite-lookup.sqlite3") as store:
        store.lookup(keys())
    assert consumed == 17


def test_package_codec_rejects_non_exact_bytes() -> None:
    package = make_package()
    with pytest.raises(CapabilityGapCorruptionError):
        ProposalDecisionPackageV1.from_bytes(bytearray(package.to_bytes()))  # type: ignore[arg-type]
