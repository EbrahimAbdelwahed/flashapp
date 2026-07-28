"""Closed contracts for accepted-only GitHub draft pull-request publication.

This module deliberately contains no transport or persistence code.  Values are
immutable, canonical JSON contracts so a host can inspect and authorize a
publication without granting the caller any authority over the source bundle.
"""

from __future__ import annotations

import base64
import re
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from hashlib import sha256
from typing import Any, NoReturn, Protocol, cast, runtime_checkable

from study_agent.state import canonical_json_bytes, canonical_json_object

from study_agent_devkit.flywheel.materialization import MaterializationPlanV1

from .resolution_contracts import FlywheelPromotionBundleV1

_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_HEX24 = re.compile(r"^[0-9a-f]{24}$")
_GIT_OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
_OPAQUE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,127}$")
_REF = re.compile(r"^[A-Za-z0-9._/-]{1,255}$")
_MAX_REQUEST_BYTES = 8 * 1024 * 1024
_MAX_RECEIPT_BYTES = 64 * 1024
_MAX_AUTH_BYTES = 64 * 1024
_DOMAIN_PROMOTION_BYTES = b"study-agent-devkit-gap06-promotion-bytes-v1\0"
_DOMAIN_PLAN = b"study-agent-devkit-gap08-plan-v1\0"
_DOMAIN_REQUEST = b"study-agent-devkit-gap08-request-v1\0"
_DOMAIN_RECEIPT = b"study-agent-devkit-gap08-receipt-v1\0"
_DOMAIN_AUTH = b"study-agent-devkit-gap08-authorization-v1\0"


class GitHubPublicationError(RuntimeError):
    """Base class for publication failures."""


class GitHubPublicationValidationError(ValueError, GitHubPublicationError):
    """An input is outside the closed publication contract."""


class GitHubPublicationCorruptionError(GitHubPublicationError):
    """Persisted or remote data is not a canonical contract."""


class GitHubPublicationCollisionError(GitHubPublicationError):
    """A publication identity is already claimed by different content."""


class GitHubPublicationUnavailableError(GitHubPublicationError):
    """The requested promotion is unknown or not accepted."""


class GitHubPublicationTamperError(GitHubPublicationError):
    """Remote state differs from the exact deterministic publication."""


class GitHubPublicationRetryableError(GitHubPublicationError):
    """The host may retry after a transient remote failure."""

    def __init__(
        self,
        message: str = "github_retryable",
        *,
        status: int | None = None,
        retry_after: int | None = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.retry_after = retry_after


class GitHubPublicationPermissionError(GitHubPublicationError):
    """Authentication or permission was rejected by GitHub."""


class GitHubPublicationAuthenticationError(GitHubPublicationPermissionError):
    """Credential authentication failed."""


def _fail(message: str) -> NoReturn:
    raise GitHubPublicationValidationError(message)


def _digest(value: object, field: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return value


def _oid(value: object, field: str) -> str:
    """Validate a Git object id without weakening 64-hex fingerprints."""
    if not isinstance(value, str) or _GIT_OID.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return value


def _opaque(value: object, field: str) -> str:
    if not isinstance(value, str) or _OPAQUE.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return value


def _text(value: object, field: str, max_bytes: int = 64 * 1024) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > max_bytes:
        _fail(f"invalid_{field}")
    return value


def _ref(value: object, field: str) -> str:
    if (
        not isinstance(value, str)
        or _REF.fullmatch(value) is None
        or value.startswith("/")
        or "//" in value
        or any(part == ".." for part in value.split("/"))
    ):
        _fail(f"invalid_{field}")
    return value


def _exact(data: bytes, fields: tuple[str, ...], limit: int) -> Mapping[str, object]:
    if type(data) is not bytes or len(data) > limit:
        raise GitHubPublicationCorruptionError("invalid_payload")
    try:
        value = canonical_json_object(data)
    except (TypeError, ValueError, UnicodeDecodeError):
        raise GitHubPublicationCorruptionError("invalid_payload") from None
    if tuple(sorted(value)) != tuple(sorted(fields)):
        raise GitHubPublicationCorruptionError("invalid_payload")
    if canonical_json_bytes(cast(Any, value)) != data:
        raise GitHubPublicationCorruptionError("noncanonical_payload")
    return value


def _b64(value: bytes) -> str:
    encoded = base64.b64encode(value).decode("ascii")
    # GitHub's blob API accepts standard base64 without line wrapping.
    return encoded


def _decode_b64(value: object) -> bytes:
    if not isinstance(value, str) or len(value) > 8 * 1024 * 1024:
        _fail("invalid_content_b64")
    try:
        decoded = base64.b64decode(value.encode("ascii"), validate=True)
    except (UnicodeEncodeError, ValueError):
        _fail("invalid_content_b64")
    if _b64(decoded) != value:
        _fail("noncanonical_content_b64")
    return decoded


def promotion_fingerprint(bundle: FlywheelPromotionBundleV1) -> str:
    exact = FlywheelPromotionBundleV1.from_bytes(bundle.to_bytes())
    return sha256(_DOMAIN_PROMOTION_BYTES + exact.to_bytes()).hexdigest()


def plan_fingerprint(plan: MaterializationPlanV1) -> str:
    exact = MaterializationPlanV1.from_bytes(plan.to_bytes())
    return sha256(_DOMAIN_PLAN + exact.to_bytes()).hexdigest()


def _marker(promotion_id: str, request_fingerprint: str) -> str:
    return (
        "<!-- study-agent-devkit:capability-gap:v1 "
        f"promotion_id={promotion_id} request_fingerprint={request_fingerprint} -->"
    )


@dataclass(frozen=True, slots=True)
class AcceptedPromotionViewV1:
    """Canonical source view supplied to the host publication authority."""

    promotion: FlywheelPromotionBundleV1
    owner: str
    repository: str
    base_ref: str
    sink_id: str

    def __post_init__(self) -> None:
        if not isinstance(self.promotion, FlywheelPromotionBundleV1):
            _fail("invalid_promotion")
        try:
            exact = FlywheelPromotionBundleV1.from_bytes(self.promotion.to_bytes())
        except Exception as error:
            raise GitHubPublicationCorruptionError("invalid_promotion") from error
        if exact != self.promotion:
            raise GitHubPublicationCorruptionError("noncanonical_promotion")
        _opaque(self.owner, "owner")
        _opaque(self.repository, "repository")
        if "/" in self.owner or "/" in self.repository:
            _fail("invalid_github_target")
        _ref(self.base_ref, "base_ref")
        _digest(self.sink_id, "sink_id")

    @property
    def promotion_id(self) -> str:
        return self.promotion.promotion_id

    @property
    def promotion_bundle_fingerprint(self) -> str:
        return promotion_fingerprint(self.promotion)

    @property
    def materialization_plan_fingerprint(self) -> str:
        return plan_fingerprint(self.promotion.materialization_plan)


@dataclass(frozen=True, slots=True)
class GitHubPublicationAuthorizationV1:
    schema_version: int
    authorization_id: str
    promotion_id: str
    resolution_id: str
    proposal_id: str
    decision_id: str
    promotion_bundle_fingerprint: str
    materialization_plan_fingerprint: str
    owner: str
    repository: str
    base_ref: str
    operation: str
    authorization_fingerprint: str

    def __post_init__(self) -> None:
        if type(self.schema_version) is not int or self.schema_version != 1:
            _fail("invalid_authorization_schema_version")
        for value, name in (
            (self.authorization_id, "authorization_id"),
            (self.promotion_id, "promotion_id"),
            (self.resolution_id, "resolution_id"),
            (self.proposal_id, "proposal_id"),
            (self.decision_id, "decision_id"),
            (self.promotion_bundle_fingerprint, "promotion_bundle_fingerprint"),
            (self.materialization_plan_fingerprint, "materialization_plan_fingerprint"),
            (self.authorization_fingerprint, "authorization_fingerprint"),
        ):
            _digest(value, name)
        _opaque(self.owner, "owner")
        _opaque(self.repository, "repository")
        if "/" in self.owner or "/" in self.repository:
            _fail("invalid_github_target")
        _ref(self.base_ref, "base_ref")
        if self.operation != "create_branch_and_draft_pr":
            _fail("invalid_authorization_operation")
        if self.authorization_fingerprint != self.derive_fingerprint(self._body()):
            raise GitHubPublicationCorruptionError("authorization_fingerprint_mismatch")

    def _body(self) -> dict[str, object]:
        return {
            "base_ref": self.base_ref,
            "decision_id": self.decision_id,
            "materialization_plan_fingerprint": self.materialization_plan_fingerprint,
            "operation": self.operation,
            "owner": self.owner,
            "promotion_bundle_fingerprint": self.promotion_bundle_fingerprint,
            "promotion_id": self.promotion_id,
            "proposal_id": self.proposal_id,
            "repository": self.repository,
            "resolution_id": self.resolution_id,
            "schema_version": 1,
        }

    def to_json(self) -> dict[str, object]:
        return {
            **self._body(),
            "authorization_fingerprint": self.authorization_fingerprint,
            "authorization_id": self.authorization_id,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > _MAX_AUTH_BYTES:
            _fail("oversized_authorization")
        return data

    @staticmethod
    def derive_fingerprint(body: Mapping[str, object]) -> str:
        return sha256(_DOMAIN_AUTH + canonical_json_bytes(cast(Any, body))).hexdigest()

    @classmethod
    def from_bytes(cls, data: bytes) -> GitHubPublicationAuthorizationV1:
        fields = (
            "authorization_fingerprint",
            "authorization_id",
            "base_ref",
            "decision_id",
            "materialization_plan_fingerprint",
            "operation",
            "owner",
            "promotion_bundle_fingerprint",
            "promotion_id",
            "proposal_id",
            "repository",
            "resolution_id",
            "schema_version",
        )
        value = _exact(data, fields, _MAX_AUTH_BYTES)
        try:
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["authorization_id"]),
                cast(str, value["promotion_id"]),
                cast(str, value["resolution_id"]),
                cast(str, value["proposal_id"]),
                cast(str, value["decision_id"]),
                cast(str, value["promotion_bundle_fingerprint"]),
                cast(str, value["materialization_plan_fingerprint"]),
                cast(str, value["owner"]),
                cast(str, value["repository"]),
                cast(str, value["base_ref"]),
                cast(str, value["operation"]),
                cast(str, value["authorization_fingerprint"]),
            )
        except (
            TypeError,
            ValueError,
            GitHubPublicationValidationError,
            GitHubPublicationCorruptionError,
        ):
            raise GitHubPublicationCorruptionError("invalid_authorization") from None
        if result.to_bytes() != data:
            raise GitHubPublicationCorruptionError("noncanonical_authorization")
        return result

    @classmethod
    def create(
        cls,
        view: AcceptedPromotionViewV1,
        *,
        authorization_id: str,
    ) -> GitHubPublicationAuthorizationV1:
        """Build the canonical host-issued authorization for one source view."""
        if not isinstance(view, AcceptedPromotionViewV1):
            _fail("invalid_authorization_view")
        body = {
            "base_ref": view.base_ref,
            "decision_id": view.promotion.decision_id,
            "materialization_plan_fingerprint": view.materialization_plan_fingerprint,
            "operation": "create_branch_and_draft_pr",
            "owner": view.owner,
            "promotion_bundle_fingerprint": view.promotion_bundle_fingerprint,
            "promotion_id": view.promotion_id,
            "proposal_id": view.promotion.proposal_id,
            "repository": view.repository,
            "resolution_id": view.promotion.resolution_id,
            "schema_version": 1,
        }
        _digest(authorization_id, "authorization_id")
        return cls(
            1,
            authorization_id,
            cast(str, body["promotion_id"]),
            cast(str, body["resolution_id"]),
            cast(str, body["proposal_id"]),
            cast(str, body["decision_id"]),
            cast(str, body["promotion_bundle_fingerprint"]),
            cast(str, body["materialization_plan_fingerprint"]),
            cast(str, body["owner"]),
            cast(str, body["repository"]),
            cast(str, body["base_ref"]),
            "create_branch_and_draft_pr",
            cls.derive_fingerprint(body),
        )


@runtime_checkable
class AcceptedPromotionSource(Protocol):
    """Read-only accepted bundle source.  Implementations must not mutate."""

    def get_by_promotion_id(self, promotion_id: str) -> object: ...


@runtime_checkable
class GitHubPublicationAuthority(Protocol):
    def authorize(
        self, view: AcceptedPromotionViewV1
    ) -> GitHubPublicationAuthorizationV1 | None: ...


@dataclass(frozen=True, slots=True)
class GitHubPublicationFileV1:
    repository_path: str
    content_b64: str

    def __post_init__(self) -> None:
        prefix = "docs/flywheel-runs/"
        if not isinstance(self.repository_path, str) or not self.repository_path.startswith(prefix):
            _fail("invalid_repository_path")
        path = self.repository_path[len(prefix) :]
        if not path or ".." in path.split("/") or "//" in path or path.endswith("/"):
            _fail("invalid_repository_path")
        _decode_b64(self.content_b64)

    @property
    def content(self) -> bytes:
        return _decode_b64(self.content_b64)

    def to_json(self) -> dict[str, str]:
        return {"content_b64": self.content_b64, "repository_path": self.repository_path}


@dataclass(frozen=True, slots=True)
class GitHubPublicationRequestV1:
    schema_version: int
    publication_id: str
    promotion_id: str
    resolution_id: str
    proposal_id: str
    decision_id: str
    sink_id: str
    owner: str
    repository: str
    base_ref: str
    base_oid: str
    branch_name: str
    commit_message: str
    pr_title: str
    pr_body: str
    marker: str
    files: tuple[GitHubPublicationFileV1, ...]
    promotion_bundle_fingerprint: str
    materialization_plan_fingerprint: str
    tree_manifest_fingerprint: str
    authorization_fingerprint: str
    request_fingerprint: str
    commit_author_name: str = "study-agent-devkit"
    commit_author_email: str = "study-agent-devkit@noreply.invalid"
    commit_committer_name: str = "study-agent-devkit"
    commit_committer_email: str = "study-agent-devkit@noreply.invalid"
    commit_timestamp: str = "1970-01-01T00:00:00Z"

    def __post_init__(self) -> None:
        if type(self.schema_version) is not int or self.schema_version != 1:
            _fail("invalid_request_schema_version")
        for value, name in (
            (self.publication_id, "publication_id"),
            (self.promotion_id, "promotion_id"),
            (self.resolution_id, "resolution_id"),
            (self.proposal_id, "proposal_id"),
            (self.decision_id, "decision_id"),
            (self.sink_id, "sink_id"),
            (self.promotion_bundle_fingerprint, "promotion_bundle_fingerprint"),
            (self.materialization_plan_fingerprint, "materialization_plan_fingerprint"),
            (self.tree_manifest_fingerprint, "tree_manifest_fingerprint"),
            (self.authorization_fingerprint, "authorization_fingerprint"),
            (self.request_fingerprint, "request_fingerprint"),
        ):
            _digest(value, name)
        _oid(self.base_oid, "base_oid")
        _opaque(self.owner, "owner")
        _opaque(self.repository, "repository")
        if "/" in self.owner or "/" in self.repository:
            _fail("invalid_github_target")
        _ref(self.base_ref, "base_ref")
        if (
            not self.branch_name.startswith("codex/capability-gap-")
            or len(self.branch_name) != len("codex/capability-gap-") + 24
        ):
            _fail("invalid_branch_name")
        if not _HEX24.fullmatch(self.branch_name[-24:]):
            _fail("invalid_branch_name")
        _text(self.commit_message, "commit_message", 16 * 1024)
        _text(self.pr_title, "pr_title", 4 * 1024)
        _text(self.pr_body, "pr_body", 64 * 1024)
        _text(self.marker, "marker", 4 * 1024)
        if self.promotion_id not in self.marker or self.request_fingerprint not in self.marker:
            _fail("marker_binding_mismatch")
        if type(self.files) is not tuple or not self.files:
            _fail("files_not_canonical")
        if any(not isinstance(item, GitHubPublicationFileV1) for item in self.files) or len(
            {item.repository_path for item in self.files}
        ) != len(self.files):
            _fail("invalid_files")
        paths = tuple(item.repository_path for item in self.files)
        if paths != tuple(sorted(paths)):
            _fail("files_not_canonical")
        try:
            parsed = datetime.fromisoformat(self.commit_timestamp.replace("Z", "+00:00"))
        except (TypeError, ValueError):
            _fail("invalid_commit_timestamp")
        if (
            parsed.tzinfo is None
            or parsed.utcoffset() != UTC.utcoffset(parsed)
            or not self.commit_timestamp.endswith("Z")
        ):
            _fail("invalid_commit_timestamp")
        if self.request_fingerprint != self.derive_fingerprint(self._body()):
            raise GitHubPublicationCorruptionError("request_fingerprint_mismatch")

    def _body(self) -> dict[str, object]:
        return {
            "authorization_fingerprint": self.authorization_fingerprint,
            "base_oid": self.base_oid,
            "base_ref": self.base_ref,
            "branch_name": self.branch_name,
            "commit_author_email": self.commit_author_email,
            "commit_author_name": self.commit_author_name,
            "commit_committer_email": self.commit_committer_email,
            "commit_committer_name": self.commit_committer_name,
            "commit_message": self.commit_message,
            "commit_timestamp": self.commit_timestamp,
            "decision_id": self.decision_id,
            "files": tuple(item.to_json() for item in self.files),
            "materialization_plan_fingerprint": self.materialization_plan_fingerprint,
            "marker": self.marker,
            "owner": self.owner,
            "pr_body": self.pr_body,
            "pr_title": self.pr_title,
            "promotion_bundle_fingerprint": self.promotion_bundle_fingerprint,
            "promotion_id": self.promotion_id,
            "proposal_id": self.proposal_id,
            "repository": self.repository,
            "resolution_id": self.resolution_id,
            "schema_version": 1,
            "sink_id": self.sink_id,
            "tree_manifest_fingerprint": self.tree_manifest_fingerprint,
        }

    def to_json(self) -> dict[str, object]:
        return {
            **self._body(),
            "publication_id": self.publication_id,
            "request_fingerprint": self.request_fingerprint,
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > _MAX_REQUEST_BYTES:
            _fail("oversized_request")
        return data

    @staticmethod
    def derive_fingerprint(body: Mapping[str, object]) -> str:
        # The marker carries this fingerprint for human/retry correlation.  It
        # is therefore deliberately excluded from the preimage to avoid a
        # circular fixed-point computation.
        material = dict(body)
        material["marker"] = ""
        if isinstance(material.get("pr_body"), str):
            material["pr_body"] = re.sub(
                r"request_fingerprint=[0-9a-f]{64}",
                "request_fingerprint=",
                cast(str, material["pr_body"]),
            )
        return sha256(_DOMAIN_REQUEST + canonical_json_bytes(cast(Any, material))).hexdigest()

    @classmethod
    def from_bytes(cls, data: bytes) -> GitHubPublicationRequestV1:
        fields = tuple(
            sorted(
                (
                    "authorization_fingerprint",
                    "base_oid",
                    "base_ref",
                    "branch_name",
                    "commit_author_email",
                    "commit_author_name",
                    "commit_committer_email",
                    "commit_committer_name",
                    "commit_message",
                    "commit_timestamp",
                    "decision_id",
                    "files",
                    "materialization_plan_fingerprint",
                    "marker",
                    "owner",
                    "pr_body",
                    "pr_title",
                    "promotion_bundle_fingerprint",
                    "promotion_id",
                    "proposal_id",
                    "publication_id",
                    "request_fingerprint",
                    "repository",
                    "resolution_id",
                    "schema_version",
                    "sink_id",
                    "tree_manifest_fingerprint",
                )
            )
        )
        value = _exact(data, fields, _MAX_REQUEST_BYTES)
        try:
            raw_files = value["files"]
            # canonical_json_object freezes JSON arrays as tuples.
            if not isinstance(raw_files, tuple):
                raise GitHubPublicationCorruptionError("invalid_files")
            files_list: list[GitHubPublicationFileV1] = []
            for item in raw_files:
                if not isinstance(item, Mapping) or tuple(sorted(item)) != (
                    "content_b64",
                    "repository_path",
                ):
                    raise GitHubPublicationCorruptionError("invalid_files")
                repository_path = item.get("repository_path")
                content_b64 = item.get("content_b64")
                if not isinstance(repository_path, str) or not isinstance(content_b64, str):
                    raise GitHubPublicationCorruptionError("invalid_files")
                files_list.append(GitHubPublicationFileV1(repository_path, content_b64))
            files = tuple(files_list)
            if len(files) != len(raw_files):
                raise GitHubPublicationCorruptionError("invalid_files")
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["publication_id"]),
                cast(str, value["promotion_id"]),
                cast(str, value["resolution_id"]),
                cast(str, value["proposal_id"]),
                cast(str, value["decision_id"]),
                cast(str, value["sink_id"]),
                cast(str, value["owner"]),
                cast(str, value["repository"]),
                cast(str, value["base_ref"]),
                cast(str, value["base_oid"]),
                cast(str, value["branch_name"]),
                cast(str, value["commit_message"]),
                cast(str, value["pr_title"]),
                cast(str, value["pr_body"]),
                cast(str, value["marker"]),
                files,
                cast(str, value["promotion_bundle_fingerprint"]),
                cast(str, value["materialization_plan_fingerprint"]),
                cast(str, value["tree_manifest_fingerprint"]),
                cast(str, value["authorization_fingerprint"]),
                cast(str, value["request_fingerprint"]),
                cast(str, value["commit_author_name"]),
                cast(str, value["commit_author_email"]),
                cast(str, value["commit_committer_name"]),
                cast(str, value["commit_committer_email"]),
                cast(str, value["commit_timestamp"]),
            )
        except (
            TypeError,
            ValueError,
            KeyError,
            GitHubPublicationValidationError,
            GitHubPublicationCorruptionError,
        ):
            raise GitHubPublicationCorruptionError("invalid_request") from None
        if result.to_bytes() != data:
            raise GitHubPublicationCorruptionError("noncanonical_request")
        return result


@dataclass(frozen=True, slots=True)
class GitHubPublicationReceiptV1:
    schema_version: int
    receipt_id: str
    publication_id: str
    promotion_id: str
    sink_id: str
    owner: str
    repository: str
    base_ref: str
    base_oid: str
    branch_name: str
    commit_oid: str
    pull_request_number: int
    pull_request_url: str
    request_fingerprint: str
    status: str = "published"

    def __post_init__(self) -> None:
        if type(self.schema_version) is not int or self.schema_version != 1:
            _fail("invalid_receipt_schema_version")
        for value, name in (
            (self.receipt_id, "receipt_id"),
            (self.publication_id, "publication_id"),
            (self.promotion_id, "promotion_id"),
            (self.sink_id, "sink_id"),
            (self.request_fingerprint, "request_fingerprint"),
        ):
            _digest(value, name)
        _oid(self.base_oid, "base_oid")
        _oid(self.commit_oid, "commit_oid")
        _opaque(self.owner, "owner")
        _opaque(self.repository, "repository")
        if "/" in self.owner or "/" in self.repository:
            _fail("invalid_github_target")
        _ref(self.base_ref, "base_ref")
        if self.branch_name != f"codex/capability-gap-{self.promotion_id[:24]}":
            _fail("invalid_branch_name")
        if type(self.pull_request_number) is not int or self.pull_request_number <= 0:
            _fail("invalid_pull_request_number")
        _text(self.pull_request_url, "pull_request_url", 2048)
        if self.status != "published":
            _fail("invalid_receipt_status")
        if self.receipt_id != self.derive_id(self._body()):
            raise GitHubPublicationCorruptionError("receipt_id_mismatch")

    def _body(self) -> dict[str, object]:
        return {
            "base_oid": self.base_oid,
            "base_ref": self.base_ref,
            "branch_name": self.branch_name,
            "commit_oid": self.commit_oid,
            "owner": self.owner,
            "promotion_id": self.promotion_id,
            "publication_id": self.publication_id,
            "pull_request_number": self.pull_request_number,
            "pull_request_url": self.pull_request_url,
            "request_fingerprint": self.request_fingerprint,
            "repository": self.repository,
            "schema_version": 1,
            "sink_id": self.sink_id,
            "status": self.status,
        }

    def to_json(self) -> dict[str, object]:
        return {**self._body(), "receipt_id": self.receipt_id}

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > _MAX_RECEIPT_BYTES:
            _fail("oversized_receipt")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> GitHubPublicationReceiptV1:
        fields = tuple(
            sorted(
                (
                    "base_oid",
                    "base_ref",
                    "branch_name",
                    "commit_oid",
                    "owner",
                    "promotion_id",
                    "publication_id",
                    "pull_request_number",
                    "pull_request_url",
                    "receipt_id",
                    "request_fingerprint",
                    "repository",
                    "schema_version",
                    "sink_id",
                    "status",
                )
            )
        )
        value = _exact(data, fields, _MAX_RECEIPT_BYTES)
        try:
            result = cls(
                cast(int, value["schema_version"]),
                cast(str, value["receipt_id"]),
                cast(str, value["publication_id"]),
                cast(str, value["promotion_id"]),
                cast(str, value["sink_id"]),
                cast(str, value["owner"]),
                cast(str, value["repository"]),
                cast(str, value["base_ref"]),
                cast(str, value["base_oid"]),
                cast(str, value["branch_name"]),
                cast(str, value["commit_oid"]),
                cast(int, value["pull_request_number"]),
                cast(str, value["pull_request_url"]),
                cast(str, value["request_fingerprint"]),
                cast(str, value["status"]),
            )
        except (
            TypeError,
            ValueError,
            GitHubPublicationValidationError,
            GitHubPublicationCorruptionError,
        ):
            raise GitHubPublicationCorruptionError("invalid_receipt") from None
        if result.to_bytes() != data:
            raise GitHubPublicationCorruptionError("noncanonical_receipt")
        return result

    @staticmethod
    def derive_id(body: Mapping[str, object]) -> str:
        return sha256(_DOMAIN_RECEIPT + canonical_json_bytes(cast(Any, body))).hexdigest()


# Remote records are deliberately transport-neutral.  REST and scripted tests
# both implement the same exact Git object / pull-request surface.
@dataclass(frozen=True, slots=True)
class GitHubCommitV1:
    oid: str
    tree_oid: str
    parent_oids: tuple[str, ...]
    message: str
    author_name: str
    author_email: str
    author_timestamp: str
    committer_name: str
    committer_email: str
    committer_timestamp: str


@dataclass(frozen=True, slots=True)
class GitHubTreeEntryV1:
    path: str
    mode: str
    entry_type: str
    oid: str
    size: int | None = None


@dataclass(frozen=True, slots=True)
class GitHubPullRequestV1:
    number: int
    url: str
    head_ref: str
    base_ref: str
    title: str
    body: str
    draft: bool
    state: str = "open"


@runtime_checkable
class GitHubApi(Protocol):
    def get_ref(self, owner: str, repository: str, ref: str) -> str | None: ...
    def get_commit(self, owner: str, repository: str, oid: str) -> GitHubCommitV1: ...
    def get_tree(
        self, owner: str, repository: str, tree_oid: str
    ) -> tuple[GitHubTreeEntryV1, ...]: ...
    def get_blob(self, owner: str, repository: str, oid: str) -> bytes: ...
    def create_blob(self, owner: str, repository: str, content: bytes) -> str: ...
    def create_tree(
        self,
        owner: str,
        repository: str,
        base_tree_oid: str,
        entries: tuple[tuple[str, str, str], ...],
    ) -> str: ...
    def create_commit(
        self,
        owner: str,
        repository: str,
        message: str,
        tree_oid: str,
        parent_oids: tuple[str, ...],
        *,
        author_name: str,
        author_email: str,
        author_timestamp: str,
        committer_name: str,
        committer_email: str,
        committer_timestamp: str,
    ) -> GitHubCommitV1: ...
    def create_ref(self, owner: str, repository: str, ref: str, oid: str) -> None: ...
    def list_pull_requests(
        self, owner: str, repository: str, head_ref: str, base_ref: str
    ) -> tuple[GitHubPullRequestV1, ...]: ...
    def create_pull_request(
        self,
        owner: str,
        repository: str,
        head_ref: str,
        base_ref: str,
        title: str,
        body: str,
        *,
        draft: bool,
    ) -> GitHubPullRequestV1: ...


@runtime_checkable
class CredentialProvider(Protocol):
    def __call__(self) -> str: ...


__all__ = [
    name
    for name in globals()
    if name.startswith("GitHub")
    or name
    in {
        "AcceptedPromotionSource",
        "AcceptedPromotionViewV1",
        "CredentialProvider",
        "promotion_fingerprint",
        "plan_fingerprint",
    }
]
