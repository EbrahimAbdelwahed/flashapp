"""Creation workflow for immutable proposal/decision packages."""

from __future__ import annotations

from collections.abc import Callable, Iterable
from datetime import UTC, datetime
from typing import Any, Protocol, cast

from study_agent.state import canonical_json_bytes

from .contracts import (
    CandidateSnapshot,
    CapabilityGapCollisionError,
    CapabilityGapValidationError,
)
from .proposal_contracts import (
    MAX_ACTIVE_WORK_PER_CANDIDATE,
    MAX_CANDIDATE_BYTES,
    MAX_CANDIDATES,
    MAX_CONTRIBUTIONS_PER_CANDIDATE,
    MAX_EVIDENCE_BYTES,
    MAX_TOTAL_ACTIVE_WORK,
    MAX_TOTAL_CONTRIBUTIONS,
    CohortMergeAuthority,
    CohortMergeReceiptV1,
    ImprovementProposalV1,
    ProposalCandidateV1,
    ProposalDecisionPackageV1,
    ProposalDraftBuilder,
    ProposalDraftV1,
    ProposalEvidenceV1,
)
from .proposal_store import _SQLiteProposalStore


class ProposalClock(Protocol):
    def now(self) -> datetime: ...


class _CallableClock:
    def __init__(self, callback: Callable[[], datetime]) -> None:
        self._callback = callback

    def now(self) -> datetime:
        return self._callback()


class SQLiteProposalService:
    """Build and persist one unresolved proposal with exact retry semantics."""

    def __init__(
        self,
        database: object,
        *,
        authority: CohortMergeAuthority | None = None,
        clock: ProposalClock | Callable[[], datetime] | None = None,
    ) -> None:
        if isinstance(database, _SQLiteProposalStore):
            raise CapabilityGapValidationError("invalid_proposal_database")
        if authority is not None and not hasattr(authority, "authorize"):
            raise CapabilityGapValidationError("invalid_merge_authority")
        if clock is None:
            self._clock: ProposalClock = _CallableClock(lambda: datetime.now(UTC))
        elif callable(clock):
            self._clock = _CallableClock(clock)
        elif hasattr(clock, "now"):
            self._clock = clock
        else:
            raise CapabilityGapValidationError("invalid_proposal_clock")
        self._store = _SQLiteProposalStore(database)
        self._authority = authority

    def close(self) -> None:
        self._store.close()

    def __enter__(self) -> SQLiteProposalService:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def lookup(self, gap_keys: Iterable[str]) -> ProposalDecisionPackageV1 | None:
        return self._store.lookup(gap_keys)

    def get_by_gap_key(self, gap_key: str) -> ProposalDecisionPackageV1 | None:
        return self._store.get_by_gap_key(gap_key)

    def get_by_decision_id(self, decision_id: str) -> ProposalDecisionPackageV1 | None:
        return self._store.get_by_decision_id(decision_id)

    def get_by_proposal_id(self, proposal_id: str) -> ProposalDecisionPackageV1 | None:
        return self._store.get_by_proposal_id(proposal_id)

    def create(
        self,
        candidates: Iterable[CandidateSnapshot],
        builder: ProposalDraftBuilder | Callable[[ProposalEvidenceV1], ProposalDraftV1],
    ) -> ProposalDecisionPackageV1:
        """Create or retrieve a package; callbacks run only for a new cohort."""
        try:
            candidate_iter = iter(candidates)
        except TypeError as error:
            raise CapabilityGapValidationError("invalid_candidates") from error
        snapshots: list[CandidateSnapshot] = []
        for _ in range(MAX_CANDIDATES + 1):
            try:
                snapshots.append(next(candidate_iter))
            except StopIteration:
                break
        if not snapshots or len(snapshots) > MAX_CANDIDATES:
            raise CapabilityGapValidationError("invalid_candidates")
        # Validate the outer snapshots and their bounded containers before
        # iterating or decoding any candidate contents.
        total_contributions = 0
        total_active_work = 0
        for item in snapshots:
            if type(item) is not CandidateSnapshot:
                raise CapabilityGapValidationError("invalid_candidate_snapshot")
            if type(item.contributions) is not tuple or type(item.active_work) is not tuple:
                raise CapabilityGapValidationError("invalid_candidate_snapshot")
            if (
                len(item.contributions) > MAX_CONTRIBUTIONS_PER_CANDIDATE
                or len(item.active_work) > MAX_ACTIVE_WORK_PER_CANDIDATE
            ):
                raise CapabilityGapValidationError("evidence_bounds")
            total_contributions += len(item.contributions)
            total_active_work += len(item.active_work)
            if (
                total_contributions > MAX_TOTAL_CONTRIBUTIONS
                or total_active_work > MAX_TOTAL_ACTIVE_WORK
            ):
                raise CapabilityGapValidationError("evidence_bounds")
        # This is deliberately before the store lookup: malformed caller data
        # cannot turn into a successful retry.
        built: list[ProposalCandidateV1] = []
        evidence_bytes = 0
        for item in snapshots:
            candidate = ProposalCandidateV1.from_snapshot(item)
            candidate_bytes = len(canonical_json_bytes(cast(Any, candidate.to_json())))
            if candidate_bytes > MAX_CANDIDATE_BYTES:
                raise CapabilityGapValidationError("evidence_bounds")
            evidence_bytes += candidate_bytes
            if evidence_bytes > MAX_EVIDENCE_BYTES:
                raise CapabilityGapValidationError("evidence_bounds")
            built.append(candidate)
        built_candidates = tuple(sorted(built, key=lambda item: item.gap_key))
        keys = tuple(item.gap_key for item in built_candidates)
        if len(set(keys)) != len(keys):
            raise CapabilityGapCollisionError("duplicate_candidate")

        existing = self._store.lookup(keys)
        if existing is not None:
            return existing

        receipt: CohortMergeReceiptV1 | None = None
        if len(keys) > 1:
            if self._authority is None:
                raise CapabilityGapCollisionError("merge_authority_required")
            receipt = self._authority.authorize(keys)
            if receipt is None:
                raise CapabilityGapCollisionError("merge_authority_rejected")
            if not isinstance(receipt, CohortMergeReceiptV1) or receipt.candidate_gap_keys != keys:
                raise CapabilityGapCollisionError("merge_authority_mismatch")
        evidence = ProposalEvidenceV1(
            1, built_candidates, None if receipt is None else _review_from_receipt(receipt)
        )
        if len(evidence.to_bytes()) > MAX_EVIDENCE_BYTES:
            raise CapabilityGapValidationError("oversized_evidence")
        try:
            draft = builder.build(evidence) if hasattr(builder, "build") else builder(evidence)
        except BaseException:
            raise
        if not isinstance(draft, ProposalDraftV1):
            raise CapabilityGapValidationError("invalid_draft")
        # Re-run all draft invariants through its constructor-backed codec.
        draft = ProposalDraftV1.from_bytes(draft.to_bytes())
        created_at = self._clock.now()
        if (
            not isinstance(created_at, datetime)
            or created_at.tzinfo is None
            or created_at.utcoffset() is None
        ):
            raise CapabilityGapValidationError("invalid_proposal_clock")
        proposal = ImprovementProposalV1.create(evidence, draft, created_at.astimezone(UTC))
        package = ProposalDecisionPackageV1.create(proposal)
        if len(package.to_bytes()) > 2 * 1024 * 1024:
            raise CapabilityGapValidationError("oversized_package")
        return self._store._create_or_get(package)

    create_proposal = create


def _review_from_receipt(receipt: CohortMergeReceiptV1) -> Any:
    from .proposal_contracts import ProposalMergeReviewV1

    return ProposalMergeReviewV1(
        receipt.candidate_gap_keys, receipt.review_id, receipt.merge_review_fingerprint
    )


ProposalService = SQLiteProposalService

__all__ = ["ProposalClock", "ProposalService", "SQLiteProposalService"]
