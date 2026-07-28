"""Closed, canonical contracts for maintainer resolution and promotion."""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from hashlib import sha256
from typing import Any, NoReturn, Protocol, cast, runtime_checkable

from study_agent.state import canonical_json_bytes, canonical_json_object

from study_agent_devkit.flywheel.materialization import (
    MaterializationPlanV1,
    validate_materialization_plan,
)

from .contracts import (
    ActiveWorkKind,
    CapabilityGapCorruptionError,
    CapabilityGapValidationError,
    ReproductionStatus,
)
from .proposal_contracts import (
    DraftArtifactKind,
    ProposalDecisionPackageV1,
    RequestedAuthority,
)

SCHEMA_VERSION = 1
MAX_COMMAND_BYTES = 128 * 1024
MAX_RESOLUTION_BYTES = 256 * 1024
MAX_PROMOTION_BYTES = 2 * 1024 * 1024
MAX_RECEIPT_BYTES = 64 * 1024
MAX_GRILL_RECEIPTS = 65
MAX_TEXT_BYTES = 16 * 1024
MAX_CONTEXT_BYTES = 256 * 1024
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_OPAQUE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$")
_DOMAIN_AUTHORITY = b"study-agent-devkit-gap06-authority-v1\0"
_DOMAIN_RESOLUTION = b"study-agent-devkit-gap06-resolution-v1\0"
_DOMAIN_PROMOTION = b"study-agent-devkit-gap06-promotion-v1\0"
_DOMAIN_GOAL = b"study-agent-devkit-gap06-goal-v1\0"
_DOMAIN_PACKAGE = b"study-agent-devkit-gap06-package-v1\0"
_DOMAIN_PROMOTION_BYTES = b"study-agent-devkit-gap06-promotion-bytes-v1\0"
_DOMAIN_FILE_MANIFEST = b"study-agent-devkit-gap06-file-manifest-v1\0"
_DOMAIN_RECEIPT = b"study-agent-devkit-gap06-receipt-v1\0"


class ResolutionContractError(ValueError):
    """A host value violates the closed resolution contract."""


class GrillSubjectKind(StrEnum):
    PROPOSAL = "proposal"
    BEAD = "bead"


class ResolutionOutcome(StrEnum):
    REJECTED = "rejected"
    DEFERRED = "deferred"
    DUPLICATE = "duplicate"
    ACCEPTED = "accepted"


def _fail(message: str) -> NoReturn:
    raise ResolutionContractError(message)


def _schema(value: object) -> int:
    if type(value) is not int or value != SCHEMA_VERSION:
        _fail("invalid_schema_version")
    return value


def _opaque(value: object, field: str) -> str:
    if not isinstance(value, str) or _OPAQUE.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return value


def _digest(value: object, field: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return value


def _text(value: object, field: str, *, max_bytes: int = MAX_TEXT_BYTES) -> str:
    if not isinstance(value, str):
        _fail(f"invalid_{field}")
    try:
        raw = value.encode("utf-8")
    except UnicodeEncodeError:
        _fail(f"invalid_{field}_utf8")
    if len(raw) > max_bytes:
        _fail(f"oversized_{field}")
    if any((ord(c) < 32 or 0x7F <= ord(c) <= 0x9F) and c not in "\t\n" for c in value):
        _fail(f"invalid_{field}_control")
    return value


def _timestamp(value: object, field: str = "resolved_at") -> datetime:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        _fail(f"invalid_{field}")
    normalized = value.astimezone(UTC)
    if normalized.microsecond != value.microsecond:
        _fail(f"invalid_{field}")
    return normalized


def _timestamp_bytes(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _parse_timestamp(value: object, field: str = "resolved_at") -> datetime:
    if (
        not isinstance(value, str)
        or re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z", value) is None
    ):
        raise CapabilityGapCorruptionError(f"invalid_{field}")
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        raise CapabilityGapCorruptionError(f"invalid_{field}") from None


def _exact(data: bytes, fields: tuple[str, ...], *, max_bytes: int) -> Mapping[str, Any]:
    if type(data) is not bytes or len(data) > max_bytes:
        raise CapabilityGapCorruptionError("invalid_resolution_payload")
    try:
        value = canonical_json_object(data)
    except (TypeError, ValueError, UnicodeDecodeError):
        raise CapabilityGapCorruptionError("invalid_resolution_payload") from None
    if tuple(sorted(value)) != tuple(sorted(fields)):
        raise CapabilityGapCorruptionError("invalid_resolution_fields")
    if canonical_json_bytes(cast(Any, value)) != data:
        raise CapabilityGapCorruptionError("noncanonical_resolution_payload")
    return value


def _seq(value: object, field: str, *, max_items: int) -> tuple[object, ...]:
    if not isinstance(value, list | tuple) or len(value) > max_items:
        raise CapabilityGapCorruptionError(f"invalid_{field}")
    return tuple(cast(list[object] | tuple[object, ...], value))


def _hash(domain: bytes, body: Mapping[str, Any]) -> str:
    return sha256(domain + canonical_json_bytes(cast(Any, body))).hexdigest()


@runtime_checkable
class ProposalPackageSource(Protocol):
    def get_by_decision_id(self, decision_id: str) -> ProposalDecisionPackageV1 | None: ...

    def get_by_proposal_id(self, proposal_id: str) -> ProposalDecisionPackageV1 | None: ...


@runtime_checkable
class MaintainerResolutionAuthority(Protocol):
    def resolve(self, decision: DecisionViewV1) -> ResolutionCommandV1 | None: ...


@runtime_checkable
class ResolutionClock(Protocol):
    def now(self) -> datetime: ...


@runtime_checkable
class FlywheelPromotionSink(Protocol):
    @property
    def sink_id(self) -> str: ...

    def apply(self, bundle: FlywheelPromotionBundleV1) -> FlywheelPromotionReceiptV1: ...


@dataclass(frozen=True, slots=True)
class DecisionViewV1:
    schema_version: int
    proposal_id: str
    decision_id: str
    requested_authority: RequestedAuthority
    option_ids: tuple[str, ...]
    bead_ids: tuple[str, ...]
    package_fingerprint: str

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.proposal_id, "proposal_id")
        _digest(self.decision_id, "decision_id")
        if not isinstance(self.requested_authority, RequestedAuthority):
            _fail("invalid_requested_authority")
        if type(self.option_ids) is not tuple or not 1 <= len(self.option_ids) <= 5:
            _fail("invalid_option_ids")
        if any(_opaque(item, "option_id") != item for item in self.option_ids):
            _fail("invalid_option_ids")
        if self.option_ids != tuple(sorted(self.option_ids)) or len(set(self.option_ids)) != len(
            self.option_ids
        ):
            _fail("option_ids_not_canonical")
        if type(self.bead_ids) is not tuple or not 1 <= len(self.bead_ids) <= 64:
            _fail("invalid_bead_ids")
        if any(_opaque(item, "bead_id") != item for item in self.bead_ids):
            _fail("invalid_bead_ids")
        if self.bead_ids != tuple(sorted(self.bead_ids)) or len(set(self.bead_ids)) != len(
            self.bead_ids
        ):
            _fail("bead_ids_not_canonical")
        _digest(self.package_fingerprint, "package_fingerprint")

    def to_json(self) -> dict[str, object]:
        return {
            "bead_ids": self.bead_ids,
            "decision_id": self.decision_id,
            "option_ids": self.option_ids,
            "package_fingerprint": self.package_fingerprint,
            "proposal_id": self.proposal_id,
            "requested_authority": self.requested_authority.value,
            "schema_version": self.schema_version,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> DecisionViewV1:
        value = _exact(
            data,
            (
                "bead_ids",
                "decision_id",
                "option_ids",
                "package_fingerprint",
                "proposal_id",
                "requested_authority",
                "schema_version",
            ),
            max_bytes=MAX_COMMAND_BYTES,
        )
        try:
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["proposal_id"]),
                cast(str, value["decision_id"]),
                RequestedAuthority(cast(str, value["requested_authority"])),
                tuple(
                    cast(str, item) for item in _seq(value["option_ids"], "option_ids", max_items=5)
                ),
                tuple(
                    cast(str, item) for item in _seq(value["bead_ids"], "bead_ids", max_items=64)
                ),
                cast(str, value["package_fingerprint"]),
            )
        except (TypeError, ValueError, ResolutionContractError, CapabilityGapCorruptionError):
            raise CapabilityGapCorruptionError("invalid_decision_view") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_decision_view")
        return result


@dataclass(frozen=True, slots=True)
class GrillReceiptV1:
    subject_kind: GrillSubjectKind
    subject_id: str
    receipt_id: str
    evidence_digest: str

    def __post_init__(self) -> None:
        if not isinstance(self.subject_kind, GrillSubjectKind):
            _fail("invalid_subject_kind")
        _opaque(self.subject_id, "subject_id")
        _opaque(self.receipt_id, "receipt_id")
        _digest(self.evidence_digest, "evidence_digest")

    def to_json(self) -> dict[str, object]:
        return {
            "evidence_digest": self.evidence_digest,
            "receipt_id": self.receipt_id,
            "subject_id": self.subject_id,
            "subject_kind": self.subject_kind.value,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> GrillReceiptV1:
        value = _exact(
            data,
            ("evidence_digest", "receipt_id", "subject_id", "subject_kind"),
            max_bytes=MAX_COMMAND_BYTES,
        )
        try:
            result = cls(
                GrillSubjectKind(cast(str, value["subject_kind"])),
                cast(str, value["subject_id"]),
                cast(str, value["receipt_id"]),
                cast(str, value["evidence_digest"]),
            )
        except (TypeError, ValueError, ResolutionContractError):
            raise CapabilityGapCorruptionError("invalid_grill_receipt") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_grill_receipt")
        return result


@dataclass(frozen=True, slots=True)
class ResolutionCommandV1:
    schema_version: int
    proposal_id: str
    decision_id: str
    outcome: ResolutionOutcome
    selected_option_id: str | None
    defer_reference: str | None
    duplicate_of_proposal_id: str | None
    grill_receipts: tuple[GrillReceiptV1, ...]

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.proposal_id, "proposal_id")
        _digest(self.decision_id, "decision_id")
        if not isinstance(self.outcome, ResolutionOutcome):
            _fail("invalid_outcome")
        if self.selected_option_id is not None:
            _opaque(self.selected_option_id, "selected_option_id")
        if self.defer_reference is not None:
            _opaque(self.defer_reference, "defer_reference")
        if self.duplicate_of_proposal_id is not None:
            _digest(self.duplicate_of_proposal_id, "duplicate_of_proposal_id")
        if type(self.grill_receipts) is not tuple or len(self.grill_receipts) > MAX_GRILL_RECEIPTS:
            _fail("invalid_grill_receipts")
        if any(not isinstance(item, GrillReceiptV1) for item in self.grill_receipts):
            _fail("invalid_grill_receipts")
        receipt_keys = tuple(
            (item.subject_kind.value, item.subject_id) for item in self.grill_receipts
        )
        if receipt_keys != tuple(sorted(receipt_keys)) or len(set(receipt_keys)) != len(
            receipt_keys
        ):
            _fail("grill_receipts_not_canonical")
        nonnull = sum(
            value is not None
            for value in (
                self.selected_option_id,
                self.defer_reference,
                self.duplicate_of_proposal_id,
            )
        )
        if self.outcome is ResolutionOutcome.REJECTED and (nonnull or self.grill_receipts):
            _fail("invalid_rejected_branch")
        if self.outcome is ResolutionOutcome.DEFERRED and (
            self.defer_reference is None or nonnull != 1 or self.grill_receipts
        ):
            _fail("invalid_deferred_branch")
        if self.outcome is ResolutionOutcome.DUPLICATE and (
            self.duplicate_of_proposal_id is None
            or self.duplicate_of_proposal_id == self.proposal_id
            or nonnull != 1
            or self.grill_receipts
        ):
            _fail("invalid_duplicate_branch")
        if self.outcome is ResolutionOutcome.ACCEPTED and (
            self.selected_option_id is None or nonnull != 1 or not self.grill_receipts
        ):
            _fail("invalid_accepted_branch")
        if self.outcome is not ResolutionOutcome.ACCEPTED and self.selected_option_id is not None:
            _fail("invalid_branch_payload")

    def to_json(self) -> dict[str, object]:
        return {
            "decision_id": self.decision_id,
            "defer_reference": self.defer_reference,
            "duplicate_of_proposal_id": self.duplicate_of_proposal_id,
            "grill_receipts": tuple(item.to_json() for item in self.grill_receipts),
            "outcome": self.outcome.value,
            "proposal_id": self.proposal_id,
            "schema_version": self.schema_version,
            "selected_option_id": self.selected_option_id,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_COMMAND_BYTES:
            _fail("oversized_command")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> ResolutionCommandV1:
        value = _exact(
            data,
            (
                "decision_id",
                "defer_reference",
                "duplicate_of_proposal_id",
                "grill_receipts",
                "outcome",
                "proposal_id",
                "schema_version",
                "selected_option_id",
            ),
            max_bytes=MAX_COMMAND_BYTES,
        )
        try:
            receipts: list[GrillReceiptV1] = []
            for raw in _seq(
                value["grill_receipts"], "grill_receipts", max_items=MAX_GRILL_RECEIPTS
            ):
                if not isinstance(raw, Mapping) or tuple(sorted(raw)) != (
                    "evidence_digest",
                    "receipt_id",
                    "subject_id",
                    "subject_kind",
                ):
                    raise CapabilityGapCorruptionError("invalid_grill_receipt_fields")
                receipts.append(
                    GrillReceiptV1(
                        GrillSubjectKind(cast(str, raw["subject_kind"])),
                        cast(str, raw["subject_id"]),
                        cast(str, raw["receipt_id"]),
                        cast(str, raw["evidence_digest"]),
                    )
                )
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["proposal_id"]),
                cast(str, value["decision_id"]),
                ResolutionOutcome(cast(str, value["outcome"])),
                cast(str | None, value["selected_option_id"]),
                cast(str | None, value["defer_reference"]),
                cast(str | None, value["duplicate_of_proposal_id"]),
                tuple(receipts),
            )
        except (TypeError, ValueError, ResolutionContractError, CapabilityGapCorruptionError):
            raise CapabilityGapCorruptionError("invalid_resolution_command") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_resolution_command")
        return result

    @property
    def authority_receipt_fingerprint(self) -> str:
        return _hash(_DOMAIN_AUTHORITY, self.to_json())


@dataclass(frozen=True, slots=True)
class ApprovedArtifactV1:
    kind: DraftArtifactKind
    artifact_id: str
    artifact_state: str
    body: str
    depends_on: tuple[str, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.kind, DraftArtifactKind) or self.artifact_state != "approved":
            _fail("invalid_approved_artifact")
        _opaque(self.artifact_id, "artifact_id")
        _text(self.body, "artifact_body", max_bytes=512 * 1024)
        if type(self.depends_on) is not tuple or len(self.depends_on) > 64:
            _fail("invalid_dependencies")
        if len(set(self.depends_on)) != len(self.depends_on):
            _fail("duplicate_dependency")
        for item in self.depends_on:
            _opaque(item, "dependency")
        if self.kind in (DraftArtifactKind.ADR, DraftArtifactKind.SPEC) and self.depends_on:
            _fail("adr_spec_dependencies_forbidden")

    def to_json(self) -> dict[str, object]:
        return {
            "artifact_id": self.artifact_id,
            "artifact_state": self.artifact_state,
            "body": self.body,
            "depends_on": self.depends_on,
            "kind": self.kind.value,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > 512 * 1024:
            _fail("oversized_approved_artifact")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> ApprovedArtifactV1:
        value = _exact(
            data,
            ("artifact_id", "artifact_state", "body", "depends_on", "kind"),
            max_bytes=512 * 1024,
        )
        try:
            result = cls(
                DraftArtifactKind(cast(str, value["kind"])),
                cast(str, value["artifact_id"]),
                cast(str, value["artifact_state"]),
                cast(str, value["body"]),
                tuple(
                    cast(str, item)
                    for item in _seq(value["depends_on"], "depends_on", max_items=64)
                ),
            )
        except (TypeError, ValueError, ResolutionContractError):
            raise CapabilityGapCorruptionError("invalid_approved_artifact") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_approved_artifact")
        return result


@dataclass(frozen=True, slots=True)
class ImplementationGoalV1:
    schema_version: int
    goal_id: str
    proposal_id: str
    spec_artifact_id: str
    bead_ids: tuple[str, ...]
    status: str

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.goal_id, "goal_id")
        _digest(self.proposal_id, "proposal_id")
        _opaque(self.spec_artifact_id, "spec_artifact_id")
        if (
            type(self.bead_ids) is not tuple
            or not self.bead_ids
            or len(self.bead_ids) > 64
            or self.bead_ids != tuple(sorted(self.bead_ids))
            or len(set(self.bead_ids)) != len(self.bead_ids)
        ):
            _fail("invalid_bead_ids")
        for item in self.bead_ids:
            _opaque(item, "bead_id")
        if self.status != "authorized_not_started":
            _fail("invalid_goal_status")
        if self.goal_id != self.derive_id(
            self.proposal_id, self.spec_artifact_id, self.bead_ids, self.status
        ):
            raise CapabilityGapCorruptionError("goal_id_mismatch")

    @staticmethod
    def derive_id(
        proposal_id: str, spec_artifact_id: str, bead_ids: tuple[str, ...], status: str
    ) -> str:
        return _hash(
            _DOMAIN_GOAL,
            {
                "bead_ids": bead_ids,
                "proposal_id": proposal_id,
                "schema_version": 1,
                "spec_artifact_id": spec_artifact_id,
                "status": status,
            },
        )

    def to_json(self) -> dict[str, object]:
        return {
            "bead_ids": self.bead_ids,
            "goal_id": self.goal_id,
            "proposal_id": self.proposal_id,
            "schema_version": self.schema_version,
            "spec_artifact_id": self.spec_artifact_id,
            "status": self.status,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> ImplementationGoalV1:
        value = _exact(
            data,
            ("bead_ids", "goal_id", "proposal_id", "schema_version", "spec_artifact_id", "status"),
            max_bytes=MAX_RESOLUTION_BYTES,
        )
        try:
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["goal_id"]),
                cast(str, value["proposal_id"]),
                cast(str, value["spec_artifact_id"]),
                tuple(
                    cast(str, item) for item in _seq(value["bead_ids"], "bead_ids", max_items=64)
                ),
                cast(str, value["status"]),
            )
        except (TypeError, ValueError, ResolutionContractError, CapabilityGapCorruptionError):
            raise CapabilityGapCorruptionError("invalid_implementation_goal") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_implementation_goal")
        return result


@dataclass(frozen=True, slots=True)
class GapResolutionV1:
    schema_version: int
    resolution_id: str
    proposal_id: str
    decision_id: str
    outcome: ResolutionOutcome
    selected_option_id: str | None
    defer_reference: str | None
    duplicate_of_proposal_id: str | None
    grill_receipts: tuple[GrillReceiptV1, ...]
    authority_receipt_fingerprint: str
    requested_authority: RequestedAuthority
    resolved_at: datetime

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.resolution_id, "resolution_id")
        if not isinstance(self.requested_authority, RequestedAuthority):
            _fail("invalid_requested_authority")
        _digest(self.authority_receipt_fingerprint, "authority_receipt_fingerprint")
        _timestamp(self.resolved_at)
        command = ResolutionCommandV1(
            1,
            self.proposal_id,
            self.decision_id,
            self.outcome,
            self.selected_option_id,
            self.defer_reference,
            self.duplicate_of_proposal_id,
            self.grill_receipts,
        )
        if self.authority_receipt_fingerprint != command.authority_receipt_fingerprint:
            raise CapabilityGapCorruptionError("authority_receipt_fingerprint_mismatch")
        if self.resolution_id != self.derive_id(
            self.proposal_id,
            self.decision_id,
            command,
            self.authority_receipt_fingerprint,
            self.requested_authority,
            self.resolved_at,
        ):
            raise CapabilityGapCorruptionError("resolution_id_mismatch")

    @staticmethod
    def derive_id(
        proposal_id: str,
        decision_id: str,
        command: ResolutionCommandV1,
        authority_receipt_fingerprint: str,
        requested_authority: RequestedAuthority,
        resolved_at: datetime,
    ) -> str:
        return _hash(
            _DOMAIN_RESOLUTION,
            {
                "authority_receipt_fingerprint": authority_receipt_fingerprint,
                "decision_id": decision_id,
                "defer_reference": command.defer_reference,
                "duplicate_of_proposal_id": command.duplicate_of_proposal_id,
                "grill_receipts": tuple(item.to_json() for item in command.grill_receipts),
                "outcome": command.outcome.value,
                "proposal_id": proposal_id,
                "requested_authority": requested_authority.value,
                "resolved_at": _timestamp_bytes(resolved_at),
                "schema_version": 1,
                "selected_option_id": command.selected_option_id,
            },
        )

    def to_json(self) -> dict[str, object]:
        return {
            "authority_receipt_fingerprint": self.authority_receipt_fingerprint,
            "decision_id": self.decision_id,
            "defer_reference": self.defer_reference,
            "duplicate_of_proposal_id": self.duplicate_of_proposal_id,
            "grill_receipts": tuple(item.to_json() for item in self.grill_receipts),
            "outcome": self.outcome.value,
            "proposal_id": self.proposal_id,
            "requested_authority": self.requested_authority.value,
            "resolution_id": self.resolution_id,
            "resolved_at": _timestamp_bytes(self.resolved_at),
            "schema_version": self.schema_version,
            "selected_option_id": self.selected_option_id,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_RESOLUTION_BYTES:
            _fail("oversized_resolution")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> GapResolutionV1:
        fields = (
            "authority_receipt_fingerprint",
            "decision_id",
            "defer_reference",
            "duplicate_of_proposal_id",
            "grill_receipts",
            "outcome",
            "proposal_id",
            "requested_authority",
            "resolution_id",
            "resolved_at",
            "schema_version",
            "selected_option_id",
        )
        value = _exact(data, fields, max_bytes=MAX_RESOLUTION_BYTES)
        try:
            receipts_list: list[GrillReceiptV1] = []
            for raw in _seq(
                value["grill_receipts"], "grill_receipts", max_items=MAX_GRILL_RECEIPTS
            ):
                if not isinstance(raw, Mapping) or tuple(sorted(raw)) != (
                    "evidence_digest",
                    "receipt_id",
                    "subject_id",
                    "subject_kind",
                ):
                    raise CapabilityGapCorruptionError("invalid_grill_receipt_fields")
                receipts_list.append(
                    GrillReceiptV1(
                        GrillSubjectKind(cast(str, raw["subject_kind"])),
                        cast(str, raw["subject_id"]),
                        cast(str, raw["receipt_id"]),
                        cast(str, raw["evidence_digest"]),
                    )
                )
            receipts = tuple(receipts_list)
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["resolution_id"]),
                cast(str, value["proposal_id"]),
                cast(str, value["decision_id"]),
                ResolutionOutcome(cast(str, value["outcome"])),
                cast(str | None, value["selected_option_id"]),
                cast(str | None, value["defer_reference"]),
                cast(str | None, value["duplicate_of_proposal_id"]),
                receipts,
                cast(str, value["authority_receipt_fingerprint"]),
                RequestedAuthority(cast(str, value["requested_authority"])),
                _parse_timestamp(value["resolved_at"]),
            )
        except (TypeError, ValueError, ResolutionContractError, CapabilityGapCorruptionError):
            raise CapabilityGapCorruptionError("invalid_resolution") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_resolution")
        return result


@dataclass(frozen=True, slots=True)
class FlywheelPromotionBundleV1:
    schema_version: int
    promotion_id: str
    resolution_id: str
    proposal_id: str
    decision_id: str
    candidate_gap_keys: tuple[str, ...]
    selected_option_id: str
    requested_authority: RequestedAuthority
    approved_artifacts: tuple[ApprovedArtifactV1, ...]
    grill_receipts: tuple[GrillReceiptV1, ...]
    materialization_plan: MaterializationPlanV1
    verification: tuple[str, ...]
    non_goals: tuple[str, ...]
    required_gates: tuple[str, ...] = (
        "worker_briefs",
        "tests",
        "semantic_review",
        "publication_authority",
    )
    exclusions: tuple[str, ...] = ("github_issue", "repository_merge", "release", "deployment")
    implementation_goal: ImplementationGoalV1 | None = None

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.promotion_id, "promotion_id")
        _digest(self.resolution_id, "resolution_id")
        _digest(self.proposal_id, "proposal_id")
        _digest(self.decision_id, "decision_id")
        _digest(self.selected_option_id, "selected_option_id") if _HEX64.fullmatch(
            self.selected_option_id
        ) else _opaque(self.selected_option_id, "selected_option_id")
        if (
            type(self.candidate_gap_keys) is not tuple
            or not 1 <= len(self.candidate_gap_keys) <= 16
            or self.candidate_gap_keys != tuple(sorted(self.candidate_gap_keys))
            or len(set(self.candidate_gap_keys)) != len(self.candidate_gap_keys)
        ):
            _fail("invalid_candidate_gap_keys")
        for key in self.candidate_gap_keys:
            _digest(key, "candidate_gap_key")
        if not isinstance(self.requested_authority, RequestedAuthority):
            _fail("invalid_requested_authority")
        if type(self.grill_receipts) is not tuple or len(self.grill_receipts) > MAX_GRILL_RECEIPTS:
            _fail("invalid_grill_receipts")
        if any(not isinstance(item, GrillReceiptV1) for item in self.grill_receipts):
            _fail("invalid_grill_receipts")
        receipt_keys = tuple(
            (item.subject_kind.value, item.subject_id) for item in self.grill_receipts
        )
        if receipt_keys != tuple(sorted(receipt_keys)) or len(set(receipt_keys)) != len(
            receipt_keys
        ):
            _fail("grill_receipts_not_canonical")
        if (
            type(self.approved_artifacts) is not tuple
            or len(self.approved_artifacts) < 3
            or len(self.approved_artifacts) > 66
            or any(not isinstance(item, ApprovedArtifactV1) for item in self.approved_artifacts)
        ):
            _fail("invalid_approved_artifacts")
        if (
            sum(item.kind is DraftArtifactKind.ADR for item in self.approved_artifacts) != 1
            or sum(item.kind is DraftArtifactKind.SPEC for item in self.approved_artifacts) != 1
            or sum(item.kind is DraftArtifactKind.BEAD for item in self.approved_artifacts) < 1
        ):
            _fail("invalid_artifact_kind_counts")
        order = {DraftArtifactKind.ADR: 0, DraftArtifactKind.SPEC: 1, DraftArtifactKind.BEAD: 2}
        keys = tuple((order[item.kind], item.artifact_id) for item in self.approved_artifacts)
        if keys != tuple(sorted(keys)) or len(
            {item.artifact_id for item in self.approved_artifacts}
        ) != len(self.approved_artifacts):
            _fail("approved_artifacts_not_canonical")
        if not isinstance(self.materialization_plan, MaterializationPlanV1):
            _fail("invalid_materialization_plan")
        if self.materialization_plan.run_id != f"gap06-{self.resolution_id[:24]}":
            _fail("materialization_run_mismatch")
        for values, field in ((self.verification, "verification"), (self.non_goals, "non_goals")):
            if type(values) is not tuple or not 1 <= len(values) <= 64:
                _fail(f"invalid_{field}")
            for item in values:
                _text(item, field)
        if self.required_gates != (
            "worker_briefs",
            "tests",
            "semantic_review",
            "publication_authority",
        ):
            _fail("invalid_required_gates")
        if self.exclusions != ("github_issue", "repository_merge", "release", "deployment"):
            _fail("invalid_exclusions")
        if (
            self.requested_authority is RequestedAuthority.PLANNING_ONLY
            and self.implementation_goal is not None
        ):
            _fail("unexpected_implementation_goal")
        if (
            self.requested_authority is RequestedAuthority.PLANNING_AND_IMPLEMENTATION_GOAL
            and not isinstance(self.implementation_goal, ImplementationGoalV1)
        ):
            _fail("missing_implementation_goal")
        _validate_promotion_plan_bindings(self)
        if self.promotion_id != self.derive_id(self._body()):
            raise CapabilityGapCorruptionError("promotion_id_mismatch")

    def _body(self) -> dict[str, object]:
        return {
            "approved_artifacts": tuple(item.to_json() for item in self.approved_artifacts),
            "candidate_gap_keys": self.candidate_gap_keys,
            "decision_id": self.decision_id,
            "exclusions": self.exclusions,
            "grill_receipts": tuple(item.to_json() for item in self.grill_receipts),
            "implementation_goal": None
            if self.implementation_goal is None
            else self.implementation_goal.to_json(),
            "materialization_plan": self.materialization_plan.to_json(),
            "non_goals": self.non_goals,
            "proposal_id": self.proposal_id,
            "required_gates": self.required_gates,
            "requested_authority": self.requested_authority.value,
            "resolution_id": self.resolution_id,
            "schema_version": 1,
            "selected_option_id": self.selected_option_id,
            "verification": self.verification,
        }

    def to_json(self) -> dict[str, object]:
        return {**self._body(), "promotion_id": self.promotion_id}

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_PROMOTION_BYTES:
            _fail("oversized_promotion")
        return data

    @classmethod
    def create(
        cls,
        schema_version: int,
        resolution_id: str,
        proposal_id: str,
        decision_id: str,
        candidate_gap_keys: tuple[str, ...],
        selected_option_id: str,
        requested_authority: RequestedAuthority,
        approved_artifacts: tuple[ApprovedArtifactV1, ...],
        grill_receipts: tuple[GrillReceiptV1, ...],
        materialization_plan: MaterializationPlanV1,
        verification: tuple[str, ...],
        non_goals: tuple[str, ...],
        required_gates: tuple[str, ...] = (
            "worker_briefs",
            "tests",
            "semantic_review",
            "publication_authority",
        ),
        exclusions: tuple[str, ...] = (
            "github_issue",
            "repository_merge",
            "release",
            "deployment",
        ),
        implementation_goal: ImplementationGoalV1 | None = None,
    ) -> FlywheelPromotionBundleV1:
        body = {
            "approved_artifacts": tuple(item.to_json() for item in approved_artifacts),
            "candidate_gap_keys": candidate_gap_keys,
            "decision_id": decision_id,
            "exclusions": exclusions,
            "grill_receipts": tuple(item.to_json() for item in grill_receipts),
            "implementation_goal": None
            if implementation_goal is None
            else implementation_goal.to_json(),
            "materialization_plan": materialization_plan.to_json(),
            "non_goals": non_goals,
            "proposal_id": proposal_id,
            "required_gates": required_gates,
            "requested_authority": requested_authority.value,
            "resolution_id": resolution_id,
            "schema_version": schema_version,
            "selected_option_id": selected_option_id,
            "verification": verification,
        }
        return cls(
            schema_version,
            cls.derive_id(body),
            resolution_id,
            proposal_id,
            decision_id,
            candidate_gap_keys,
            selected_option_id,
            requested_authority,
            approved_artifacts,
            grill_receipts,
            materialization_plan,
            verification,
            non_goals,
            required_gates,
            exclusions,
            implementation_goal,
        )

    @classmethod
    def from_bytes(cls, data: bytes) -> FlywheelPromotionBundleV1:
        fields = (
            "approved_artifacts",
            "candidate_gap_keys",
            "decision_id",
            "exclusions",
            "grill_receipts",
            "implementation_goal",
            "materialization_plan",
            "non_goals",
            "promotion_id",
            "proposal_id",
            "required_gates",
            "requested_authority",
            "resolution_id",
            "schema_version",
            "selected_option_id",
            "verification",
        )
        value = _exact(data, fields, max_bytes=MAX_PROMOTION_BYTES)
        try:
            artifacts: list[ApprovedArtifactV1] = []
            for raw in _seq(value["approved_artifacts"], "approved_artifacts", max_items=66):
                if not isinstance(raw, Mapping) or tuple(sorted(raw)) != (
                    "artifact_id",
                    "artifact_state",
                    "body",
                    "depends_on",
                    "kind",
                ):
                    raise CapabilityGapCorruptionError("invalid_approved_artifact_fields")
                artifacts.append(
                    ApprovedArtifactV1(
                        DraftArtifactKind(cast(str, raw["kind"])),
                        cast(str, raw["artifact_id"]),
                        cast(str, raw["artifact_state"]),
                        cast(str, raw["body"]),
                        tuple(
                            cast(str, item)
                            for item in _seq(raw["depends_on"], "depends_on", max_items=64)
                        ),
                    )
                )
            receipts: list[GrillReceiptV1] = []
            for raw in _seq(
                value["grill_receipts"], "grill_receipts", max_items=MAX_GRILL_RECEIPTS
            ):
                if not isinstance(raw, Mapping) or tuple(sorted(raw)) != (
                    "evidence_digest",
                    "receipt_id",
                    "subject_id",
                    "subject_kind",
                ):
                    raise CapabilityGapCorruptionError("invalid_grill_receipt_fields")
                receipts.append(
                    GrillReceiptV1(
                        GrillSubjectKind(cast(str, raw["subject_kind"])),
                        cast(str, raw["subject_id"]),
                        cast(str, raw["receipt_id"]),
                        cast(str, raw["evidence_digest"]),
                    )
                )
            plan_raw = value["materialization_plan"]
            if not isinstance(plan_raw, Mapping):
                raise CapabilityGapCorruptionError("invalid_materialization_plan")
            plan = MaterializationPlanV1.from_bytes(canonical_json_bytes(cast(Any, plan_raw)))
            goal_raw = value["implementation_goal"]
            goal = None
            if goal_raw is not None:
                if not isinstance(goal_raw, Mapping) or tuple(sorted(goal_raw)) != (
                    "bead_ids",
                    "goal_id",
                    "proposal_id",
                    "schema_version",
                    "spec_artifact_id",
                    "status",
                ):
                    raise CapabilityGapCorruptionError("invalid_implementation_goal")
                goal = ImplementationGoalV1(
                    cast(int, goal_raw["schema_version"]),
                    cast(str, goal_raw["goal_id"]),
                    cast(str, goal_raw["proposal_id"]),
                    cast(str, goal_raw["spec_artifact_id"]),
                    tuple(
                        cast(str, item)
                        for item in _seq(goal_raw["bead_ids"], "bead_ids", max_items=64)
                    ),
                    cast(str, goal_raw["status"]),
                )
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["promotion_id"]),
                cast(str, value["resolution_id"]),
                cast(str, value["proposal_id"]),
                cast(str, value["decision_id"]),
                tuple(
                    cast(str, item)
                    for item in _seq(
                        value["candidate_gap_keys"], "candidate_gap_keys", max_items=16
                    )
                ),
                cast(str, value["selected_option_id"]),
                RequestedAuthority(cast(str, value["requested_authority"])),
                tuple(artifacts),
                tuple(receipts),
                plan,
                tuple(
                    cast(str, item)
                    for item in _seq(value["verification"], "verification", max_items=64)
                ),
                tuple(
                    cast(str, item) for item in _seq(value["non_goals"], "non_goals", max_items=64)
                ),
                tuple(
                    cast(str, item)
                    for item in _seq(value["required_gates"], "required_gates", max_items=8)
                ),
                tuple(
                    cast(str, item) for item in _seq(value["exclusions"], "exclusions", max_items=8)
                ),
                goal,
            )
        except (TypeError, ValueError, ResolutionContractError, CapabilityGapCorruptionError):
            raise CapabilityGapCorruptionError("invalid_promotion") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_promotion")
        if result.promotion_id != cls.derive_id(result._body()):
            raise CapabilityGapCorruptionError("promotion_id_mismatch")
        return result

    @staticmethod
    def derive_id(body: Mapping[str, Any]) -> str:
        return _hash(_DOMAIN_PROMOTION, body)


@dataclass(frozen=True, slots=True)
class FlywheelPromotionReceiptV1:
    schema_version: int
    receipt_id: str
    promotion_id: str
    sink_id: str
    promotion_bundle_fingerprint: str
    run_id: str
    file_manifest_digest: str
    status: str

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _digest(self.receipt_id, "receipt_id")
        _digest(self.promotion_id, "promotion_id")
        _digest(self.sink_id, "sink_id")
        _digest(self.promotion_bundle_fingerprint, "promotion_bundle_fingerprint")
        _opaque(self.run_id, "run_id")
        _digest(self.file_manifest_digest, "file_manifest_digest")
        if self.status != "materialized":
            _fail("invalid_receipt_status")
        if self.receipt_id != self.derive_id(self._body()):
            raise CapabilityGapCorruptionError("receipt_id_mismatch")

    def _body(self) -> dict[str, object]:
        return {
            "file_manifest_digest": self.file_manifest_digest,
            "promotion_bundle_fingerprint": self.promotion_bundle_fingerprint,
            "promotion_id": self.promotion_id,
            "run_id": self.run_id,
            "schema_version": 1,
            "sink_id": self.sink_id,
            "status": self.status,
        }

    def to_json(self) -> dict[str, object]:
        return {**self._body(), "receipt_id": self.receipt_id}

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_RECEIPT_BYTES:
            _fail("oversized_receipt")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> FlywheelPromotionReceiptV1:
        fields = (
            "file_manifest_digest",
            "promotion_bundle_fingerprint",
            "promotion_id",
            "receipt_id",
            "run_id",
            "schema_version",
            "sink_id",
            "status",
        )
        value = _exact(data, fields, max_bytes=MAX_RECEIPT_BYTES)
        try:
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["receipt_id"]),
                cast(str, value["promotion_id"]),
                cast(str, value["sink_id"]),
                cast(str, value["promotion_bundle_fingerprint"]),
                cast(str, value["run_id"]),
                cast(str, value["file_manifest_digest"]),
                cast(str, value["status"]),
            )
        except (TypeError, ValueError, ResolutionContractError, CapabilityGapCorruptionError):
            raise CapabilityGapCorruptionError("invalid_receipt") from None
        if result.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_receipt")
        return result

    @classmethod
    def for_bundle(
        cls, bundle: FlywheelPromotionBundleV1, sink_id: str
    ) -> FlywheelPromotionReceiptV1:
        if not isinstance(bundle, FlywheelPromotionBundleV1):
            _fail("invalid_promotion_bundle")
        _digest(sink_id, "sink_id")
        # Reparse the exact bytes so callers cannot derive a receipt from a
        # structurally equivalent but noncanonical object.
        exact_bundle = FlywheelPromotionBundleV1.from_bytes(bundle.to_bytes())
        promotion_bytes = exact_bundle.to_bytes()
        promotion_fingerprint = sha256(_DOMAIN_PROMOTION_BYTES + promotion_bytes).hexdigest()
        entries = tuple(
            (item.relative_path, sha256(item.content).hexdigest())
            for item in exact_bundle.materialization_plan.files
        )
        manifest_digest = sha256(
            _DOMAIN_FILE_MANIFEST + canonical_json_bytes(cast(Any, entries))
        ).hexdigest()
        body = {
            "file_manifest_digest": manifest_digest,
            "promotion_bundle_fingerprint": promotion_fingerprint,
            "promotion_id": exact_bundle.promotion_id,
            "run_id": exact_bundle.materialization_plan.run_id,
            "schema_version": 1,
            "sink_id": sink_id,
            "status": "materialized",
        }
        return cls(
            1,
            cls.derive_id(body),
            cast(str, body["promotion_id"]),
            sink_id,
            promotion_fingerprint,
            cast(str, body["run_id"]),
            manifest_digest,
            "materialized",
        )

    @staticmethod
    def derive_id(body: Mapping[str, Any]) -> str:
        return sha256(_DOMAIN_RECEIPT + canonical_json_bytes(cast(Any, body))).hexdigest()


def _render_promotion_context(
    proposal_id: str,
    decision_id: str,
    evidence_fingerprint: str,
    selected_option_id: str,
    candidate_gap_keys: tuple[str, ...],
    candidates: object,
) -> str:
    """Render the deterministic, closed context document used by promotion plans."""
    lines = [
        "# Capability Gap Promotion Context",
        f"proposal_id: {proposal_id}",
        f"decision_id: {decision_id}",
        f"evidence_fingerprint: {evidence_fingerprint}",
        f"selected_option_id: {selected_option_id}",
        "cohort_gap_keys: " + ", ".join(candidate_gap_keys),
    ]
    for candidate in cast(tuple[object, ...], candidates):
        dimensions = canonical_json_bytes(
            cast(Any, cast(Any, candidate).dimensions.to_json())
        ).decode("utf-8")
        lines.append(f"dimension_summary: {cast(Any, candidate).gap_key} {dimensions}")
        lines.extend(
            f"active_work_ref: {item.kind.value}:{item.work_id}"
            for item in cast(Any, candidate).active_work
        )
        lines.extend(
            f"reproduction_summary: {item.reproduction.status.value}"
            for item in cast(Any, candidate).contributions
        )
    return "\n".join(lines) + "\n"


def _validate_context_document(data: bytes, bundle: FlywheelPromotionBundleV1) -> None:
    if type(data) is not bytes or not data.endswith(b"\n"):
        _fail("invalid_context")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        _fail("invalid_context")
    if any(
        (ord(char) < 32 or 0x7F <= ord(char) <= 0x9F) and char not in "\n"
        for char in text
    ):
        _fail("invalid_context")
    lines = text.splitlines()
    if not lines or lines[0] != "# Capability Gap Promotion Context" or any(
        not line for line in lines
    ):
        _fail("invalid_context")
    fixed_order = (
        "proposal_id",
        "decision_id",
        "evidence_fingerprint",
        "selected_option_id",
        "cohort_gap_keys",
    )
    if len(lines) < 6 or any(
        not lines[index].startswith(f"{key}: ") for index, key in enumerate(fixed_order, 1)
    ):
        _fail("invalid_context")
    fixed: dict[str, str] = {}
    dimensions: set[str] = set()
    for line in lines[1:]:
        if line.startswith("dimension_summary: "):
            payload = line[len("dimension_summary: ") :]
            try:
                gap_key, raw = payload.split(" ", 1)
                if not _HEX64.fullmatch(gap_key) or gap_key not in bundle.candidate_gap_keys:
                    raise ValueError
                parsed = canonical_json_object(raw.encode("utf-8"))
                if canonical_json_bytes(cast(Any, parsed)).decode("utf-8") != raw:
                    raise ValueError
            except (TypeError, ValueError, UnicodeDecodeError):
                _fail("invalid_context")
            if gap_key in dimensions:
                _fail("invalid_context")
            dimensions.add(gap_key)
            continue
        if line.startswith("active_work_ref: "):
            line_value: str = line[len("active_work_ref: ") :]
            try:
                kind, work_id = line_value.split(":", 1)
                ActiveWorkKind(kind)
            except (TypeError, ValueError):
                _fail("invalid_context")
            if _OPAQUE.fullmatch(work_id) is None:
                _fail("invalid_context")
            continue
        if line.startswith("reproduction_summary: "):
            line_value = line[len("reproduction_summary: ") :]
            try:
                ReproductionStatus(line_value)
            except ValueError:
                _fail("invalid_context")
            continue
        if ": " not in line:
            _fail("invalid_context")
        key, line_value = line.split(": ", 1)
        if key not in {
            "proposal_id",
            "decision_id",
            "evidence_fingerprint",
            "selected_option_id",
            "cohort_gap_keys",
        } or key in fixed or not line_value:
            _fail("invalid_context")
        fixed[key] = line_value
    if set(fixed) != {
        "proposal_id",
        "decision_id",
        "evidence_fingerprint",
        "selected_option_id",
        "cohort_gap_keys",
    }:
        _fail("invalid_context")
    if (
        fixed["proposal_id"] != bundle.proposal_id
        or fixed["decision_id"] != bundle.decision_id
        or fixed["selected_option_id"] != bundle.selected_option_id
        or fixed["cohort_gap_keys"].split(", ") != list(bundle.candidate_gap_keys)
        or _HEX64.fullmatch(fixed["evidence_fingerprint"]) is None
        or dimensions != set(bundle.candidate_gap_keys)
    ):
        _fail("invalid_context")


def _validate_promotion_plan_bindings(bundle: FlywheelPromotionBundleV1) -> None:
    """Check that the closed promotion body is exactly represented by its plan."""
    bead_ids = tuple(
        item.artifact_id
        for item in bundle.approved_artifacts
        if item.kind is DraftArtifactKind.BEAD
    )
    bead_set = set(bead_ids)
    graph = {
        item.artifact_id: item.depends_on
        for item in bundle.approved_artifacts
        if item.kind is DraftArtifactKind.BEAD
    }
    if any(dep not in bead_set for deps in graph.values() for dep in deps):
        _fail("invalid_dependency")
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(node: str) -> None:
        if node in visiting:
            _fail("dependency_cycle")
        if node in visited:
            return
        visiting.add(node)
        for dependency in graph[node]:
            visit(dependency)
        visiting.remove(node)
        visited.add(node)

    for node in graph:
        visit(node)
    expected_receipts = {
        (GrillSubjectKind.PROPOSAL.value, bundle.proposal_id),
        *((GrillSubjectKind.BEAD.value, item) for item in bead_ids),
    }
    actual_receipts = {(item.subject_kind.value, item.subject_id) for item in bundle.grill_receipts}
    if actual_receipts != expected_receipts or len(actual_receipts) != len(bundle.grill_receipts):
        _fail("invalid_grill_receipts")
    if bundle.implementation_goal is not None:
        spec = next(
            item for item in bundle.approved_artifacts if item.kind is DraftArtifactKind.SPEC
        )
        if (
            bundle.implementation_goal.proposal_id != bundle.proposal_id
            or bundle.implementation_goal.spec_artifact_id != spec.artifact_id
            or bundle.implementation_goal.bead_ids != tuple(sorted(bead_ids))
        ):
            _fail("goal_crosslink_mismatch")

    findings = validate_materialization_plan(bundle.materialization_plan)
    if any(item.severity == "error" for item in findings):
        _fail("invalid_materialization_plan")
    files = {item.relative_path: item.content for item in bundle.materialization_plan.files}
    try:
        manifest_bytes = files["manifest.json"]
        manifest = canonical_json_object(manifest_bytes)
    except (KeyError, TypeError, ValueError, UnicodeDecodeError):
        _fail("invalid_materialization_manifest")
    if canonical_json_bytes(cast(Any, manifest)) != manifest_bytes:
        _fail("invalid_materialization_manifest")
    refs = manifest.get("artifacts")
    if not isinstance(refs, Mapping):
        _fail("invalid_materialization_manifest")
    feature = manifest.get("feature")
    if (
        not isinstance(feature, Mapping)
        or feature.get("title") != f"Capability gap {bundle.proposal_id}"
        or manifest.get("source_ref")
        != "docs/specs/capability-gap-resolution-promotion.md"
    ):
        _fail("manifest_binding_mismatch")

    def role_ref(value: object, expected: str) -> str:
        if not isinstance(value, str):
            _fail("invalid_materialization_manifest")
        prefix = f"docs/flywheel-runs/{bundle.materialization_plan.run_id}/"
        alias = value[len(prefix) :] if value.startswith(prefix) else value
        if alias != expected or alias not in files:
            _fail("materialization_role_binding_mismatch")
        return alias

    spec = next(item for item in bundle.approved_artifacts if item.kind is DraftArtifactKind.SPEC)
    role_ref(refs.get("context"), "context/context.md")
    _validate_context_document(files["context/context.md"], bundle)
    spec_path = role_ref(refs.get("spec"), "spec/feature-spec.md")
    if files[spec_path] != spec.body.encode("utf-8"):
        _fail("materialization_spec_mismatch")
    adrs = tuple(
        item for item in bundle.approved_artifacts if item.kind is DraftArtifactKind.ADR
    )
    bead_items = tuple(
        item for item in bundle.approved_artifacts if item.kind is DraftArtifactKind.BEAD
    )
    decision_refs = refs.get("decisions")
    task_refs = refs.get("task_beads")
    if not isinstance(decision_refs, (list, tuple)) or not isinstance(task_refs, (list, tuple)):
        _fail("materialization_manifest_artifacts_mismatch")
    if len(decision_refs) != len(adrs) or len(task_refs) != len(bead_items):
        _fail("materialization_manifest_artifacts_mismatch")
    for artifact, ref in zip(adrs, decision_refs, strict=True):
        path = role_ref(ref, f"decisions/{artifact.artifact_id}.md")
        if files[path] != artifact.body.encode("utf-8"):
            _fail("materialization_artifact_mismatch")
    for artifact, ref in zip(bead_items, task_refs, strict=True):
        path = role_ref(ref, f"tasks/{artifact.artifact_id}.md")
        if files[path] != artifact.body.encode("utf-8"):
            _fail("materialization_artifact_mismatch")
    goal_ref = refs.get("implementation_goal")
    if bundle.implementation_goal is None:
        if goal_ref is not None:
            _fail("goal_crosslink_mismatch")
    else:
        goal_path = role_ref(goal_ref, "implementation-goal.json")
        if files[goal_path] != bundle.implementation_goal.to_bytes():
            _fail("materialization_goal_mismatch")


def _package_fingerprint(package_bytes: bytes) -> str:
    return sha256(_DOMAIN_PACKAGE + package_bytes).hexdigest()


def decision_view_for_package(package: ProposalDecisionPackageV1) -> DecisionViewV1:
    if not isinstance(package, ProposalDecisionPackageV1):
        raise CapabilityGapValidationError("invalid_package")
    return DecisionViewV1(
        1,
        package.proposal.proposal_id,
        package.decision.decision_id,
        package.proposal.draft.requested_authority,
        tuple(sorted(item.option_id for item in package.proposal.draft.options)),
        tuple(
            sorted(
                item.artifact_id
                for item in package.proposal.draft.artifacts
                if item.kind is DraftArtifactKind.BEAD
            )
        ),
        _package_fingerprint(package.to_bytes()),
    )


__all__ = [
    "MAX_COMMAND_BYTES",
    "MAX_PROMOTION_BYTES",
    "MAX_RECEIPT_BYTES",
    "MAX_RESOLUTION_BYTES",
    "ApprovedArtifactV1",
    "DecisionViewV1",
    "FlywheelPromotionBundleV1",
    "GapResolutionV1",
    "GrillReceiptV1",
    "GrillSubjectKind",
    "ImplementationGoalV1",
    "MaintainerResolutionAuthority",
    "ProposalPackageSource",
    "ResolutionClock",
    "ResolutionCommandV1",
    "ResolutionContractError",
    "ResolutionOutcome",
    "decision_view_for_package",
]
