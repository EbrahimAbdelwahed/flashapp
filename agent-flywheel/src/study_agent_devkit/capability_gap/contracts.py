"""Closed contracts for the private capability-gap intake boundary.

The public harness owns the outbox codec.  These types only describe trusted
import context and immutable, redacted evidence exposed after persistence.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from hashlib import sha256
from typing import Any, Protocol, cast, runtime_checkable

from study_agent.feedback.outbox import GapOutboxDimensions, GapOutboxRecord
from study_agent.state import canonical_json_bytes, canonical_json_object

_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_OPAQUE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$")


class CapabilityGapImportError(RuntimeError):
    """The imported evidence could not be accepted atomically."""


class CapabilityGapValidationError(ValueError):
    """A caller supplied a value outside the closed devkit contract."""


class CapabilityGapCollisionError(CapabilityGapImportError):
    """An idempotency or candidate identity claim conflicts with stored data."""


class CapabilityGapCorruptionError(CapabilityGapImportError):
    """Stored or imported bytes are not the canonical contract."""


class CapabilityGapUnavailableError(CapabilityGapImportError):
    """The requested candidate is not available."""


def _digest(value: object, field: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        raise CapabilityGapValidationError(f"invalid_{field}")
    return value


def _opaque(value: object, field: str) -> str:
    if not isinstance(value, str) or _OPAQUE.fullmatch(value) is None:
        raise CapabilityGapValidationError(f"invalid_{field}")
    return value


def _exact_object(data: bytes, fields: tuple[str, ...]) -> Mapping[str, object]:
    if not isinstance(data, bytes):
        raise CapabilityGapCorruptionError("invalid_payload")
    try:
        value = canonical_json_object(data)
    except (TypeError, ValueError, UnicodeDecodeError):
        raise CapabilityGapCorruptionError("invalid_payload") from None
    if tuple(sorted(value)) != tuple(sorted(fields)):
        raise CapabilityGapCorruptionError("invalid_payload")
    if canonical_json_bytes(cast(Any, value)) != data:
        raise CapabilityGapCorruptionError("noncanonical_payload")
    return value


@dataclass(frozen=True, slots=True)
class DeliveryImportContext:
    """Host-authenticated idempotency context; never persisted as evidence."""

    delivery_import_id: str
    bundle_fingerprint: str

    def __post_init__(self) -> None:
        _digest(self.delivery_import_id, "delivery_import_id")
        _digest(self.bundle_fingerprint, "bundle_fingerprint")

    @classmethod
    def for_local_bundle(cls, bundle_fingerprint: str) -> DeliveryImportContext:
        _digest(bundle_fingerprint, "bundle_fingerprint")
        preimage = (
            b"study-agent-devkit-local-delivery-v1\0"
            + b"local-file\0"
            + bundle_fingerprint.encode("ascii")
        )
        return cls(sha256(preimage).hexdigest(), bundle_fingerprint)

@dataclass(frozen=True, slots=True)
class ImportReceiptV1:
    """The only durable response to an import, intentionally identity-free."""

    bundle_fingerprint: str
    candidate_gap_keys: tuple[str, ...]
    schema_version: int = 1

    def __post_init__(self) -> None:
        if type(self.schema_version) is not int or self.schema_version != 1:
            raise CapabilityGapValidationError("invalid_receipt_schema_version")
        _digest(self.bundle_fingerprint, "bundle_fingerprint")
        if not isinstance(self.candidate_gap_keys, tuple):
            raise CapabilityGapValidationError("candidate_gap_keys_must_be_tuple")
        if any(_HEX64.fullmatch(key) is None for key in self.candidate_gap_keys):
            raise CapabilityGapValidationError("invalid_candidate_gap_key")
        if self.candidate_gap_keys != tuple(sorted(self.candidate_gap_keys)):
            raise CapabilityGapValidationError("candidate_gap_keys_not_canonical")
        if len(set(self.candidate_gap_keys)) != len(self.candidate_gap_keys):
            raise CapabilityGapValidationError("candidate_gap_keys_not_unique")

    def to_json(self) -> dict[str, object]:
        return {
            "bundle_fingerprint": self.bundle_fingerprint,
            "candidate_gap_keys": self.candidate_gap_keys,
            "schema_version": self.schema_version,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> ImportReceiptV1:
        value = _exact_object(
            data, ("schema_version", "bundle_fingerprint", "candidate_gap_keys")
        )
        keys = value["candidate_gap_keys"]
        if not isinstance(keys, list | tuple):
            raise CapabilityGapCorruptionError("invalid_receipt")
        try:
            receipt = cls(
                bundle_fingerprint=cast(str, value["bundle_fingerprint"]),
                candidate_gap_keys=tuple(cast(str, key) for key in keys),
                schema_version=cast(int, value["schema_version"]),
            )
        except (TypeError, ValueError, CapabilityGapValidationError):
            raise CapabilityGapCorruptionError("invalid_receipt") from None
        if receipt.to_bytes() != data:
            raise CapabilityGapCorruptionError("noncanonical_receipt")
        return receipt


class ReproductionStatus(StrEnum):
    REPRODUCED = "reproduced"
    NOT_REPRODUCED = "not_reproduced"
    NOT_REPRODUCIBLE_FROM_EXPORT = "not_reproducible_from_export"


class ActiveWorkKind(StrEnum):
    SPEC = "spec"
    BEAD = "bead"


@dataclass(frozen=True, slots=True)
class ActiveWorkSnapshot:
    """An informational exact link to already visible private work."""

    gap_key: str
    kind: ActiveWorkKind
    work_id: str

    def __post_init__(self) -> None:
        _digest(self.gap_key, "gap_key")
        if not isinstance(self.kind, ActiveWorkKind):
            raise CapabilityGapValidationError("invalid_active_work_kind")
        _opaque(self.work_id, "work_id")


@runtime_checkable
class ActiveWorkIndex(Protocol):
    """Trusted host snapshot source; implementations must be read-only."""

    def matches(
        self, gap_key: str, dimensions: GapOutboxDimensions
    ) -> Iterable[ActiveWorkSnapshot]: ...


@dataclass(frozen=True, slots=True)
class ReproductionResult:
    status: ReproductionStatus
    evidence_digest: str

    def __post_init__(self) -> None:
        if self.status is ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT:
            raise CapabilityGapValidationError("missing_fixture_result")
        if not isinstance(self.status, ReproductionStatus):
            raise CapabilityGapValidationError("invalid_reproduction_status")
        _digest(self.evidence_digest, "evidence_digest")


@dataclass(frozen=True, slots=True)
class ReproductionEvidence:
    status: ReproductionStatus
    fixture_id: str | None
    evidence_digest: str | None

    def __post_init__(self) -> None:
        if not isinstance(self.status, ReproductionStatus):
            raise CapabilityGapValidationError("invalid_reproduction_status")
        if self.status is ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT:
            if self.fixture_id is not None or self.evidence_digest is not None:
                raise CapabilityGapValidationError("invalid_missing_fixture_evidence")
        else:
            if self.fixture_id is None:
                raise CapabilityGapValidationError("missing_fixture_id")
            _opaque(self.fixture_id, "fixture_id")
            if self.evidence_digest is None:
                raise CapabilityGapValidationError("missing_evidence_digest")
            _digest(self.evidence_digest, "evidence_digest")


@dataclass(frozen=True, slots=True)
class ContributionSnapshot:
    """One complete redacted record and its reproduction outcome."""

    gap_key: str
    dimensions: GapOutboxDimensions
    record_bytes: bytes
    reproduction: ReproductionEvidence

    def __post_init__(self) -> None:
        _digest(self.gap_key, "gap_key")
        if not isinstance(self.dimensions, GapOutboxDimensions):
            raise CapabilityGapValidationError("invalid_dimensions")
        if not isinstance(self.record_bytes, bytes):
            raise CapabilityGapValidationError("invalid_record_bytes")
        if not isinstance(self.reproduction, ReproductionEvidence):
            raise CapabilityGapValidationError("invalid_reproduction")
        try:
            record = GapOutboxRecord.from_bytes(self.record_bytes)
        except Exception as error:
            raise CapabilityGapCorruptionError("invalid_record_bytes") from error
        if record.gap_key.value != self.gap_key or record.dimensions != self.dimensions:
            raise CapabilityGapCorruptionError("record_dimensions_mismatch")


@dataclass(frozen=True, slots=True)
class CandidateSnapshot:
    """Immutable aggregate view with no delivery identity."""

    gap_key: str
    dimensions: GapOutboxDimensions
    contributions: tuple[ContributionSnapshot, ...]
    occurrence_count: int
    first_seen: datetime
    last_seen: datetime
    active_work: tuple[ActiveWorkSnapshot, ...]

    def __post_init__(self) -> None:
        _digest(self.gap_key, "gap_key")
        if not isinstance(self.dimensions, GapOutboxDimensions):
            raise CapabilityGapValidationError("invalid_dimensions")
        if not isinstance(self.contributions, tuple) or not self.contributions:
            raise CapabilityGapValidationError("invalid_contributions")
        if any(
            not isinstance(item, ContributionSnapshot)
            or item.gap_key != self.gap_key
            or item.dimensions != self.dimensions
            for item in self.contributions
        ):
            raise CapabilityGapValidationError("contribution_dimensions_mismatch")
        occurrence_count = 0
        first_seen: datetime | None = None
        last_seen: datetime | None = None
        for item in self.contributions:
            try:
                record = GapOutboxRecord.from_bytes(item.record_bytes)
            except Exception as error:
                raise CapabilityGapCorruptionError("invalid_contribution_record") from error
            occurrence_count += record.occurrence_count
            first_seen = (
                record.first_seen if first_seen is None else min(first_seen, record.first_seen)
            )
            last_seen = (
                record.last_seen if last_seen is None else max(last_seen, record.last_seen)
            )
        if type(self.occurrence_count) is not int or self.occurrence_count != occurrence_count:
            raise CapabilityGapCorruptionError("occurrence_count_mismatch")
        if not isinstance(self.first_seen, datetime) or self.first_seen != first_seen:
            raise CapabilityGapCorruptionError("first_seen_mismatch")
        if not isinstance(self.last_seen, datetime) or self.last_seen != last_seen:
            raise CapabilityGapCorruptionError("last_seen_mismatch")
        if not isinstance(self.active_work, tuple):
            raise CapabilityGapValidationError("invalid_active_work")
        if any(
            not isinstance(item, ActiveWorkSnapshot) or item.gap_key != self.gap_key
            for item in self.active_work
        ):
            raise CapabilityGapValidationError("active_work_key_mismatch")
        active_work_key = tuple((item.kind.value, item.work_id) for item in self.active_work)
        if active_work_key != tuple(sorted(active_work_key)):
            raise CapabilityGapValidationError("active_work_not_canonical")
        if len(set(active_work_key)) != len(active_work_key):
            raise CapabilityGapValidationError("active_work_not_unique")


ReproductionCallback = Callable[[GapOutboxRecord], ReproductionResult]


class ReproductionRegistry:
    """Allowlist of trusted offline fixture callbacks.

    Callbacks are trusted host code and are not a process sandbox.  They only
    receive the parsed redacted outbox record; the registry supplies fixture
    identity and stores no source path, command, or delivery context.
    """

    def __init__(self) -> None:
        self._handlers: dict[bytes, tuple[str, ReproductionCallback]] = {}

    def register(
        self,
        fixture_id: str,
        dimensions: GapOutboxDimensions,
        callback: ReproductionCallback,
    ) -> None:
        _opaque(fixture_id, "fixture_id")
        if not isinstance(dimensions, GapOutboxDimensions):
            raise CapabilityGapValidationError("invalid_dimensions")
        if not callable(callback):
            raise CapabilityGapValidationError("invalid_reproduction_callback")
        key = dimensions.to_bytes()
        if key in self._handlers:
            raise CapabilityGapCollisionError("fixture_dimensions_collision")
        self._handlers[key] = (fixture_id, callback)

    def evaluate(self, record: GapOutboxRecord) -> ReproductionEvidence:
        if not isinstance(record, GapOutboxRecord):
            raise CapabilityGapValidationError("invalid_record")
        registered = self._handlers.get(record.dimensions.to_bytes())
        if registered is None:
            return ReproductionEvidence(
                ReproductionStatus.NOT_REPRODUCIBLE_FROM_EXPORT, None, None
            )
        fixture_id, callback = registered
        result = callback(record)
        if not isinstance(result, ReproductionResult):
            raise CapabilityGapValidationError("invalid_reproduction_result")
        return ReproductionEvidence(result.status, fixture_id, result.evidence_digest)


class InMemoryActiveWorkIndex:
    """Small deterministic index useful for local tests and factory runs."""

    def __init__(self, entries: Iterable[ActiveWorkSnapshot] = ()) -> None:
        self._entries = tuple(entries)

    def matches(
        self, gap_key: str, dimensions: GapOutboxDimensions
    ) -> tuple[ActiveWorkSnapshot, ...]:
        del dimensions
        return tuple(entry for entry in self._entries if entry.gap_key == gap_key)


__all__ = [
    "ActiveWorkIndex",
    "ActiveWorkKind",
    "ActiveWorkSnapshot",
    "CandidateSnapshot",
    "CapabilityGapCollisionError",
    "CapabilityGapCorruptionError",
    "CapabilityGapImportError",
    "CapabilityGapUnavailableError",
    "CapabilityGapValidationError",
    "ContributionSnapshot",
    "DeliveryImportContext",
    "ImportReceiptV1",
    "InMemoryActiveWorkIndex",
    "ReproductionCallback",
    "ReproductionEvidence",
    "ReproductionRegistry",
    "ReproductionResult",
    "ReproductionStatus",
]
