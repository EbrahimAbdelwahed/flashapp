"""Closed, canonical contracts for immutable capability-gap proposals.

This module intentionally contains data and validation only.  Proposal builders
are behavior-layer callbacks supplied by the private factory; they cannot reach
the database or any external system through these types.
"""

from __future__ import annotations

import base64
import re
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from hashlib import sha256
from typing import Any, Protocol, cast, runtime_checkable

from study_agent.feedback.outbox import (
    GapOutboxDimensions,
    GapOutboxRecord,
)
from study_agent.state import canonical_json_bytes, canonical_json_object

from .contracts import (
    ActiveWorkKind,
    CandidateSnapshot,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
    ReproductionStatus,
)

_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_OPAQUE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$")
_DOMAIN_MERGE = b"study-agent-devkit-gap05c-merge-review-v1\0"
_DOMAIN_COHORT = b"study-agent-devkit-gap05c-cohort-v1\0"
_DOMAIN_EVIDENCE = b"study-agent-devkit-gap05c-evidence-v1\0"
_DOMAIN_PROPOSAL = b"study-agent-devkit-gap05c-proposal-v1\0"
_DOMAIN_DECISION = b"study-agent-devkit-gap05c-decision-v1\0"
_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$")

MAX_CANDIDATES = 16
MAX_CONTRIBUTIONS_PER_CANDIDATE = 256
MAX_TOTAL_CONTRIBUTIONS = 256
MAX_ACTIVE_WORK_PER_CANDIDATE = 256
MAX_TOTAL_ACTIVE_WORK = 256
MAX_CANDIDATE_BYTES = 512 * 1024
MAX_EVIDENCE_BYTES = 1024 * 1024
MAX_TEXT_BYTES = 16 * 1024
MAX_DRAFT_BYTES = 512 * 1024
MAX_PACKAGE_BYTES = 2 * 1024 * 1024


class RequestedAuthority(StrEnum):
    PLANNING_ONLY = "planning_only"
    PLANNING_AND_IMPLEMENTATION_GOAL = "planning_and_implementation_goal"


class DraftArtifactKind(StrEnum):
    ADR = "adr"
    SPEC = "spec"
    BEAD = "bead"


class DraftArtifactState(StrEnum):
    DRAFT = "draft"


class DecisionStatus(StrEnum):
    UNRESOLVED = "unresolved"


class ProposalContractError(ValueError):
    """A value does not satisfy the closed proposal contract."""


def _fail(message: str) -> None:
    raise ProposalContractError(message)


def _digest(value: object, field: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return cast(str, value)


def _opaque(value: object, field: str) -> str:
    if not isinstance(value, str) or _OPAQUE.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return cast(str, value)


def _text(value: object, field: str, *, max_bytes: int = MAX_TEXT_BYTES) -> str:
    if not isinstance(value, str):
        _fail(f"invalid_{field}")
    try:
        encoded = cast(str, value).encode("utf-8")
    except UnicodeEncodeError:
        _fail(f"invalid_{field}_utf8")
    if len(encoded) > max_bytes:
        _fail(f"oversized_{field}")
    if any(
        (ord(char) < 32 or 0x7F <= ord(char) <= 0x9F) and char not in "\t\n"
        for char in cast(str, value)
    ):
        _fail(f"invalid_{field}_control")
    return cast(str, value)


def _schema(value: object, field: str = "schema_version") -> int:
    if type(value) is not int or value != 1:
        _fail(f"invalid_{field}")
    return cast(int, value)


def _exact(
    data: bytes, fields: tuple[str, ...], *, max_bytes: int
) -> Mapping[str, Any]:
    if type(data) is not bytes or len(data) > max_bytes:
        raise CapabilityGapCorruptionError("invalid_proposal_payload")
    try:
        value = canonical_json_object(data)
    except (TypeError, ValueError, UnicodeDecodeError):
        raise CapabilityGapCorruptionError("invalid_proposal_payload") from None
    if tuple(sorted(value)) != tuple(sorted(fields)):
        raise CapabilityGapCorruptionError("invalid_proposal_fields")
    if canonical_json_bytes(cast(Any, value)) != data:
        raise CapabilityGapCorruptionError("noncanonical_proposal_payload")
    return value


def _timestamp(value: object, field: str = "created_at") -> datetime:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        _fail(f"invalid_{field}")
    normalized = cast(datetime, value).astimezone(UTC)
    return normalized


def _timestamp_bytes(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _parse_timestamp(value: object, field: str = "created_at") -> datetime:
    if not isinstance(value, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z", value
    ):
        raise CapabilityGapCorruptionError(f"invalid_{field}")
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        raise CapabilityGapCorruptionError(f"invalid_{field}") from None


def _as_tuple(value: object, field: str) -> tuple[Any, ...]:
    if not isinstance(value, list | tuple):
        raise CapabilityGapCorruptionError(f"invalid_{field}")
    return tuple(value)


def _hash(domain: bytes, value: bytes) -> str:
    return sha256(domain + value).hexdigest()


@dataclass(frozen=True, slots=True)
class CohortMergeReceiptV1:
    candidate_gap_keys: tuple[str, ...]
    review_id: str

    def __post_init__(self) -> None:
        if not isinstance(self.candidate_gap_keys, tuple):
            _fail("candidate_gap_keys_must_be_tuple")
        if not self.candidate_gap_keys or any(
            _HEX64.fullmatch(key) is None for key in self.candidate_gap_keys
        ):
            _fail("invalid_candidate_gap_keys")
        if self.candidate_gap_keys != tuple(sorted(self.candidate_gap_keys)) or len(
            set(self.candidate_gap_keys)
        ) != len(self.candidate_gap_keys):
            _fail("candidate_gap_keys_not_canonical")
        _opaque(self.review_id, "review_id")

    def to_json(self) -> dict[str, object]:
        return {"candidate_gap_keys": self.candidate_gap_keys, "review_id": self.review_id}

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> CohortMergeReceiptV1:
        value = _exact(
            data, ("candidate_gap_keys", "review_id"), max_bytes=MAX_EVIDENCE_BYTES
        )
        try:
            result = cls(
                tuple(
                    cast(str, item)
                    for item in _as_tuple(value["candidate_gap_keys"], "candidate_gap_keys")
                ),
                cast(str, value["review_id"]),
            )
        except (TypeError, ValueError, ProposalContractError):
            raise CapabilityGapCorruptionError("invalid_merge_receipt") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_merge_receipt")
        return result

    @property
    def merge_review_fingerprint(self) -> str:
        return _hash(_DOMAIN_MERGE, canonical_json_bytes(cast(Any, self.to_json())))


@runtime_checkable
class CohortMergeAuthority(Protocol):
    def authorize(self, candidate_gap_keys: tuple[str, ...]) -> CohortMergeReceiptV1 | None: ...


@dataclass(frozen=True, slots=True)
class ProposalActiveWorkV1:
    kind: ActiveWorkKind
    work_id: str

    def __post_init__(self) -> None:
        if not isinstance(self.kind, ActiveWorkKind):
            _fail("invalid_active_work_kind")
        _opaque(self.work_id, "work_id")

    def to_json(self) -> dict[str, object]:
        return {"kind": self.kind.value, "work_id": self.work_id}


@dataclass(frozen=True, slots=True)
class ProposalReproductionV1:
    status: ReproductionStatus
    fixture_id: str | None
    evidence_digest: str | None

    def __post_init__(self) -> None:
        if not isinstance(self.status, ReproductionStatus):
            _fail("invalid_reproduction_status")
        if self.status is ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT:
            if self.fixture_id is not None or self.evidence_digest is not None:
                _fail("invalid_missing_fixture_evidence")
        else:
            if self.fixture_id is None:
                _fail("missing_fixture_id")
            _opaque(self.fixture_id, "fixture_id")
            _digest(self.evidence_digest, "evidence_digest")

    def to_json(self) -> dict[str, object]:
        return {
            "evidence_digest": self.evidence_digest,
            "fixture_id": self.fixture_id,
            "status": self.status.value,
        }


@dataclass(frozen=True, slots=True)
class ProposalContributionV1:
    record_b64: str
    reproduction: ProposalReproductionV1

    def __post_init__(self) -> None:
        if not isinstance(self.record_b64, str):
            _fail("invalid_record_b64")
        try:
            raw = base64.b64decode(self.record_b64, validate=True)
        except (ValueError, TypeError):
            _fail("invalid_record_b64")
        if base64.b64encode(raw).decode("ascii") != self.record_b64:
            _fail("noncanonical_record_b64")
        try:
            record = GapOutboxRecord.from_bytes(raw)
        except Exception as error:
            raise CapabilityGapCorruptionError("invalid_record_b64") from error
        if record.to_bytes() != raw:
            raise CapabilityGapCorruptionError("noncanonical_record")
        if not isinstance(self.reproduction, ProposalReproductionV1):
            _fail("invalid_reproduction")

    @property
    def record_bytes(self) -> bytes:
        return base64.b64decode(self.record_b64, validate=True)

    def to_json(self) -> dict[str, object]:
        return {"record_b64": self.record_b64, "reproduction": self.reproduction.to_json()}


@dataclass(frozen=True, slots=True)
class ProposalCandidateV1:
    gap_key: str
    dimensions: GapOutboxDimensions
    contributions: tuple[ProposalContributionV1, ...]
    occurrence_count: int
    first_seen: datetime
    last_seen: datetime
    active_work: tuple[ProposalActiveWorkV1, ...]

    def __post_init__(self) -> None:
        _digest(self.gap_key, "gap_key")
        if not isinstance(self.dimensions, GapOutboxDimensions):
            _fail("invalid_dimensions")
        if type(self.dimensions.schema_version) is not int or self.dimensions.schema_version != 1:
            _fail("invalid_dimensions_schema_version")
        if (
            not isinstance(self.contributions, tuple)
            or not self.contributions
            or len(self.contributions) > MAX_CONTRIBUTIONS_PER_CANDIDATE
        ):
            _fail("invalid_contributions")
        if any(not isinstance(item, ProposalContributionV1) for item in self.contributions):
            _fail("invalid_contributions")
        if self.contributions != tuple(
            sorted(
                self.contributions,
                key=lambda item: (
                    item.record_bytes,
                    canonical_json_bytes(cast(Any, item.reproduction.to_json())),
                ),
            )
        ):
            _fail("contributions_not_canonical")
        if type(self.occurrence_count) is not int or self.occurrence_count < 1:
            _fail("invalid_occurrence_count")
        first = _timestamp(self.first_seen, "first_seen")
        last = _timestamp(self.last_seen, "last_seen")
        if last < first:
            _fail("invalid_seen_range")
        object.__setattr__(self, "first_seen", first)
        object.__setattr__(self, "last_seen", last)
        if (
            not isinstance(self.active_work, tuple)
            or len(self.active_work) > MAX_ACTIVE_WORK_PER_CANDIDATE
        ):
            _fail("invalid_active_work")
        if any(not isinstance(item, ProposalActiveWorkV1) for item in self.active_work):
            _fail("invalid_active_work")
        active = tuple((item.kind.value, item.work_id) for item in self.active_work)
        if active != tuple(sorted(active)) or len(set(active)) != len(active):
            _fail("active_work_not_canonical")
        total = 0
        first_record: datetime | None = None
        last_record: datetime | None = None
        for item in self.contributions:
            record = GapOutboxRecord.from_bytes(item.record_bytes)
            if record.gap_key.value != self.gap_key or record.dimensions != self.dimensions:
                raise CapabilityGapCorruptionError("candidate_record_mismatch")
            total += record.occurrence_count
            first_record = (
                record.first_seen if first_record is None else min(first_record, record.first_seen)
            )
            last_record = (
                record.last_seen if last_record is None else max(last_record, record.last_seen)
            )
        if (
            total != self.occurrence_count
            or first_record != self.first_seen
            or last_record != self.last_seen
        ):
            raise CapabilityGapCorruptionError("candidate_aggregate_mismatch")

    def to_json(self) -> dict[str, object]:
        return {
            "active_work": tuple(item.to_json() for item in self.active_work),
            "contributions": tuple(item.to_json() for item in self.contributions),
            "dimensions": self.dimensions.to_json(),
            "first_seen": _timestamp_bytes(self.first_seen),
            "gap_key": self.gap_key,
            "last_seen": _timestamp_bytes(self.last_seen),
            "occurrence_count": self.occurrence_count,
        }

    @classmethod
    def from_snapshot(cls, snapshot: CandidateSnapshot) -> ProposalCandidateV1:
        if not isinstance(snapshot, CandidateSnapshot):
            _fail("invalid_candidate_snapshot")
        contributions = tuple(
            ProposalContributionV1(
                base64.b64encode(item.record_bytes).decode("ascii"),
                ProposalReproductionV1(
                    item.reproduction.status,
                    item.reproduction.fixture_id,
                    item.reproduction.evidence_digest,
                ),
            )
            for item in snapshot.contributions
        )
        return cls(
            snapshot.gap_key,
            snapshot.dimensions,
            tuple(
                sorted(
                    contributions,
                    key=lambda item: (
                        item.record_bytes,
                        canonical_json_bytes(cast(Any, item.reproduction.to_json())),
                    ),
                )
            ),
            snapshot.occurrence_count,
            snapshot.first_seen,
            snapshot.last_seen,
            tuple(ProposalActiveWorkV1(item.kind, item.work_id) for item in snapshot.active_work),
        )


@dataclass(frozen=True, slots=True)
class ProposalMergeReviewV1:
    candidate_gap_keys: tuple[str, ...]
    review_id: str
    merge_review_fingerprint: str

    def __post_init__(self) -> None:
        receipt = CohortMergeReceiptV1(self.candidate_gap_keys, self.review_id)
        if self.merge_review_fingerprint != receipt.merge_review_fingerprint:
            raise CapabilityGapCorruptionError("merge_review_fingerprint_mismatch")

    def to_json(self) -> dict[str, object]:
        return {
            "candidate_gap_keys": self.candidate_gap_keys,
            "merge_review_fingerprint": self.merge_review_fingerprint,
            "review_id": self.review_id,
        }


@dataclass(frozen=True, slots=True)
class ProposalEvidenceV1:
    schema_version: int
    candidates: tuple[ProposalCandidateV1, ...]
    merge_review: ProposalMergeReviewV1 | None

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        if (
            not isinstance(self.candidates, tuple)
            or not self.candidates
            or len(self.candidates) > MAX_CANDIDATES
        ):
            _fail("invalid_candidates")
        if any(not isinstance(item, ProposalCandidateV1) for item in self.candidates):
            _fail("invalid_candidates")
        keys = tuple(item.gap_key for item in self.candidates)
        if keys != tuple(sorted(keys)) or len(set(keys)) != len(keys):
            _fail("candidates_not_canonical")
        if len(self.candidates) == 1 and self.merge_review is not None:
            _fail("unexpected_merge_review")
        if len(self.candidates) > 1 and (
            self.merge_review is None or self.merge_review.candidate_gap_keys != keys
        ):
            _fail("missing_merge_review")
        total_contributions = sum(len(item.contributions) for item in self.candidates)
        total_active = sum(len(item.active_work) for item in self.candidates)
        if total_contributions > MAX_TOTAL_CONTRIBUTIONS or total_active > MAX_TOTAL_ACTIVE_WORK:
            _fail("evidence_bounds")
        if any(
            len(canonical_json_bytes(cast(Any, item.to_json()))) > MAX_CANDIDATE_BYTES
            for item in self.candidates
        ):
            _fail("candidate_bytes_bound")

    @classmethod
    def from_snapshots(
        cls,
        snapshots: Iterable[CandidateSnapshot],
        merge_review: CohortMergeReceiptV1 | None = None,
    ) -> ProposalEvidenceV1:
        candidates = tuple(
            sorted(
                (ProposalCandidateV1.from_snapshot(item) for item in snapshots),
                key=lambda item: item.gap_key,
            )
        )
        review = (
            None
            if merge_review is None
            else ProposalMergeReviewV1(
                merge_review.candidate_gap_keys,
                merge_review.review_id,
                merge_review.merge_review_fingerprint,
            )
        )
        result = cls(1, candidates, review)
        if len(result.candidates) > 1 and merge_review is None:
            _fail("missing_merge_review")
        return result

    def to_json(self) -> dict[str, object]:
        return {
            "candidates": tuple(item.to_json() for item in self.candidates),
            "merge_review": None if self.merge_review is None else self.merge_review.to_json(),
            "schema_version": self.schema_version,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_EVIDENCE_BYTES:
            _fail("oversized_evidence")
        return data

    @property
    def candidate_gap_keys(self) -> tuple[str, ...]:
        return tuple(item.gap_key for item in self.candidates)

    @property
    def cohort_fingerprint(self) -> str:
        return _hash(
            _DOMAIN_COHORT,
            canonical_json_bytes(
                cast(
                    Any,
                    {
                        "candidate_gap_keys": self.candidate_gap_keys,
                        "merge_review_fingerprint": None
                        if self.merge_review is None
                        else self.merge_review.merge_review_fingerprint,
                    },
                )
            ),
        )

    @property
    def evidence_fingerprint(self) -> str:
        return _hash(_DOMAIN_EVIDENCE, self.to_bytes())

    @classmethod
    def from_bytes(cls, data: bytes) -> ProposalEvidenceV1:
        value = _exact(
            data,
            ("schema_version", "candidates", "merge_review"),
            max_bytes=MAX_EVIDENCE_BYTES,
        )
        try:
            candidates = []
            for raw in _as_tuple(value["candidates"], "candidates"):
                if not isinstance(raw, Mapping) or tuple(sorted(raw)) != tuple(
                    sorted(
                        (
                            "active_work",
                            "contributions",
                            "dimensions",
                            "first_seen",
                            "gap_key",
                            "last_seen",
                            "occurrence_count",
                        )
                    )
                ):
                    raise CapabilityGapCorruptionError("invalid_candidate")
                dimensions = GapOutboxDimensions.from_json(
                    cast(Mapping[str, object], raw["dimensions"])
                )
                contributions = []
                for contribution in _as_tuple(raw["contributions"], "contributions"):
                    if not isinstance(contribution, Mapping) or tuple(sorted(contribution)) != (
                        "record_b64",
                        "reproduction",
                    ):
                        raise CapabilityGapCorruptionError("invalid_contribution")
                    repro = contribution["reproduction"]
                    if not isinstance(repro, Mapping) or tuple(sorted(repro)) != (
                        "evidence_digest",
                        "fixture_id",
                        "status",
                    ):
                        raise CapabilityGapCorruptionError("invalid_reproduction")
                    contributions.append(
                        ProposalContributionV1(
                            cast(str, contribution["record_b64"]),
                            ProposalReproductionV1(
                                ReproductionStatus(cast(str, repro["status"])),
                                cast(str | None, repro["fixture_id"]),
                                cast(str | None, repro["evidence_digest"]),
                            ),
                        )
                    )
                active = []
                for link in _as_tuple(raw["active_work"], "active_work"):
                    if not isinstance(link, Mapping) or tuple(sorted(link)) != ("kind", "work_id"):
                        raise CapabilityGapCorruptionError("invalid_active_work")
                    active.append(
                        ProposalActiveWorkV1(
                            ActiveWorkKind(cast(str, link["kind"])), cast(str, link["work_id"])
                        )
                    )
                candidates.append(
                    ProposalCandidateV1(
                        cast(str, raw["gap_key"]),
                        dimensions,
                        tuple(contributions),
                        cast(int, raw["occurrence_count"]),
                        _parse_timestamp(raw["first_seen"], "first_seen"),
                        _parse_timestamp(raw["last_seen"], "last_seen"),
                        tuple(active),
                    )
                )
            merge_raw = value["merge_review"]
            merge = None
            if merge_raw is not None:
                if not isinstance(merge_raw, Mapping) or tuple(sorted(merge_raw)) != (
                    "candidate_gap_keys",
                    "merge_review_fingerprint",
                    "review_id",
                ):
                    raise CapabilityGapCorruptionError("invalid_merge_review")
                merge = ProposalMergeReviewV1(
                    tuple(
                        cast(str, item)
                        for item in _as_tuple(merge_raw["candidate_gap_keys"], "candidate_gap_keys")
                    ),
                    cast(str, merge_raw["review_id"]),
                    cast(str, merge_raw["merge_review_fingerprint"]),
                )
            result = cls(cast(int, value["schema_version"]), tuple(candidates), merge)
        except (
            TypeError,
            ValueError,
            KeyError,
            ProposalContractError,
            CapabilityGapValidationError,
            CapabilityGapCorruptionError,
        ):
            raise CapabilityGapCorruptionError("invalid_evidence") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_evidence")
        return result


@runtime_checkable
class ProposalDraftBuilder(Protocol):
    def build(self, evidence: ProposalEvidenceV1) -> ProposalDraftV1: ...


@dataclass(frozen=True, slots=True)
class ProposalOptionV1:
    option_id: str
    summary: str
    tradeoffs: tuple[str, ...]

    def __post_init__(self) -> None:
        _opaque(self.option_id, "option_id")
        _text(self.summary, "summary")
        if not isinstance(self.tradeoffs, tuple) or not self.tradeoffs or len(self.tradeoffs) > 8:
            _fail("invalid_tradeoffs")
        for item in self.tradeoffs:
            _text(item, "tradeoff")

    def to_json(self) -> dict[str, object]:
        return {"option_id": self.option_id, "summary": self.summary, "tradeoffs": self.tradeoffs}


@dataclass(frozen=True, slots=True)
class DraftArtifactV1:
    kind: DraftArtifactKind
    artifact_id: str
    artifact_state: DraftArtifactState
    body: str
    depends_on: tuple[str, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.kind, DraftArtifactKind):
            _fail("invalid_artifact_kind")
        _opaque(self.artifact_id, "artifact_id")
        if self.artifact_state is not DraftArtifactState.DRAFT:
            _fail("invalid_artifact_state")
        _text(self.body, "artifact_body")
        if not isinstance(self.depends_on, tuple) or len(self.depends_on) > 64:
            _fail("invalid_dependencies")
        for item in self.depends_on:
            _opaque(item, "dependency")
        if self.kind in (DraftArtifactKind.ADR, DraftArtifactKind.SPEC) and self.depends_on:
            _fail("adr_spec_dependencies_forbidden")

    def to_json(self) -> dict[str, object]:
        return {
            "artifact_id": self.artifact_id,
            "artifact_state": self.artifact_state.value,
            "body": self.body,
            "depends_on": self.depends_on,
            "kind": self.kind.value,
        }


@dataclass(frozen=True, slots=True)
class ProposalDraftV1:
    schema_version: int
    options: tuple[ProposalOptionV1, ...]
    recommended_option_id: str
    artifacts: tuple[DraftArtifactV1, ...]
    verification: tuple[str, ...]
    non_goals: tuple[str, ...]
    requested_authority: RequestedAuthority

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        if not isinstance(self.options, tuple) or not 2 <= len(self.options) <= 5:
            _fail("invalid_options")
        option_ids = tuple(item.option_id for item in self.options)
        if any(not isinstance(item, ProposalOptionV1) for item in self.options) or len(
            set(option_ids)
        ) != len(option_ids):
            _fail("invalid_options")
        _opaque(self.recommended_option_id, "recommended_option_id")
        if self.recommended_option_id not in option_ids:
            _fail("missing_recommendation")
        if not isinstance(self.artifacts, tuple) or not 3 <= len(self.artifacts) <= 66:
            _fail("invalid_artifacts")
        if any(not isinstance(item, DraftArtifactV1) for item in self.artifacts):
            _fail("invalid_artifacts")
        ids = tuple(item.artifact_id for item in self.artifacts)
        if len(set(ids)) != len(ids):
            _fail("duplicate_artifact_id")
        kinds = tuple(item.kind for item in self.artifacts)
        if (
            kinds.count(DraftArtifactKind.ADR) != 1
            or kinds.count(DraftArtifactKind.SPEC) != 1
            or kinds.count(DraftArtifactKind.BEAD) < 1
        ):
            _fail("artifact_kind_counts")
        id_set = set(ids)
        for artifact in self.artifacts:
            if artifact.kind is DraftArtifactKind.BEAD and any(
                dep not in id_set for dep in artifact.depends_on
            ):
                _fail("unknown_dependency")
        # Dependency edges are bead-only and must be acyclic.
        graph = {
            item.artifact_id: tuple(item.depends_on)
            for item in self.artifacts
            if item.kind is DraftArtifactKind.BEAD
        }
        visiting: set[str] = set()
        visited: set[str] = set()

        def visit(node: str) -> None:
            if node in visiting:
                _fail("dependency_cycle")
            if node in visited:
                return
            visiting.add(node)
            for dep in graph.get(node, ()):
                if dep in graph:
                    visit(dep)
                else:
                    _fail("non_bead_dependency")
            visiting.remove(node)
            visited.add(node)

        for node in graph:
            visit(node)
        if not isinstance(self.verification, tuple) or not 1 <= len(self.verification) <= 64:
            _fail("invalid_verification")
        if not isinstance(self.non_goals, tuple) or not 1 <= len(self.non_goals) <= 64:
            _fail("invalid_non_goals")
        for item in self.verification:
            _text(item, "verification")
        for item in self.non_goals:
            _text(item, "non_goal")
        if not isinstance(self.requested_authority, RequestedAuthority):
            _fail("invalid_requested_authority")

    def to_json(self) -> dict[str, object]:
        return {
            "artifacts": tuple(item.to_json() for item in self.artifacts),
            "non_goals": self.non_goals,
            "options": tuple(item.to_json() for item in self.options),
            "recommended_option_id": self.recommended_option_id,
            "requested_authority": self.requested_authority.value,
            "schema_version": self.schema_version,
            "verification": self.verification,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_DRAFT_BYTES:
            _fail("oversized_draft")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> ProposalDraftV1:
        value = _exact(
            data,
            (
                "artifacts",
                "non_goals",
                "options",
                "recommended_option_id",
                "requested_authority",
                "schema_version",
                "verification",
            ),
            max_bytes=MAX_DRAFT_BYTES,
        )
        try:
            options_list: list[ProposalOptionV1] = []
            for item in _as_tuple(value["options"], "options"):
                if not isinstance(item, Mapping) or tuple(sorted(item)) != (
                    "option_id",
                    "summary",
                    "tradeoffs",
                ):
                    raise CapabilityGapCorruptionError("invalid_option")
                options_list.append(
                    ProposalOptionV1(
                        cast(str, item["option_id"]),
                        cast(str, item["summary"]),
                        tuple(
                            cast(str, trade) for trade in _as_tuple(item["tradeoffs"], "tradeoffs")
                        ),
                    )
                )
            artifacts_list: list[DraftArtifactV1] = []
            for item in _as_tuple(value["artifacts"], "artifacts"):
                if not isinstance(item, Mapping) or tuple(sorted(item)) != (
                    "artifact_id",
                    "artifact_state",
                    "body",
                    "depends_on",
                    "kind",
                ):
                    raise CapabilityGapCorruptionError("invalid_artifact")
                artifacts_list.append(
                    DraftArtifactV1(
                        DraftArtifactKind(cast(str, item["kind"])),
                        cast(str, item["artifact_id"]),
                        DraftArtifactState(cast(str, item["artifact_state"])),
                        cast(str, item["body"]),
                        tuple(
                            cast(str, dep) for dep in _as_tuple(item["depends_on"], "depends_on")
                        ),
                    )
                )
            options = tuple(options_list)
            artifacts = tuple(artifacts_list)
            result = cls(
                cast(int, value["schema_version"]),
                options,
                cast(str, value["recommended_option_id"]),
                artifacts,
                tuple(cast(str, item) for item in _as_tuple(value["verification"], "verification")),
                tuple(cast(str, item) for item in _as_tuple(value["non_goals"], "non_goals")),
                RequestedAuthority(cast(str, value["requested_authority"])),
            )
        except (TypeError, ValueError, KeyError, ProposalContractError):
            raise CapabilityGapCorruptionError("invalid_draft") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_draft")
        return result


@dataclass(frozen=True, slots=True)
class ImprovementProposalV1:
    schema_version: int
    proposal_id: str
    cohort_fingerprint: str
    evidence_fingerprint: str
    evidence: ProposalEvidenceV1
    draft: ProposalDraftV1
    created_at: datetime

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.proposal_id, "proposal_id")
        _digest(self.cohort_fingerprint, "cohort_fingerprint")
        _digest(self.evidence_fingerprint, "evidence_fingerprint")
        if not isinstance(self.evidence, ProposalEvidenceV1) or not isinstance(
            self.draft, ProposalDraftV1
        ):
            _fail("invalid_proposal_components")
        created = _timestamp(self.created_at)
        object.__setattr__(self, "created_at", created)
        if (
            self.evidence.cohort_fingerprint != self.cohort_fingerprint
            or self.evidence.evidence_fingerprint != self.evidence_fingerprint
        ):
            raise CapabilityGapCorruptionError("proposal_fingerprint_mismatch")
        if self.proposal_id != self.derive_id(
            self.cohort_fingerprint, self.evidence_fingerprint, self.evidence, self.draft, created
        ):
            raise CapabilityGapCorruptionError("proposal_id_mismatch")

    @staticmethod
    def derive_id(
        cohort_fingerprint: str,
        evidence_fingerprint: str,
        evidence: ProposalEvidenceV1,
        draft: ProposalDraftV1,
        created_at: datetime,
    ) -> str:
        body = {
            "cohort_fingerprint": cohort_fingerprint,
            "created_at": _timestamp_bytes(created_at),
            "draft": draft.to_json(),
            "evidence": evidence.to_json(),
            "evidence_fingerprint": evidence_fingerprint,
            "schema_version": 1,
        }
        return _hash(_DOMAIN_PROPOSAL, canonical_json_bytes(cast(Any, body)))

    @classmethod
    def create(
        cls, evidence: ProposalEvidenceV1, draft: ProposalDraftV1, created_at: datetime
    ) -> ImprovementProposalV1:
        created = _timestamp(created_at)
        return cls(
            1,
            cls.derive_id(
                evidence.cohort_fingerprint, evidence.evidence_fingerprint, evidence, draft, created
            ),
            evidence.cohort_fingerprint,
            evidence.evidence_fingerprint,
            evidence,
            draft,
            created,
        )

    def to_json(self) -> dict[str, object]:
        return {
            "cohort_fingerprint": self.cohort_fingerprint,
            "created_at": _timestamp_bytes(self.created_at),
            "draft": self.draft.to_json(),
            "evidence": self.evidence.to_json(),
            "evidence_fingerprint": self.evidence_fingerprint,
            "proposal_id": self.proposal_id,
            "schema_version": self.schema_version,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> ImprovementProposalV1:
        value = _exact(
            data,
            (
                "cohort_fingerprint",
                "created_at",
                "draft",
                "evidence",
                "evidence_fingerprint",
                "proposal_id",
                "schema_version",
            ),
            max_bytes=MAX_PACKAGE_BYTES,
        )
        try:
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["proposal_id"]),
                cast(str, value["cohort_fingerprint"]),
                cast(str, value["evidence_fingerprint"]),
                ProposalEvidenceV1.from_bytes(canonical_json_bytes(cast(Any, value["evidence"]))),
                ProposalDraftV1.from_bytes(canonical_json_bytes(cast(Any, value["draft"]))),
                _parse_timestamp(value["created_at"]),
            )
        except (
            TypeError,
            ValueError,
            KeyError,
            ProposalContractError,
            CapabilityGapCorruptionError,
        ):
            raise CapabilityGapCorruptionError("invalid_proposal") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_proposal")
        return result


@dataclass(frozen=True, slots=True)
class MaintainerDecisionRequestV1:
    schema_version: int
    decision_id: str
    proposal_id: str
    requested_authority: RequestedAuthority
    status: DecisionStatus
    created_at: datetime

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.decision_id, "decision_id")
        _digest(self.proposal_id, "proposal_id")
        if (
            not isinstance(self.requested_authority, RequestedAuthority)
            or self.status is not DecisionStatus.UNRESOLVED
        ):
            _fail("invalid_decision")
        created = _timestamp(self.created_at)
        object.__setattr__(self, "created_at", created)
        if self.decision_id != self.derive_id(self.proposal_id, self.requested_authority, created):
            raise CapabilityGapCorruptionError("decision_id_mismatch")

    @staticmethod
    def derive_id(
        proposal_id: str, requested_authority: RequestedAuthority, created_at: datetime
    ) -> str:
        body = {
            "created_at": _timestamp_bytes(created_at),
            "proposal_id": proposal_id,
            "requested_authority": requested_authority.value,
            "schema_version": 1,
            "status": DecisionStatus.UNRESOLVED.value,
        }
        return _hash(_DOMAIN_DECISION, canonical_json_bytes(cast(Any, body)))

    @classmethod
    def create(cls, proposal: ImprovementProposalV1) -> MaintainerDecisionRequestV1:
        return cls(
            1,
            cls.derive_id(
                proposal.proposal_id, proposal.draft.requested_authority, proposal.created_at
            ),
            proposal.proposal_id,
            proposal.draft.requested_authority,
            DecisionStatus.UNRESOLVED,
            proposal.created_at,
        )

    def to_json(self) -> dict[str, object]:
        return {
            "created_at": _timestamp_bytes(self.created_at),
            "decision_id": self.decision_id,
            "proposal_id": self.proposal_id,
            "requested_authority": self.requested_authority.value,
            "schema_version": self.schema_version,
            "status": self.status.value,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> MaintainerDecisionRequestV1:
        value = _exact(
            data,
            (
                "created_at",
                "decision_id",
                "proposal_id",
                "requested_authority",
                "schema_version",
                "status",
            ),
            max_bytes=MAX_PACKAGE_BYTES,
        )
        try:
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["decision_id"]),
                cast(str, value["proposal_id"]),
                RequestedAuthority(cast(str, value["requested_authority"])),
                DecisionStatus(cast(str, value["status"])),
                _parse_timestamp(value["created_at"]),
            )
        except (
            TypeError,
            ValueError,
            KeyError,
            ProposalContractError,
            CapabilityGapCorruptionError,
        ):
            raise CapabilityGapCorruptionError("invalid_decision") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_decision")
        return result


@dataclass(frozen=True, slots=True)
class ProposalDecisionPackageV1:
    schema_version: int
    proposal: ImprovementProposalV1
    decision: MaintainerDecisionRequestV1

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        if not isinstance(self.proposal, ImprovementProposalV1) or not isinstance(
            self.decision, MaintainerDecisionRequestV1
        ):
            _fail("invalid_package")
        if (
            self.decision.proposal_id != self.proposal.proposal_id
            or self.decision.created_at != self.proposal.created_at
        ):
            raise CapabilityGapCorruptionError("package_cross_link_mismatch")
        if self.decision.requested_authority is not self.proposal.draft.requested_authority:
            raise CapabilityGapCorruptionError("package_authority_mismatch")

    @classmethod
    def create(cls, proposal: ImprovementProposalV1) -> ProposalDecisionPackageV1:
        return cls(1, proposal, MaintainerDecisionRequestV1.create(proposal))

    def to_json(self) -> dict[str, object]:
        return {
            "decision": self.decision.to_json(),
            "proposal": self.proposal.to_json(),
            "schema_version": self.schema_version,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_PACKAGE_BYTES:
            _fail("oversized_package")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> ProposalDecisionPackageV1:
        value = _exact(
            data,
            ("decision", "proposal", "schema_version"),
            max_bytes=MAX_PACKAGE_BYTES,
        )
        try:
            result = cls(
                cast(int, value["schema_version"]),
                ImprovementProposalV1.from_bytes(
                    canonical_json_bytes(cast(Any, value["proposal"]))
                ),
                MaintainerDecisionRequestV1.from_bytes(
                    canonical_json_bytes(cast(Any, value["decision"]))
                ),
            )
        except (
            TypeError,
            ValueError,
            KeyError,
            ProposalContractError,
            CapabilityGapCorruptionError,
        ):
            raise CapabilityGapCorruptionError("invalid_package") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_package")
        return result


__all__ = [
    "MAX_PACKAGE_BYTES",
    "CohortMergeAuthority",
    "CohortMergeReceiptV1",
    "DecisionStatus",
    "DraftArtifactKind",
    "DraftArtifactState",
    "DraftArtifactV1",
    "ImprovementProposalV1",
    "MaintainerDecisionRequestV1",
    "ProposalActiveWorkV1",
    "ProposalCandidateV1",
    "ProposalContractError",
    "ProposalContributionV1",
    "ProposalDecisionPackageV1",
    "ProposalDraftBuilder",
    "ProposalDraftV1",
    "ProposalEvidenceV1",
    "ProposalMergeReviewV1",
    "ProposalOptionV1",
    "ProposalReproductionV1",
    "RequestedAuthority",
]
