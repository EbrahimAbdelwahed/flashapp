"""Pure planning and rendering for a self-contained Flywheel run.

This module deliberately has no filesystem, process, network, provider, or
capability-gap dependency.  It owns only closed value objects, canonical
codecs, deterministic renderers, and in-memory validation.  The local runner
and a later promotion adapter can therefore share the exact same behavior.
"""

from __future__ import annotations

import base64
import binascii
import json
import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, NoReturn, cast

try:
    from study_agent.state import canonical_json_bytes, canonical_json_object
except ModuleNotFoundError as exc:  # pragma: no cover - direct runner before install
    if exc.name not in {"study_agent", "study_agent.state"}:
        raise

    def canonical_json_bytes(value: Any) -> bytes:  # type: ignore[misc]
        return json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
        ).encode("utf-8")

    def canonical_json_object(data: bytes) -> Mapping[str, Any]:  # type: ignore[misc]
        value = json.loads(data.decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("expected object")
        return cast(Mapping[str, Any], value)


SCHEMA_VERSION = 1
MAX_FILES = 128
MAX_FILE_BYTES = 256 * 1024
MAX_PLAN_BYTES = 2 * 1024 * 1024
MAX_FINDINGS = 256
MAX_FINDING_CODE = 64
MAX_FINDING_MESSAGE_BYTES = 4 * 1024
MAX_CONTEXT_BYTES = 256 * 1024
MAX_ARTIFACT_BODY_BYTES = 512 * 1024
MAX_GOAL_BYTES = 256 * 1024
MAX_TEXT_BYTES = 64 * 1024
_OPAQUE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$")
_ASCII_CODE_RE = re.compile(r"^[A-Za-z0-9._:-]+$")
_REQUIRED_TASK_SECTIONS = (
    "Outcome",
    "Slice Strategy",
    "Spec Coverage",
    "Grilling Evidence",
    "Worker Profile",
    "Context",
    "What To Do",
    "Likely Files / Packages",
    "Acceptance Criteria",
    "Verification",
    "Out Of Scope",
)
_REQUIRED_SPEC_SECTIONS = (
    "Grilling Evidence",
    "Goal",
    "Problem",
    "In Scope",
    "Out of Scope",
    "Acceptance Criteria",
    "Verification",
)
_PLACEHOLDERS = (
    re.compile(r"<[^>\n]+>"),
    re.compile(r"\b(?:TODO|TBD|FIXME)\b", re.IGNORECASE),
    re.compile(r"Draft public shape", re.IGNORECASE),
    re.compile(r"Observable behavior satisfies the spec", re.IGNORECASE),
    re.compile(r"Run the narrowest relevant verification command", re.IGNORECASE),
    re.compile(r"Derived from the feature spec and context pack", re.IGNORECASE),
)
_PROFILE_RE = re.compile(r"^create\s+(`?)([A-Za-z0-9][A-Za-z0-9._:@-]{0,127})\1$", re.IGNORECASE)
_OPAQUE_PATH_RE = re.compile(r"^[^/\\]+$")


class MaterializationContractError(ValueError):
    """A value supplied by trusted host code violates this closed contract."""


class MaterializationCorruptionError(MaterializationContractError):
    """Bytes are malformed, noncanonical, or violate their declared schema."""


def _fail(message: str) -> NoReturn:
    raise MaterializationContractError(message)


def _schema(value: object) -> int:
    if type(value) is not int or value != SCHEMA_VERSION:
        _fail("invalid_schema_version")
    return value


def _opaque(value: object, field: str) -> str:
    if not isinstance(value, str) or _OPAQUE_RE.fullmatch(value) is None:
        _fail(f"invalid_{field}")
    return value


def _text(value: object, field: str, *, max_bytes: int = MAX_TEXT_BYTES) -> str:
    if not isinstance(value, str):
        _fail(f"invalid_{field}")
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError:
        _fail(f"invalid_{field}_utf8")
    if len(encoded) > max_bytes:
        _fail(f"oversized_{field}")
    if any((ord(char) < 32 or 0x7F <= ord(char) <= 0x9F) and char not in "\t\n" for char in value):
        _fail(f"invalid_{field}_control")
    return value


def _tuple_text(
    value: object, field: str, *, max_items: int = 256, max_bytes: int = MAX_TEXT_BYTES
) -> tuple[str, ...]:
    if type(value) is not tuple or len(value) > max_items:
        _fail(f"invalid_{field}")
    return tuple(
        _text(item, field, max_bytes=max_bytes) for item in cast(tuple[object, ...], value)
    )


def _exact(data: bytes, fields: tuple[str, ...], *, max_bytes: int) -> Mapping[str, Any]:
    if type(data) is not bytes or len(data) > max_bytes:
        raise MaterializationCorruptionError("invalid_payload")
    try:
        value = canonical_json_object(data)
    except (TypeError, ValueError, UnicodeDecodeError):
        raise MaterializationCorruptionError("invalid_payload") from None
    if tuple(sorted(value)) != tuple(sorted(fields)):
        raise MaterializationCorruptionError("invalid_fields")
    if canonical_json_bytes(cast(Any, value)) != data:
        raise MaterializationCorruptionError("noncanonical_payload")
    return value


def _path(value: object, field: str = "relative_path") -> str:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        _fail(f"invalid_{field}")
    if value.startswith("/") or value.startswith("~") or "://" in value:
        _fail(f"invalid_{field}")
    segments = value.split("/")
    if any(not segment or segment in {".", ".."} for segment in segments):
        _fail(f"invalid_{field}")
    if any(_OPAQUE_PATH_RE.fullmatch(segment) is None for segment in segments):
        _fail(f"invalid_{field}")
    _text(value, field, max_bytes=1024)
    return value


def _b64(value: object, field: str = "content_b64") -> str:
    if not isinstance(value, str) or any(ord(char) > 127 for char in value):
        _fail(f"invalid_{field}")
    if len(value) % 4:
        _fail(f"invalid_{field}")
    # Reject impossible encoded lengths before invoking the decoder.  This is
    # both a cheap size guard and protection against oversized attacker input.
    if len(value) > 4 * ((MAX_FILE_BYTES + 2) // 3):
        _fail(f"oversized_{field}")
    try:
        decoded = base64.b64decode(value.encode("ascii"), validate=True)
    except (ValueError, binascii.Error):
        _fail(f"invalid_{field}")
    if base64.b64encode(decoded).decode("ascii") != value:
        _fail(f"noncanonical_{field}")
    if len(decoded) > MAX_FILE_BYTES:
        _fail("oversized_file")
    return value


def _decode_b64(value: str) -> bytes:
    return base64.b64decode(value.encode("ascii"), validate=True)


def _as_mapping(value: object, field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise MaterializationCorruptionError(f"invalid_{field}")
    return cast(Mapping[str, Any], value)


def _as_tuple(value: object, field: str, *, max_items: int = 256) -> tuple[object, ...]:
    if not isinstance(value, list | tuple) or len(value) > max_items:
        raise MaterializationCorruptionError(f"invalid_{field}")
    return tuple(cast(list[object] | tuple[object, ...], value))


def _require_no_bool_int(value: object, field: str) -> int:
    if type(value) is not int:
        raise MaterializationCorruptionError(f"invalid_{field}")
    return value


@dataclass(frozen=True, slots=True)
class RunArtifactV1:
    kind: str
    artifact_id: str
    body: str
    depends_on: tuple[str, ...]

    def __post_init__(self) -> None:
        if self.kind not in {"adr", "spec", "task"}:
            _fail("invalid_artifact_kind")
        _opaque(self.artifact_id, "artifact_id")
        _text(self.body, "artifact_body", max_bytes=MAX_ARTIFACT_BODY_BYTES)
        if type(self.depends_on) is not tuple or len(self.depends_on) > 64:
            _fail("invalid_dependencies")
        if len(set(self.depends_on)) != len(self.depends_on):
            _fail("duplicate_dependency")
        for item in self.depends_on:
            _opaque(item, "dependency")
        if self.kind in {"adr", "spec"} and self.depends_on:
            _fail("artifact_dependencies_forbidden")

    def to_json(self) -> dict[str, object]:
        return {
            "artifact_id": self.artifact_id,
            "body": self.body,
            "depends_on": self.depends_on,
            "kind": self.kind,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> RunArtifactV1:
        value = _exact(
            data,
            ("artifact_id", "body", "depends_on", "kind"),
            max_bytes=MAX_ARTIFACT_BODY_BYTES + 16 * 1024,
        )
        try:
            result = cls(
                cast(str, value["kind"]),
                cast(str, value["artifact_id"]),
                cast(str, value["body"]),
                tuple(
                    cast(str, item)
                    for item in _as_tuple(value["depends_on"], "depends_on", max_items=64)
                ),
            )
        except (TypeError, ValueError, MaterializationContractError):
            raise MaterializationCorruptionError("invalid_artifact") from None
        if result.to_bytes() != data:
            raise MaterializationCorruptionError("noncanonical_artifact")
        return result


@dataclass(frozen=True, slots=True)
class WorkerProfileRenderInputV1:
    profile_id: str
    task_id: str
    task_ref: str
    task_title: str
    spec_ref: str
    context_ref: str
    reuse_trigger: str
    mandate: str
    scope: tuple[str, ...]
    out_of_scope: tuple[str, ...]
    allowed_inspect: tuple[str, ...]
    research_note: str
    allowed_edit: tuple[str, ...]
    forbidden_decisions: tuple[str, ...]
    quality_gates: tuple[str, ...]
    verification_commands: tuple[str, ...]
    generated_at: str = ""
    # Parsed task-contract fields.  They are optional for backwards-compatible
    # hosts, but a materialized plan supplies them verbatim rather than asking
    # the renderer to infer missing behavior.
    outcome: str = ""
    context: str = ""
    likely_files: tuple[str, ...] = ()
    acceptance_criteria: tuple[str, ...] = ()
    stop_conditions: tuple[str, ...] = ()
    invariants: tuple[str, ...] = ()
    review_gate: str = ""

    def __post_init__(self) -> None:
        for value, field in ((self.profile_id, "profile_id"), (self.task_id, "task_id")):
            _opaque(value, field)
        for value, field in (
            (self.task_ref, "task_ref"),
            (self.spec_ref, "spec_ref"),
            (self.context_ref, "context_ref"),
        ):
            _path(value, field)
        _text(self.task_title, "task_title")
        for value, field in (
            (self.reuse_trigger, "reuse_trigger"),
            (self.mandate, "mandate"),
            (self.research_note, "research_note"),
        ):
            _text(value, field)
        _tuple_text(self.scope, "scope")
        _tuple_text(self.out_of_scope, "out_of_scope")
        _tuple_text(self.allowed_inspect, "allowed_inspect")
        _tuple_text(self.allowed_edit, "allowed_edit")
        _tuple_text(self.forbidden_decisions, "forbidden_decisions")
        _tuple_text(self.quality_gates, "quality_gates")
        _tuple_text(self.verification_commands, "verification_commands")
        _text(self.generated_at, "generated_at", max_bytes=128)
        _text(self.outcome, "outcome")
        _text(self.context, "context", max_bytes=MAX_CONTEXT_BYTES)
        _tuple_text(self.likely_files, "likely_files")
        _tuple_text(self.acceptance_criteria, "acceptance_criteria")
        _tuple_text(self.stop_conditions, "stop_conditions")
        _tuple_text(self.invariants, "invariants")
        _text(self.review_gate, "review_gate")


@dataclass(frozen=True, slots=True)
class WorkerBriefRenderInputV1:
    task_id: str
    task_title: str
    spec_ref: str
    task_ref: str
    context_ref: str
    profile_ref: str | None
    outcome: str = ""
    context: str = ""
    allowed_scope: tuple[str, ...] = ()
    forbidden_scope: tuple[str, ...] = ()
    invariants: tuple[str, ...] = ()
    acceptance_criteria: tuple[str, ...] = ()
    verification: tuple[str, ...] = ()
    stop_conditions: tuple[str, ...] = ()
    review_gate: str = ""

    def __post_init__(self) -> None:
        _opaque(self.task_id, "task_id")
        _text(self.task_title, "task_title")
        _path(self.spec_ref, "spec_ref")
        _path(self.task_ref, "task_ref")
        _path(self.context_ref, "context_ref")
        if self.profile_ref is not None:
            _path(self.profile_ref, "profile_ref")
        _text(self.outcome, "outcome")
        _text(self.context, "context", max_bytes=MAX_CONTEXT_BYTES)
        _tuple_text(self.allowed_scope, "allowed_scope")
        _tuple_text(self.forbidden_scope, "forbidden_scope")
        _tuple_text(self.invariants, "invariants")
        _tuple_text(self.acceptance_criteria, "acceptance_criteria")
        _tuple_text(self.verification, "verification")
        _tuple_text(self.stop_conditions, "stop_conditions")
        _text(self.review_gate, "review_gate")


@dataclass(frozen=True, slots=True)
class PromotedRunInputV1:
    schema_version: int
    run_id: str
    feature_title: str
    source_ref: str
    context_body: str
    spec: RunArtifactV1
    adrs: tuple[RunArtifactV1, ...]
    tasks: tuple[RunArtifactV1, ...]
    implementation_goal_json: bytes | None = None

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _opaque(self.run_id, "run_id")
        _text(self.feature_title, "feature_title")
        _path(self.source_ref, "source_ref")
        _text(self.context_body, "context_body", max_bytes=MAX_CONTEXT_BYTES)
        if not isinstance(self.spec, RunArtifactV1) or self.spec.kind != "spec":
            _fail("invalid_spec_artifact")
        if type(self.adrs) is not tuple or any(
            not isinstance(item, RunArtifactV1) or item.kind != "adr" for item in self.adrs
        ):
            _fail("invalid_adr_artifacts")
        if (
            type(self.tasks) is not tuple
            or not self.tasks
            or any(
                not isinstance(item, RunArtifactV1) or item.kind != "task" for item in self.tasks
            )
        ):
            _fail("invalid_task_artifacts")
        artifacts = (self.spec, *self.adrs, *self.tasks)
        ids = tuple(item.artifact_id for item in artifacts)
        if len(set(ids)) != len(ids):
            _fail("duplicate_artifact_id")
        task_ids = {item.artifact_id for item in self.tasks}
        for task in self.tasks:
            if any(dep not in task_ids for dep in task.depends_on):
                _fail("unknown_dependency")
        if self.implementation_goal_json is not None:
            if (
                type(self.implementation_goal_json) is not bytes
                or len(self.implementation_goal_json) > MAX_GOAL_BYTES
            ):
                _fail("invalid_implementation_goal")
            try:
                goal = canonical_json_object(self.implementation_goal_json)
                if canonical_json_bytes(cast(Any, goal)) != self.implementation_goal_json:
                    _fail("noncanonical_implementation_goal")
            except (TypeError, ValueError, UnicodeDecodeError):
                _fail("invalid_implementation_goal")

    def to_json(self) -> dict[str, object]:
        return {
            "adrs": tuple(item.to_json() for item in self.adrs),
            "context_body": self.context_body,
            "feature_title": self.feature_title,
            "implementation_goal_json_b64": None
            if self.implementation_goal_json is None
            else base64.b64encode(self.implementation_goal_json).decode("ascii"),
            "run_id": self.run_id,
            "schema_version": self.schema_version,
            "source_ref": self.source_ref,
            "spec": self.spec.to_json(),
            "tasks": tuple(item.to_json() for item in self.tasks),
        }

    def to_bytes(self) -> bytes:
        data = canonical_json_bytes(cast(Any, self.to_json()))
        if len(data) > MAX_PLAN_BYTES:
            _fail("oversized_run_input")
        return data

    @classmethod
    def from_bytes(cls, data: bytes) -> PromotedRunInputV1:
        fields = (
            "adrs",
            "context_body",
            "feature_title",
            "implementation_goal_json_b64",
            "run_id",
            "schema_version",
            "source_ref",
            "spec",
            "tasks",
        )
        value = _exact(data, fields, max_bytes=MAX_PLAN_BYTES)
        try:
            spec = _artifact_from_mapping(value["spec"])
            adrs = tuple(
                _artifact_from_mapping(item)
                for item in _as_tuple(value["adrs"], "adrs", max_items=64)
            )
            tasks = tuple(
                _artifact_from_mapping(item)
                for item in _as_tuple(value["tasks"], "tasks", max_items=64)
            )
            goal = value["implementation_goal_json_b64"]
            goal_bytes = (
                None
                if goal is None
                else _decode_optional_b64(cast(str, goal), "implementation_goal_json_b64")
            )
            result = cls(
                _require_no_bool_int(value["schema_version"], "schema_version"),
                cast(str, value["run_id"]),
                cast(str, value["feature_title"]),
                cast(str, value["source_ref"]),
                cast(str, value["context_body"]),
                spec,
                adrs,
                tasks,
                goal_bytes,
            )
        except (
            TypeError,
            ValueError,
            MaterializationContractError,
            MaterializationCorruptionError,
        ):
            raise MaterializationCorruptionError("invalid_run_input") from None
        if result.to_bytes() != data:
            raise MaterializationCorruptionError("noncanonical_run_input")
        return result


def _decode_optional_b64(value: str, field: str, *, max_bytes: int = MAX_GOAL_BYTES) -> bytes:
    if not isinstance(value, str) or not value:
        raise MaterializationCorruptionError(f"invalid_{field}")
    if len(value) % 4 or len(value) > 4 * ((max_bytes + 2) // 3):
        raise MaterializationCorruptionError(f"invalid_{field}")
    try:
        decoded = base64.b64decode(value.encode("ascii"), validate=True)
    except (ValueError, UnicodeEncodeError, binascii.Error):
        raise MaterializationCorruptionError(f"invalid_{field}") from None
    if base64.b64encode(decoded).decode("ascii") != value:
        raise MaterializationCorruptionError(f"noncanonical_{field}")
    if len(decoded) > max_bytes:
        raise MaterializationCorruptionError(f"oversized_{field}")
    return decoded


def _artifact_from_mapping(value: object) -> RunArtifactV1:
    item = _as_mapping(value, "artifact")
    if tuple(sorted(item)) != ("artifact_id", "body", "depends_on", "kind"):
        raise MaterializationCorruptionError("invalid_artifact_fields")
    return RunArtifactV1(
        cast(str, item["kind"]),
        cast(str, item["artifact_id"]),
        cast(str, item["body"]),
        tuple(cast(str, dep) for dep in _as_tuple(item["depends_on"], "depends_on", max_items=64)),
    )


def _file_from_mapping(value: object) -> MaterializationFileV1:
    item = _as_mapping(value, "file")
    if tuple(sorted(item)) != ("content_b64", "relative_path"):
        raise MaterializationCorruptionError("invalid_materialization_file_fields")
    return MaterializationFileV1(
        cast(str, item["relative_path"]),
        cast(str, item["content_b64"]),
    )


@dataclass(frozen=True, slots=True)
class MaterializationFileV1:
    relative_path: str
    content_b64: str

    def __post_init__(self) -> None:
        _path(self.relative_path)
        _b64(self.content_b64)

    @property
    def content(self) -> bytes:
        return _decode_b64(self.content_b64)

    def to_json(self) -> dict[str, str]:
        return {"content_b64": self.content_b64, "relative_path": self.relative_path}

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> MaterializationFileV1:
        value = _exact(data, ("content_b64", "relative_path"), max_bytes=MAX_FILE_BYTES * 2)
        try:
            result = cls(cast(str, value["relative_path"]), cast(str, value["content_b64"]))
        except (TypeError, ValueError, MaterializationContractError):
            raise MaterializationCorruptionError("invalid_materialization_file") from None
        if result.to_bytes() != data:
            raise MaterializationCorruptionError("noncanonical_materialization_file")
        return result


@dataclass(frozen=True, slots=True)
class MaterializationPlanV1:
    schema_version: int
    run_id: str
    files: tuple[MaterializationFileV1, ...]

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        _opaque(self.run_id, "run_id")
        if type(self.files) is not tuple or not self.files or len(self.files) > MAX_FILES:
            _fail("invalid_materialization_files")
        if any(not isinstance(item, MaterializationFileV1) for item in self.files):
            _fail("invalid_materialization_files")
        paths = tuple(item.relative_path for item in self.files)
        if paths != tuple(sorted(paths)):
            _fail("files_not_canonical")
        if len(set(paths)) != len(paths) or len({path.casefold() for path in paths}) != len(paths):
            _fail("duplicate_materialization_path")
        if len(self.to_bytes()) > MAX_PLAN_BYTES:
            _fail("oversized_materialization_plan")

    def to_json(self) -> dict[str, object]:
        return {
            "files": tuple(item.to_json() for item in self.files),
            "run_id": self.run_id,
            "schema_version": self.schema_version,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> MaterializationPlanV1:
        value = _exact(data, ("files", "run_id", "schema_version"), max_bytes=MAX_PLAN_BYTES)
        try:
            files = tuple(
                _file_from_mapping(item)
                for item in _as_tuple(value["files"], "files", max_items=MAX_FILES)
            )
            result = cls(
                _require_no_bool_int(value["schema_version"], "schema_version"),
                cast(str, value["run_id"]),
                files,
            )
        except (TypeError, ValueError, MaterializationContractError):
            raise MaterializationCorruptionError("invalid_materialization_plan") from None
        if result.to_bytes() != data:
            raise MaterializationCorruptionError("noncanonical_materialization_plan")
        return result


@dataclass(frozen=True, slots=True)
class ValidationFindingV1:
    schema_version: int
    severity: str
    code: str
    relative_path: str | None
    message: str

    def __post_init__(self) -> None:
        _schema(self.schema_version)
        if self.severity not in {"error", "warning"}:
            _fail("invalid_finding_severity")
        if (
            not isinstance(self.code, str)
            or len(self.code.encode("ascii", "strict")) > MAX_FINDING_CODE
            or _ASCII_CODE_RE.fullmatch(self.code) is None
        ):
            _fail("invalid_finding_code")
        if self.relative_path is not None:
            _path(self.relative_path)
        _text(self.message, "finding_message", max_bytes=MAX_FINDING_MESSAGE_BYTES)

    def to_json(self) -> dict[str, object]:
        return {
            "code": self.code,
            "message": self.message,
            "relative_path": self.relative_path,
            "schema_version": self.schema_version,
            "severity": self.severity,
        }

    def to_bytes(self) -> bytes:
        return canonical_json_bytes(cast(Any, self.to_json()))

    @classmethod
    def from_bytes(cls, data: bytes) -> ValidationFindingV1:
        value = _exact(
            data,
            ("code", "message", "relative_path", "schema_version", "severity"),
            max_bytes=MAX_FINDING_MESSAGE_BYTES + 4096,
        )
        try:
            result = cls(
                _require_no_bool_int(value["schema_version"], "schema_version"),
                cast(str, value["severity"]),
                cast(str, value["code"]),
                cast(str | None, value["relative_path"]),
                cast(str, value["message"]),
            )
        except (TypeError, ValueError, UnicodeEncodeError, MaterializationContractError):
            raise MaterializationCorruptionError("invalid_validation_finding") from None
        if result.to_bytes() != data:
            raise MaterializationCorruptionError("noncanonical_validation_finding")
        return result


def _section(text: str, heading: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}\s*$", text, re.MULTILINE)
    if match is None:
        return ""
    next_heading = re.search(r"^##\s+", text[match.end() :], re.MULTILINE)
    end = match.end() + next_heading.start() if next_heading else len(text)
    return text[match.end() : end].strip()


def _items(section: str) -> tuple[str, ...]:
    values: list[str] = []
    for line in section.splitlines():
        stripped = line.strip()
        if stripped.startswith("- [ ] "):
            stripped = stripped[6:].strip()
        elif stripped.startswith("- "):
            stripped = stripped[2:].strip()
        else:
            continue
        if stripped and stripped != "<none>":
            values.append(stripped)
    return tuple(values)


def _has_placeholder(text: str) -> bool:
    return any(pattern.search(text) for pattern in _PLACEHOLDERS)


def _validate_spec_body(text: str, *, strict: bool = True) -> None:
    if not text.strip() or _has_placeholder(text):
        _fail("invalid_spec_body")
    if re.search(r"^Status:\s*Draft\s*$", text, re.MULTILINE | re.IGNORECASE):
        _fail("invalid_spec_body")
    if strict:
        for section in _REQUIRED_SPEC_SECTIONS:
            content = _section(text, section)
            if not content or _has_placeholder(content):
                _fail("incomplete_spec_contract")


def _validate_adr_body(data: bytes) -> None:
    if type(data) is not bytes or len(data) > MAX_ARTIFACT_BODY_BYTES:
        _fail("invalid_adr_body")
    try:
        text = data.decode("utf-8", "strict")
    except UnicodeDecodeError:
        _fail("invalid_adr_utf8")
    _text(text, "adr_body", max_bytes=MAX_ARTIFACT_BODY_BYTES)
    if _has_placeholder(text) or re.search(
        r"^Status:\s*Draft\s*$", text, re.MULTILINE | re.IGNORECASE
    ):
        _fail("invalid_adr_body")


def _task_contract(task: RunArtifactV1, *, strict: bool = True) -> dict[str, object]:
    """Parse the closed task contract once for all render/validation consumers.

    The parser intentionally returns only source text and list items present in
    the bead.  It never fills an absent section with a guessed default.  The
    ``strict`` mode is used by dispatch validation; the permissive mode keeps
    old approved beads renderable while they are being migrated to the richer
    contract.
    """
    body = task.body
    heading = re.search(
        r"^# Task Bead:\s+([A-Za-z0-9][A-Za-z0-9._:@-]*)(?:\s+(.+?))?\s*$",
        body,
        re.MULTILINE,
    )
    if heading is None or heading.group(1) != task.artifact_id:
        _fail("invalid_task_heading")
    sections: dict[str, str] = {name: _section(body, name) for name in _REQUIRED_TASK_SECTIONS}
    for _name, value in sections.items():
        if not value:
            _fail("incomplete_task_contract")
        if _has_placeholder(value):
            _fail("invalid_task_body")

    def items(name: str) -> tuple[str, ...]:
        value = _items(sections[name])
        # These sections are list-valued in the runner contract.  A non-empty
        # prose blob is not silently converted into a one-item list.
        if (
            name
            in {
                "Spec Coverage",
                "Grilling Evidence",
                "What To Do",
                "Likely Files / Packages",
                "Acceptance Criteria",
                "Verification",
                "Out Of Scope",
            }
            and not value
        ):
            _fail(f"invalid_{name.lower().replace(' ', '_').replace('/', '_')}")
        return value

    optional = {
        name: _section(body, name)
        for name in ("Stop Conditions", "Invariants", "Review Gate", "Independent Semantic Review")
    }
    # Explicit optional sections are still required to be parseable; omission
    # means the migration-era closed template will supply the review gate.
    for _name, value in optional.items():
        if value and _has_placeholder(value):
            _fail("invalid_task_body")
    if optional["Stop Conditions"] and not _items(optional["Stop Conditions"]):
        _fail("invalid_stop_conditions")
    if optional["Invariants"] and not _items(optional["Invariants"]):
        _fail("invalid_invariants")

    depends_match = re.search(r"^Depends On:\s*(.*?)\s*$", body, re.MULTILINE)
    declared_depends: tuple[str, ...] | None = None
    if depends_match:
        raw = depends_match.group(1).strip()
        declared_depends = (
            ()
            if not raw or raw.lower() == "none"
            else tuple(item.strip() for item in raw.split(",") if item.strip())
        )
        if any(_OPAQUE_RE.fullmatch(item) is None for item in declared_depends):
            _fail("invalid_dependencies")
    fresh_match = re.search(
        r"^Fresh Context Fit:\s*(yes|no)\s*$",
        body,
        re.MULTILINE | re.IGNORECASE,
    )
    fresh_fit = fresh_match.group(1).lower() if fresh_match else None
    strategy = sections["Slice Strategy"].splitlines()[0].strip().lower()
    if strict:
        if fresh_fit != "yes":
            _fail("fresh_context_overflow")
        if strategy not in {"tracer-bullet", "prefactor", "expand", "migrate", "contract"}:
            _fail("unknown_slice_strategy")
        if declared_depends is None:
            _fail("missing_dependency_declaration")
        if (
            not sections["Outcome"].strip()
            or not sections["Context"].strip()
            or sections["Context"].strip().lower() in {"none", "<none>"}
        ):
            _fail("invalid_task_contract")
    return {
        "heading_title": heading.group(2).strip() if heading.group(2) else task.artifact_id,
        "outcome": sections["Outcome"],
        "slice_strategy": sections["Slice Strategy"],
        "spec_coverage": items("Spec Coverage"),
        "grilling_evidence": items("Grilling Evidence"),
        "worker_profile": sections["Worker Profile"],
        "context": sections["Context"],
        "what_to_do": items("What To Do"),
        "likely_files": items("Likely Files / Packages"),
        "acceptance_criteria": items("Acceptance Criteria"),
        "verification": items("Verification"),
        "out_of_scope": items("Out Of Scope"),
        "stop_conditions": _items(optional["Stop Conditions"]),
        "invariants": _items(optional["Invariants"]),
        "review_gate": optional["Review Gate"] or optional["Independent Semantic Review"],
        "declared_depends": declared_depends,
        "fresh_context_fit": fresh_fit,
    }


def _profile_directive(section: str) -> tuple[str, str | None]:
    first = next(
        (
            line.strip()
            for line in section.splitlines()
            if line.strip() and line.strip().lower() != "rationale:"
        ),
        "",
    )
    if first.lower() == "none needed":
        return "none", None
    match = _PROFILE_RE.fullmatch(first)
    if match:
        return "create", match.group(2)
    reuse = re.fullmatch(r"reuse\s+`?([A-Za-z0-9][A-Za-z0-9._:@-]{0,127})`?", first, re.IGNORECASE)
    return ("reuse", reuse.group(1)) if reuse else ("invalid", None)


def _validate_closed_profile(data: bytes, profile_id: str) -> None:
    try:
        text = data.decode("utf-8", "strict")
    except UnicodeDecodeError:
        _fail("invalid_worker_profile_utf8")
    _text(text, "worker_profile", max_bytes=MAX_ARTIFACT_BODY_BYTES)
    # The historical runner uses `<none>` for explicit empty optional fields;
    # treat that value as closed data while still rejecting scaffold markers.
    profile_text = re.sub(r"<none>", "", text, flags=re.IGNORECASE)
    if _has_placeholder(profile_text) or not re.search(
        rf"^# Worker Profile:\s+{re.escape(profile_id)}\s*$", text, re.MULTILINE
    ):
        _fail("invalid_worker_profile")
    if not _section(text, "Verification"):
        _fail("invalid_worker_profile")


def _profile_input(
    task: RunArtifactV1,
    spec_ref: str,
    context_ref: str,
    generated_at: str = "",
    task_ref: str | None = None,
) -> WorkerProfileRenderInputV1:
    contract = _task_contract(task)
    profile = cast(str, contract["worker_profile"])
    first = next(
        (
            line.strip()
            for line in profile.splitlines()
            if line.strip() and line.strip().lower() != "rationale:"
        ),
        "",
    )
    match = _PROFILE_RE.fullmatch(first)
    if match is None:
        _fail("unsupported_worker_profile_directive")
    profile_id = match.group(2)
    task_title = cast(str, contract["heading_title"])
    # The pure plan path uses the closed task sections as its only source.  The
    # runner's historical defaults are represented explicitly here.
    return WorkerProfileRenderInputV1(
        profile_id=profile_id,
        task_id=task.artifact_id,
        task_ref=task_ref or f"tasks/{task.artifact_id}.md",
        task_title=task_title,
        spec_ref=spec_ref,
        context_ref=context_ref,
        reuse_trigger=(
            f"Use this worker when a bead has the same implementation shape as `{task_title}`."
        ),
        mandate=(
            f"Complete recurring work shaped like `{task.artifact_id}` without redesigning the "
            "feature."
        ),
        scope=(
            "Implement the scoped task behavior described by the linked bead and worker brief.",
        ),
        out_of_scope=cast(tuple[str, ...], contract["out_of_scope"]),
        allowed_inspect=(
            spec_ref,
            context_ref,
            f"tasks/{task.artifact_id}.md",
            "applicable `AGENTS.md` files",
        ),
        research_note="not needed",
        allowed_edit=cast(tuple[str, ...], contract["likely_files"]),
        forbidden_decisions=(
            "architecture boundaries outside the task bead",
            "product behavior not covered by acceptance criteria",
            "new dependencies or provider choices",
            "data model or persistence changes not specified by the orchestrator",
        ),
        quality_gates=(
            "Change stays within the task file/package scope.",
            "Acceptance criteria are implemented or explicitly reported as blocked.",
            "Verification commands from the task bead are run or a concrete reason is reported.",
        ),
        verification_commands=cast(tuple[str, ...], contract["verification"]),
        generated_at=generated_at,
        outcome=cast(str, contract["outcome"]),
        context=cast(str, contract["context"]),
        likely_files=cast(tuple[str, ...], contract["likely_files"]),
        acceptance_criteria=cast(tuple[str, ...], contract["acceptance_criteria"]),
        stop_conditions=cast(tuple[str, ...], contract["stop_conditions"]),
        invariants=cast(tuple[str, ...], contract["invariants"]),
        review_gate=cast(str, contract["review_gate"]),
    )


def _brief_input(
    task: RunArtifactV1,
    spec_ref: str,
    context_ref: str,
    profile_ref: str | None,
    task_ref: str | None = None,
) -> WorkerBriefRenderInputV1:
    contract = _task_contract(task)
    return WorkerBriefRenderInputV1(
        task.artifact_id,
        cast(str, contract["heading_title"]),
        spec_ref,
        task_ref or f"tasks/{task.artifact_id}.md",
        context_ref,
        profile_ref,
        outcome=cast(str, contract["outcome"]),
        context=cast(str, contract["context"]),
        allowed_scope=cast(tuple[str, ...], contract["likely_files"]),
        forbidden_scope=cast(tuple[str, ...], contract["out_of_scope"]),
        invariants=cast(tuple[str, ...], contract["invariants"]),
        acceptance_criteria=cast(tuple[str, ...], contract["acceptance_criteria"]),
        verification=cast(tuple[str, ...], contract["verification"]),
        stop_conditions=cast(tuple[str, ...], contract["stop_conditions"]),
        review_gate=cast(str, contract["review_gate"]),
    )


def render_worker_profile(input: WorkerProfileRenderInputV1) -> bytes:
    generated = f"Generated: {input.generated_at}\n" if input.generated_at else ""
    stop_conditions = (
        _bullet(input.stop_conditions)
        if input.stop_conditions
        else ("- Stop and report when a required decision or verification cannot be completed.")
    )
    review_gate = input.review_gate or (
        "A separate reviewer must confirm the diff remains within this contract "
        "before dispatch is closed."
    )
    contract = ""
    if (
        input.outcome
        or input.context
        or input.likely_files
        or input.acceptance_criteria
        or input.verification_commands
    ):
        contract = f"""
## Task Contract (verbatim)

### Goal / Outcome

{input.outcome}

### Context

{input.context}

### Allowed Scope

{_bullet(input.likely_files)}

### Forbidden Scope

{_bullet(input.out_of_scope)}

### Invariants

{_bullet(input.invariants)}

### Acceptance Criteria

{_bullet(input.acceptance_criteria)}

### Verification

{_bullet(input.verification_commands)}

If a verification command cannot run, state why and what remains unverified.

### Stop Conditions

{stop_conditions}

### Independent Semantic Review Gate

{review_gate}
"""
    text = (
        f"""# Worker Profile: {input.profile_id}

{generated}Source task: `{input.task_ref}`

## Reuse Trigger

{input.reuse_trigger}

## Mandate

{input.mandate}

## Scope

In scope:

{_bullet(input.scope)}

Out of scope:

{_bullet(input.out_of_scope)}

## Required Context

Read first:

{_bullet(input.allowed_inspect)}

Current-doc research:

- {input.research_note}

## Allowed Files

May edit:

{_bullet(input.allowed_edit)}

May inspect:

{_bullet(input.allowed_inspect)}

Do not edit:

- Files outside the bead's approved scope.
- Files reserved by another active worker.

## Forbidden Decisions

Stop and report back before deciding:

{_bullet(input.forbidden_decisions)}

## Quality Gates

{_bullet(input.quality_gates)}

## Verification

Run:

```bash
{chr(10).join(input.verification_commands)}
```

If verification cannot run, report the reason and the narrowest manual check completed.

## Report Format

Return:

- files changed;
- behavior implemented;
- verification results;
- profile constraints followed;
- unresolved questions;
- recommended next worker or review step.
"""
        + contract
    )
    return text.encode("utf-8")


def render_worker_brief(input: WorkerBriefRenderInputV1) -> bytes:
    profile_read = (
        f"- `{input.profile_ref}`"
        if input.profile_ref
        else "- No reusable worker profile linked for this bead."
    )
    contract = ""
    stop_conditions = (
        _bullet(input.stop_conditions)
        if input.stop_conditions
        else ("- Stop and report when a required decision or verification cannot be completed.")
    )
    review_gate = input.review_gate or (
        "A separate reviewer must confirm the diff remains within this contract "
        "before dispatch is closed."
    )
    if (
        input.outcome
        or input.context
        or input.allowed_scope
        or input.acceptance_criteria
        or input.verification
    ):
        contract = f"""

## Contract (verbatim)

### Goal / Outcome

{input.outcome}

### Context

{input.context}

### Allowed Scope

{_bullet(input.allowed_scope)}

### Forbidden Scope

{_bullet(input.forbidden_scope)}

### Invariants

{_bullet(input.invariants)}

### Acceptance Criteria

{_bullet(input.acceptance_criteria)}

### Verification

{_bullet(input.verification)}

### Stop Conditions

{stop_conditions}

### Independent Semantic Review Gate

{review_gate}
"""
    text = (
        f"""# Worker Brief: {input.task_id}

## Assignment

Implement `{input.task_id}` from `{input.spec_ref}`.

Task title: {input.task_title}

## Read First

- `{input.spec_ref}`
- `{input.task_ref}`
- `{input.context_ref}`
{profile_read}
- Project `AGENTS.md` files that apply to touched paths.

## Scope

You may change:

- Paths listed in the task bead after inspecting the codebase.

Do not change:

- Unrelated modules.
- Files reserved by another active worker.
- Public behavior outside the task acceptance criteria.

## Requirements

- Claim or reserve the bead before editing when `br`/Agent Mail are active.
- Inspect existing patterns before editing.
- Keep changes small and reviewable.
- Add or update tests for changed behavior.
- Update docs if public behavior changes.
- If a material decision is needed, create a decision request with
  `flywheel-runner.py decision-request` instead of burying the question in chat.

## Verification

Run the commands listed in the task bead. If a command cannot run, explain why.

## Report Back

Return:

- files changed;
- behavior implemented;
- verification results;
- unresolved questions;
- follow-up beads needed.
"""
        + contract
    )
    return text.encode("utf-8")


def _bullet(items: tuple[str, ...]) -> str:
    return "\n".join(f"- {item}" for item in items) if items else "- <none>"


def _file(path: str, content: bytes) -> MaterializationFileV1:
    return MaterializationFileV1(path, base64.b64encode(content).decode("ascii"))


def _final_ref(run_id: str, relative_path: str) -> str:
    return f"docs/flywheel-runs/{run_id}/{relative_path}"


def plan_run(input: PromotedRunInputV1) -> MaterializationPlanV1:
    if input.schema_version != SCHEMA_VERSION:
        _fail("invalid_schema_version")
    _validate_spec_body(input.spec.body)
    for adr in input.adrs:
        _validate_adr_body(adr.body.encode("utf-8"))
    if not input.context_body.strip() or input.context_body.strip().lower() in {"none", "<none>"}:
        _fail("invalid_context")
    for artifact in (input.spec, *input.adrs, *input.tasks):
        if _has_placeholder(artifact.body) or re.search(
            r"^Status:\s*Draft\s*$", artifact.body, re.MULTILINE | re.IGNORECASE
        ):
            _fail("invalid_artifact_body")
    task_graph = {task.artifact_id: task.depends_on for task in input.tasks}
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(task_id: str) -> None:
        if task_id in visiting:
            _fail("dependency_cycle")
        if task_id in visited:
            return
        visiting.add(task_id)
        for dependency in task_graph[task_id]:
            visit(dependency)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in task_graph:
        visit(task_id)
    spec_ref = "spec/feature-spec.md"
    context_ref = "context/context.md"
    spec_manifest_ref = _final_ref(input.run_id, spec_ref)
    context_manifest_ref = _final_ref(input.run_id, context_ref)
    files: list[MaterializationFileV1] = []
    manifest: dict[str, object] = {
        "artifacts": {"context": context_manifest_ref, "spec": spec_manifest_ref},
        "feature": {"slug": input.run_id, "title": input.feature_title},
        "phases": {},
        "run_id": input.run_id,
        "schema_version": SCHEMA_VERSION,
        "source_ref": input.source_ref,
    }
    manifest["artifacts"] = {
        **cast(dict[str, object], manifest["artifacts"]),
        "task_beads": tuple(
            _final_ref(input.run_id, f"tasks/{task.artifact_id}.md") for task in input.tasks
        ),
    }
    if input.adrs:
        manifest["artifacts"] = {
            **cast(dict[str, object], manifest["artifacts"]),
            "decisions": tuple(
                _final_ref(input.run_id, f"decisions/{item.artifact_id}.md") for item in input.adrs
            ),
        }
    manifest["artifacts"] = {
        **cast(dict[str, object], manifest["artifacts"]),
        "worker_briefs": tuple(
            _final_ref(input.run_id, f"briefs/{item.artifact_id}.md") for item in input.tasks
        ),
    }
    files.append(_file("manifest.json", canonical_json_bytes(cast(Any, manifest))))
    files.append(_file(context_ref, input.context_body.encode("utf-8")))
    files.append(_file(spec_ref, input.spec.body.encode("utf-8")))
    for adr in input.adrs:
        files.append(_file(f"decisions/{adr.artifact_id}.md", adr.body.encode("utf-8")))
    profile_refs: dict[str, str] = {}
    for task in input.tasks:
        contract = _task_contract(task)
        declared_depends = cast(tuple[str, ...] | None, contract["declared_depends"])
        if declared_depends is not None and declared_depends != task.depends_on:
            _fail("dependency_declaration_mismatch")
        if any(not _section(task.body, section) for section in _REQUIRED_TASK_SECTIONS):
            _fail("incomplete_task_contract")
        if _has_placeholder(task.body) or re.search(
            r"^Status:\s*Draft\s*$", task.body, re.MULTILINE | re.IGNORECASE
        ):
            _fail("invalid_task_body")
        directive = _section(task.body, "Worker Profile").splitlines()
        first = next(
            (
                line.strip()
                for line in directive
                if line.strip() and line.strip().lower() != "rationale:"
            ),
            "",
        )
        if first.lower() == "none needed":
            continue
        match = _PROFILE_RE.fullmatch(first)
        if match is None:
            _fail("unsupported_worker_profile_directive")
        profile_id = match.group(2)
        profile_alias = f"profiles/{profile_id}.md"
        profile_refs[task.artifact_id] = _final_ref(input.run_id, profile_alias)
        files.append(
            _file(
                profile_alias,
                render_worker_profile(
                    _profile_input(
                        task,
                        spec_manifest_ref,
                        context_manifest_ref,
                        task_ref=_final_ref(input.run_id, f"tasks/{task.artifact_id}.md"),
                    )
                ),
            )
        )
    manifest["artifacts"] = {
        **cast(dict[str, object], manifest["artifacts"]),
        "worker_profiles": profile_refs,
    }
    files[0] = _file("manifest.json", canonical_json_bytes(cast(Any, manifest)))
    for task in input.tasks:
        files.append(_file(f"tasks/{task.artifact_id}.md", task.body.encode("utf-8")))
    for task in input.tasks:
        files.append(
            _file(
                f"briefs/{task.artifact_id}.md",
                render_worker_brief(
                    _brief_input(
                        task,
                        spec_manifest_ref,
                        context_manifest_ref,
                        profile_refs.get(task.artifact_id),
                        task_ref=_final_ref(input.run_id, f"tasks/{task.artifact_id}.md"),
                    )
                ),
            )
        )
    if input.implementation_goal_json is not None:
        files.append(_file("implementation-goal.json", input.implementation_goal_json))
        manifest["artifacts"] = {
            **cast(dict[str, object], manifest["artifacts"]),
            "implementation_goal": _final_ref(input.run_id, "implementation-goal.json"),
        }
        files[0] = _file("manifest.json", canonical_json_bytes(cast(Any, manifest)))
    files.sort(key=lambda item: item.relative_path)
    return MaterializationPlanV1(SCHEMA_VERSION, input.run_id, tuple(files))


def _validate_materialization_plan(
    plan: MaterializationPlanV1, *, legacy_runner: bool
) -> tuple[ValidationFindingV1, ...]:
    findings: list[ValidationFindingV1] = []

    def add(severity: str, code: str, path: str | None, message: str) -> None:
        if len(findings) < MAX_FINDINGS:
            findings.append(ValidationFindingV1(SCHEMA_VERSION, severity, code, path, message))

    try:
        files = {item.relative_path: item.content for item in plan.files}
    except (MaterializationContractError, ValueError) as exc:
        add("error", "invalid-plan", None, str(exc))
        return tuple(findings)
    manifest_bytes = files.get("manifest.json")
    if manifest_bytes is None:
        add("error", "missing-manifest", None, "manifest.json is required")
        return tuple(findings)
    try:
        manifest = canonical_json_object(manifest_bytes)
    except (TypeError, ValueError, UnicodeDecodeError):
        add("error", "invalid-manifest", "manifest.json", "Manifest is not canonical JSON")
        return tuple(findings)
    if canonical_json_bytes(cast(Any, manifest)) != manifest_bytes:
        add("error", "noncanonical-manifest", "manifest.json", "Manifest bytes are not canonical")
    if not legacy_runner:
        allowed_manifest_keys = {
            "artifacts",
            "feature",
            "phases",
            "run_id",
            "schema_version",
            "source_ref",
        }
        for key in sorted(set(manifest) - allowed_manifest_keys):
            add(
                "error",
                "legacy-manifest-field",
                "manifest.json",
                f"Manifest field `{key}` is reserved for the runner adapter.",
            )
    if manifest.get("schema_version") != SCHEMA_VERSION or manifest.get("run_id") != plan.run_id:
        add(
            "error",
            "manifest-binding",
            "manifest.json",
            "Manifest schema or run binding is invalid",
        )
    refs = manifest.get("artifacts")
    if not isinstance(refs, Mapping):
        add("error", "manifest-artifacts", "manifest.json", "Manifest artifacts must be an object")
        return tuple(findings)
    project_prefix = f"docs/flywheel-runs/{plan.run_id}/"

    def ref_alias(value: object, key: str | None = None) -> str | None:
        if not isinstance(value, str):
            return None
        if value.startswith(project_prefix):
            return value[len(project_prefix) :]
        if key == "context":
            return "context/context.md"
        if key == "spec":
            return "spec/feature-spec.md"
        if key == "task_beads":
            return f"tasks/{value.rsplit('/', 1)[-1]}"
        if key == "worker_briefs":
            return f"briefs/{value.rsplit('/', 1)[-1]}"
        if key == "worker_profiles":
            return f"profiles/{value.rsplit('/', 1)[-1]}"
        if key == "decisions":
            return f"decisions/{value.rsplit('/', 1)[-1]}"
        if key == "implementation_goal":
            return "implementation-goal.json"
        # Legacy runner manifests use project-global paths.  The CLI adapter
        # maps those into this run-tree namespace before calling us.
        return value

    referenced: list[str] = []

    def record_ref(value: object, *, path: str, key: str | None = None) -> str | None:
        alias = ref_alias(value, key)
        if alias is None or not alias:
            add("error", "invalid-reference", path, "Manifest references must be non-empty strings")
            return None
        referenced.append(alias)
        return alias

    context_alias = record_ref(refs.get("context"), path="manifest.json", key="context")
    spec_alias = record_ref(refs.get("spec"), path="manifest.json", key="spec")
    for key in ("context", "spec"):
        ref = refs.get(key)
        alias = context_alias if key == "context" else spec_alias
        if alias is None or alias not in files:
            add(
                "error",
                "missing-artifact",
                "manifest.json",
                f"Manifest reference `{key}` is missing",
            )
        elif key == "context":
            context_text = files[alias].decode("utf-8", "replace")
            if not context_text.strip() or context_text.strip().lower() in {"none", "<none>"}:
                add("error", "invalid-context", alias, "Context must be non-empty.")
    for key in ("decisions", "task_beads", "worker_briefs"):
        values = refs.get(key, ())
        if not isinstance(values, list | tuple):
            add(
                "error", "manifest-artifacts", "manifest.json", f"Manifest `{key}` must be an array"
            )
            values = ()
        for ref in values:
            alias = record_ref(ref, path="manifest.json", key=key)
            if alias is None or alias not in files:
                add(
                    "error",
                    "missing-artifact",
                    "manifest.json",
                    f"Manifest reference `{ref}` is missing",
                )
    profiles = refs.get("worker_profiles", {})
    if not isinstance(profiles, Mapping):
        add(
            "error",
            "manifest-artifacts",
            "manifest.json",
            "Manifest worker_profiles must be an object",
        )
        profiles = {}
    for ref in profiles.values():
        alias = record_ref(ref, path="manifest.json", key="worker_profiles")
        if alias is None or alias not in files:
            add(
                "error",
                "missing-artifact",
                "manifest.json",
                f"Manifest profile reference `{ref}` is missing",
            )
    goal_ref = refs.get("implementation_goal")
    if goal_ref is not None:
        goal_alias = record_ref(goal_ref, path="manifest.json", key="implementation_goal")
        if goal_alias is None or goal_alias not in files:
            add(
                "error",
                "missing-artifact",
                "manifest.json",
                "Manifest implementation goal reference is missing",
            )
        elif goal_alias is not None:
            try:
                goal_object = canonical_json_object(files[goal_alias])
                if canonical_json_bytes(cast(Any, goal_object)) != files[goal_alias]:
                    raise ValueError("noncanonical_goal")
            except (TypeError, ValueError, UnicodeDecodeError) as exc:
                add("error", "invalid-goal", goal_alias, str(exc))
    task_refs = manifest.get("task_beads")
    if not isinstance(task_refs, list | tuple):
        task_refs = refs.get("task_beads", ())
    for ref in task_refs if isinstance(task_refs, list | tuple) else ():
        alias = ref_alias(ref, "task_beads")
        if alias not in files and isinstance(ref, str) and ref in files:
            alias = ref
        if alias is None or alias not in files:
            add(
                "error",
                "missing-task",
                "manifest.json",
                f"Manifest task reference `{ref}` is missing",
            )
    task_ref_values = task_refs if isinstance(task_refs, list | tuple) else ()
    all_task_ids = {
        alias.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        for ref in task_ref_values
        if (alias := ref_alias(ref, "task_beads")) is not None
        and alias in files
    }
    decision_values = refs.get("decisions", ())
    for decision_ref in decision_values if isinstance(decision_values, list | tuple) else ():
        decision_alias = ref_alias(decision_ref, "decisions")
        if decision_alias in files:
            try:
                _validate_adr_body(files[decision_alias])
            except MaterializationContractError as exc:
                add("error", "invalid-adr", decision_alias, str(exc))
    spec_ref = spec_alias or "spec/feature-spec.md"
    if spec_ref in files:
        spec_text = files[spec_ref].decode("utf-8", "replace")
        try:
            _validate_spec_body(spec_text)
        except MaterializationContractError as exc:
            add("error", "invalid-spec-contract", spec_ref, str(exc))
        questions = _section(spec_text, "Open Questions")
        if questions and not re.fullmatch(
            r"(?:-\s*)?(?:none|<none>)", questions.strip(), re.IGNORECASE
        ):
            add(
                "warning",
                "open-questions",
                spec_ref,
                "Spec has open questions; confirm they do not block implementation.",
            )
    task_aliases: list[str] = []
    dependency_graph: dict[str, tuple[str, ...]] = {}
    derived_profiles: dict[str, str] = {}
    normalized_titles: dict[str, str] = {}
    for ref in task_refs if isinstance(task_refs, list | tuple) else ():
        alias = ref_alias(ref, "task_beads")
        if alias not in files and isinstance(ref, str) and ref in files:
            alias = ref
        if alias is None or alias not in files:
            continue
        task_aliases.append(alias)
        text = files[alias].decode("utf-8", "replace")
        title_match = re.search(
            r"^# Task Bead:\s+[A-Za-z0-9][A-Za-z0-9._:@-]*(?:\s+(.+?))?\s*$", text, re.MULTILINE
        )
        title = title_match.group(1).strip() if title_match and title_match.group(1) else alias
        title_key = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
        if title_key in normalized_titles:
            add(
                "error",
                "duplicate-task",
                alias,
                f"Task title duplicates `{normalized_titles[title_key]}` after normalization.",
            )
        else:
            normalized_titles[title_key] = alias
        for section in _REQUIRED_TASK_SECTIONS:
            content = _section(text, section)
            if not content:
                add(
                    "error",
                    "missing-task-section",
                    alias,
                    f"Task section `{section}` is missing or empty",
                )
            elif _has_placeholder(content):
                add(
                    "error",
                    "task-placeholder",
                    alias,
                    f"Task section `{section}` contains placeholder text",
                )
        try:
            artifact_id = alias.rsplit("/", 1)[-1].rsplit(".", 1)[0]
            task_artifact = RunArtifactV1("task", artifact_id, text, ())
            contract = _task_contract(task_artifact, strict=True)
        except (MaterializationContractError, ValueError) as exc:
            add("error", "invalid-task-contract", alias, str(exc))
            for section in _REQUIRED_TASK_SECTIONS:
                if not _section(text, section):
                    add(
                        "error",
                        "missing-task-section",
                        alias,
                        f"Task section `{section}` is missing or empty",
                    )
            continue
        for file_hint in cast(tuple[str, ...], contract["likely_files"]):
            if "unrelated" in file_hint.lower() or "**" in file_hint:
                add(
                    "warning",
                    "broad-file-scope",
                    alias,
                    "Task file scope may be too broad for safe worker dispatch.",
                )
        action, profile_id = _profile_directive(_section(text, "Worker Profile"))
        if action == "invalid" or (action == "reuse" and not legacy_runner):
            add(
                "error",
                "unsupported-worker-profile",
                alias,
                "Worker Profile must be `create <id>` or `none needed`",
            )
        elif action in {"create", "reuse"} and profile_id and (action == "create" or legacy_runner):
            derived_profiles[alias.rsplit("/", 1)[-1].rsplit(".", 1)[0]] = (
                f"profiles/{profile_id}.md"
            )
        # A generated runner task carries an explicit dependency declaration;
        # when present, the pure validator enforces the dispatch contract.
        declared = cast(tuple[str, ...] | None, contract["declared_depends"])
        if declared is not None:
            if cast(str, contract["fresh_context_fit"]) != "yes":
                add(
                    "error",
                    "fresh-context-overflow",
                    alias,
                    "Fresh Context Fit must be exactly `yes`.",
                )
            if cast(str, contract["slice_strategy"]).splitlines()[0].strip().lower() not in {
                "tracer-bullet",
                "prefactor",
                "expand",
                "migrate",
                "contract",
            }:
                add(
                    "error",
                    "unknown-slice-strategy",
                    alias,
                    "Slice Strategy is not an approved strategy.",
                )
            if tuple(declared) != tuple(dict.fromkeys(declared)):
                add("error", "duplicate-dependency", alias, "Dependencies must be unique.")
            task_id = alias.rsplit("/", 1)[-1].rsplit(".", 1)[0]
            dependency_graph[task_id] = declared
            task_ids = all_task_ids
            br_ids = set()
            br_values = manifest.get("br_beads", {}) if legacy_runner else {}
            if isinstance(br_values, Mapping):
                br_ids = {item for item in br_values.values() if isinstance(item, str) and item}
            for dep in declared:
                if dep not in task_ids and dep not in br_ids:
                    add(
                        "error",
                        "unknown-dependency",
                        alias,
                        f"Dependency `{dep}` is not a linked task.",
                    )

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(task_id: str) -> None:
        if task_id in visiting:
            add("error", "dependency-cycle", "task graph", "Dependency cycle detected.")
            return
        if task_id in visited:
            return
        visiting.add(task_id)
        for dependency in dependency_graph.get(task_id, ()):
            if dependency in dependency_graph:
                visit(dependency)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in dependency_graph:
        visit(task_id)

    # Every task has exactly one brief; create directives have exactly one
    # profile while none-needed directives have none.  Also reject hidden,
    # swapped, deleted, or outside files by enforcing the exact ref set.
    brief_values = refs.get("worker_briefs", ())
    brief_aliases = (
        [ref_alias(item, "worker_briefs") for item in brief_values]
        if isinstance(brief_values, list | tuple)
        else []
    )
    profile_aliases = [ref_alias(item, "worker_profiles") for item in profiles.values()]
    expected_profile_aliases = set(derived_profiles.values())
    actual_profile_aliases = {item for item in profile_aliases if item}
    if actual_profile_aliases != expected_profile_aliases:
        add(
            "error",
            "profile-set-mismatch",
            "manifest.json",
            "Manifest profiles must exactly match create-task profiles.",
        )
    if context_alias != "context/context.md":
        add("error", "context-binding", "manifest.json", "Context must use context/context.md.")
    if spec_alias != "spec/feature-spec.md":
        add("error", "spec-binding", "manifest.json", "Spec must use spec/feature-spec.md.")
    decision_refs = refs.get("decisions", ())
    for _index, item in enumerate(decision_refs if isinstance(decision_refs, list | tuple) else ()):
        alias = ref_alias(item, "decisions")
        if alias != f"decisions/{str(item).rsplit('/', 1)[-1]}":
            add(
                "error",
                "decision-binding",
                "manifest.json",
                "Decision reference has an invalid role path.",
            )
    for alias in task_aliases:
        task_id = alias.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        if alias != f"tasks/{task_id}.md":
            add("error", "task-binding", alias, "Task reference has an invalid role path.")
    for alias in brief_aliases:
        if alias is None or not alias.startswith("briefs/") or not alias.endswith(".md"):
            add(
                "error",
                "brief-binding",
                "manifest.json",
                "Brief reference has an invalid role path.",
            )
    for alias in profile_aliases:
        if alias is None or not alias.startswith("profiles/") or not alias.endswith(".md"):
            add(
                "error",
                "profile-binding",
                "manifest.json",
                "Profile reference has an invalid role path.",
            )
    if (
        goal_ref is not None
        and ref_alias(goal_ref, "implementation_goal") != "implementation-goal.json"
    ):
        add("error", "goal-binding", "manifest.json", "Goal reference has an invalid role path.")
    expected_refs = {"manifest.json", *task_aliases}
    expected_refs.update(item for item in (context_alias, spec_alias) if item)
    expected_refs.update(item for item in brief_aliases if item)
    expected_refs.update(item for item in profile_aliases if item)
    decision_values = refs.get("decisions", ())
    decision_items = (
        cast(list[object] | tuple[object, ...], decision_values)
        if isinstance(decision_values, list | tuple)
        else ()
    )
    for decision_item in decision_items:
        alias = ref_alias(decision_item, "decisions")
        if alias:
            expected_refs.add(alias)
    if goal_ref is not None:
        alias = ref_alias(goal_ref, "implementation_goal")
        if alias:
            expected_refs.add(alias)
    actual_refs = set(files)
    for unreferenced in sorted(actual_refs - expected_refs):
        add("error", "unreferenced-file", unreferenced, "File is not referenced by the manifest.")
    for missing_ref in sorted(expected_refs - actual_refs):
        add(
            "error",
            "missing-artifact",
            "manifest.json",
            f"Manifest reference `{missing_ref}` is missing",
        )
    if len(referenced) != len(set(referenced)):
        add("error", "duplicate-reference", "manifest.json", "Manifest references must be unique.")
    if len(task_aliases) != len(brief_aliases) or len(
        {item for item in brief_aliases if item}
    ) != len(brief_aliases):
        add(
            "error",
            "brief-count-mismatch",
            "manifest.json",
            "Exactly one worker brief is required per task.",
        )
    for task_alias in task_aliases:
        task_id = task_alias.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        if f"briefs/{task_id}.md" not in brief_aliases:
            add(
                "error",
                "brief-binding",
                task_alias,
                "Task must bind exactly one same-id worker brief.",
            )
        try:
            contract = _task_contract(
                RunArtifactV1("task", task_id, files[task_alias].decode("utf-8", "replace"), ())
            )
            action, profile_id = _profile_directive(cast(str, contract["worker_profile"]))
            expected_profile = (
                f"profiles/{profile_id}.md"
                if action in {"create", "reuse"} and profile_id
                else None
            )
            # Pure plans key profiles by task id; the historical CLI manifest
            # keys them by reusable profile id.  Both names must resolve to the
            # exact expected file, never merely to any existing profile.
            profile_for_task = profiles.get(task_id)
            if profile_for_task is None and profile_id:
                profile_for_task = profiles.get(profile_id)
            if (
                action in {"create", "reuse"}
                and ref_alias(profile_for_task, "worker_profiles") != expected_profile
            ):
                add(
                    "error",
                    "profile-binding",
                    task_alias,
                    "Profile task binding is missing or points at the wrong file.",
                )
            if action == "none" and profile_for_task is not None:
                add(
                    "error",
                    "unexpected-profile",
                    task_alias,
                    "none-needed task must not bind a profile.",
                )
            if action in {"create", "reuse"} and profile_id and profile_for_task is not None:
                profile_alias = ref_alias(profile_for_task, "worker_profiles")
                brief_alias = f"briefs/{task_id}.md"
                if profile_alias in files and brief_alias in files:
                    if legacy_runner:
                        try:
                            _validate_closed_profile(files[profile_alias], profile_id)
                            brief_text = files[brief_alias].decode("utf-8", "strict")
                            legacy_profile_ref = f"docs/worker-profiles/{profile_id}.md"
                            if (
                                str(profile_for_task) not in brief_text
                                and legacy_profile_ref not in brief_text
                            ):
                                _fail("brief_profile_binding")
                        except (MaterializationContractError, UnicodeDecodeError) as exc:
                            add("error", "invalid-worker-artifact", brief_alias, str(exc))
                    else:
                        spec_manifest_ref = cast(str, refs.get("spec"))
                        context_manifest_ref = cast(str, refs.get("context"))
                        task_manifest_ref = f"{project_prefix}{task_alias}"
                        expected_profile_bytes = render_worker_profile(
                            _profile_input(
                                RunArtifactV1(
                                    "task", task_id, files[task_alias].decode("utf-8"), ()
                                ),
                                spec_manifest_ref,
                                context_manifest_ref,
                                task_ref=task_manifest_ref,
                            )
                        )
                        expected_brief_bytes = render_worker_brief(
                            _brief_input(
                                RunArtifactV1(
                                    "task", task_id, files[task_alias].decode("utf-8"), ()
                                ),
                                spec_manifest_ref,
                                context_manifest_ref,
                                cast(str, profile_for_task),
                                task_ref=task_manifest_ref,
                            )
                        )
                        if files[profile_alias] != expected_profile_bytes:
                            add(
                                "error",
                                "profile-content-mismatch",
                                profile_alias,
                                "Profile bytes do not match the linked task contract.",
                            )
                        if files[brief_alias] != expected_brief_bytes:
                            add(
                                "error",
                                "brief-content-mismatch",
                                brief_alias,
                                "Brief bytes do not match the linked task contract.",
                            )
            elif action == "none" and f"briefs/{task_id}.md" in files:
                if legacy_runner:
                    try:
                        files[f"briefs/{task_id}.md"].decode("utf-8", "strict")
                    except UnicodeDecodeError:
                        add(
                            "error",
                            "invalid-worker-artifact",
                            f"briefs/{task_id}.md",
                            "Brief is not strict UTF-8.",
                        )
                else:
                    spec_manifest_ref = cast(str, refs.get("spec"))
                    context_manifest_ref = cast(str, refs.get("context"))
                    task_manifest_ref = f"{project_prefix}{task_alias}"
                    expected_brief_bytes = render_worker_brief(
                        _brief_input(
                            RunArtifactV1("task", task_id, files[task_alias].decode("utf-8"), ()),
                            spec_manifest_ref,
                            context_manifest_ref,
                            None,
                            task_ref=task_manifest_ref,
                        )
                    )
                    if files[f"briefs/{task_id}.md"] != expected_brief_bytes:
                        add(
                            "error",
                            "brief-content-mismatch",
                            f"briefs/{task_id}.md",
                            "Brief bytes do not match the linked task contract.",
                        )
        except (MaterializationContractError, ValueError) as exc:
            add("error", "invalid-task-contract", task_alias, str(exc))
    return tuple(findings)


def validate_materialization_plan(plan: MaterializationPlanV1) -> tuple[ValidationFindingV1, ...]:
    """Validate a self-contained public materialization plan."""
    return _validate_materialization_plan(plan, legacy_runner=False)


def _validate_legacy_runner_plan(
    plan: MaterializationPlanV1,
) -> tuple[ValidationFindingV1, ...]:
    """Validate a runner-adapted plan through the trusted CLI boundary."""
    return _validate_materialization_plan(plan, legacy_runner=True)


__all__ = [
    "MaterializationContractError",
    "MaterializationCorruptionError",
    "MaterializationFileV1",
    "MaterializationPlanV1",
    "PromotedRunInputV1",
    "RunArtifactV1",
    "ValidationFindingV1",
    "WorkerBriefRenderInputV1",
    "WorkerProfileRenderInputV1",
    "plan_run",
    "render_worker_brief",
    "render_worker_profile",
    "validate_materialization_plan",
]
