from __future__ import annotations

import base64
import json
from collections.abc import Callable

import pytest

import study_agent_devkit.flywheel.materialization as materialization
from study_agent_devkit.flywheel.materialization import (
    MaterializationContractError,
    MaterializationCorruptionError,
    MaterializationFileV1,
    MaterializationPlanV1,
    PromotedRunInputV1,
    RunArtifactV1,
    ValidationFindingV1,
    plan_run,
)


def _canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def _file_payload(content: bytes = b"x") -> dict[str, str]:
    return {
        "content_b64": base64.b64encode(content).decode("ascii"),
        "relative_path": "one.txt",
    }


def _task_body(task_id: str = "task-a") -> str:
    return f"""# Task Bead: {task_id} A bounded task

Status: Approved
Depends On: none

## Outcome

Implement {task_id}.

## Slice Strategy

tracer-bullet
Fresh Context Fit: yes

## Spec Coverage

- The approved spec covers {task_id}.

## Grilling Evidence

- Independent review approved the slice.

## Worker Profile

create `{task_id}`

## Context

Use only the linked context pack.

## What To Do

- Implement the bounded behavior.

## Likely Files / Packages

- `src/{task_id}.py`

## Acceptance Criteria

- [ ] {task_id} produces the documented result.

## Verification

- `pytest -q tests/{task_id}`

## Out Of Scope

- Product UI and provider integrations.
"""


def _promoted(tasks: tuple[RunArtifactV1, ...] | None = None) -> PromotedRunInputV1:
    spec = RunArtifactV1(
        "spec",
        "feature-spec",
        """# Feature

Status: Approved

## Grilling Evidence

- Approved review.

## Goal

Feature goal.

## Problem

Feature problem.

## In Scope

- Feature behavior.

## Out of Scope

- Product UI.

## Acceptance Criteria

- [ ] Feature is bounded.

## Verification

- pytest -q tests/feature
""",
        (),
    )
    return PromotedRunInputV1(
        1,
        "run-001",
        "Feature",
        "docs/specs/feature.md",
        "# Context\n",
        spec,
        (),
        tasks or (RunArtifactV1("task", "task-a", _task_body(), ()),),
    )


def test_oversized_payload_is_rejected_before_json_decode(monkeypatch: pytest.MonkeyPatch) -> None:
    def fail_decode(_: bytes) -> object:
        raise AssertionError("oversized input must not reach JSON decoding")

    monkeypatch.setattr(materialization, "canonical_json_object", fail_decode)
    with pytest.raises(MaterializationCorruptionError, match="invalid_payload"):
        MaterializationPlanV1.from_bytes(b"{" + b"x" * (materialization.MAX_PLAN_BYTES + 1))


@pytest.mark.parametrize(
    ("codec", "payload"),
    [
        (MaterializationFileV1.from_bytes, {**_file_payload(), "hash": "0" * 64}),
        (MaterializationFileV1.from_bytes, {"content_b64": 1, "relative_path": "one.txt"}),
        (MaterializationFileV1.from_bytes, {"content_b64": "eA", "relative_path": "one.txt"}),
        (
            MaterializationPlanV1.from_bytes,
            {"files": [_file_payload()], "run_id": "run-001", "schema_version": True},
        ),
        (
            MaterializationPlanV1.from_bytes,
            {
                "files": [_file_payload()],
                "run_id": "run-001",
                "schema_version": 1,
                "hash": "0" * 64,
            },
        ),
    ],
)
def test_codecs_reject_types_unknown_fields_boolean_schema_and_noncanonical_base64(
    codec: Callable[[bytes], object], payload: dict[str, object]
) -> None:
    with pytest.raises(MaterializationCorruptionError):
        codec(_canonical(payload))


def test_artifact_codec_rejects_unknown_hash_and_boolean_schema_fields() -> None:
    artifact = RunArtifactV1("task", "task-a", "body", ()).to_bytes()
    payload = json.loads(artifact)
    payload["hash"] = "0" * 64
    with pytest.raises(MaterializationCorruptionError):
        RunArtifactV1.from_bytes(_canonical(payload))
    payload = json.loads(artifact)
    payload["kind"] = True
    with pytest.raises(MaterializationCorruptionError):
        RunArtifactV1.from_bytes(_canonical(payload))


@pytest.mark.parametrize("path", ["../escape", "a/../b", "a\\b", "a\x00b", "A/./b"])
def test_paths_reject_traversal_backslash_nul_and_dot_segments(path: str) -> None:
    with pytest.raises(MaterializationContractError):
        MaterializationFileV1(path, base64.b64encode(b"x").decode("ascii"))


def test_file_and_plan_bounds_are_closed() -> None:
    exact = MaterializationFileV1(
        "exact.bin", base64.b64encode(b"x" * materialization.MAX_FILE_BYTES).decode("ascii")
    )
    assert len(exact.content) == materialization.MAX_FILE_BYTES
    with pytest.raises(MaterializationContractError, match="oversized_file"):
        MaterializationFileV1(
            "too-large.bin",
            base64.b64encode(b"x" * (materialization.MAX_FILE_BYTES + 1)).decode("ascii"),
        )

    files = tuple(
        MaterializationFileV1(f"file-{index:03d}.txt", base64.b64encode(b"x").decode("ascii"))
        for index in range(materialization.MAX_FILES)
    )
    assert MaterializationPlanV1(1, "run-001", files).files == files
    with pytest.raises(MaterializationContractError, match="invalid_materialization_files"):
        MaterializationPlanV1(1, "run-001", (*files, MaterializationFileV1("overflow.txt", "eA==")))


def test_validation_findings_are_bounded_and_finding_fields_are_closed() -> None:
    assert ValidationFindingV1(1, "error", "valid-code", None, "message").to_bytes()
    with pytest.raises(MaterializationContractError, match="invalid_finding_code"):
        ValidationFindingV1(
            1, "error", "x" * (materialization.MAX_FINDING_CODE + 1), None, "message"
        )

    refs = {
        "context": "context/context.md",
        "spec": "spec/feature-spec.md",
        "task_beads": [f"missing/{i}.md" for i in range(300)],
    }
    manifest = MaterializationFileV1(
        "manifest.json",
        base64.b64encode(
            _canonical({"artifacts": refs, "run_id": "run-001", "schema_version": 1})
        ).decode("ascii"),
    )
    plan = MaterializationPlanV1(1, "run-001", (manifest,))
    findings = materialization.validate_materialization_plan(plan)
    assert len(findings) == materialization.MAX_FINDINGS


def test_promoted_input_preserves_exact_artifact_bytes_and_plan_is_deterministic() -> None:
    body = (
        "# Task Bead: task-a\n\nStatus: Approved\nDepends On: none\n\n"
        + _task_body().split("\n\n", 2)[2]
    )
    task = RunArtifactV1("task", "task-a", body, ())
    promoted = _promoted((task,))
    first = plan_run(promoted)
    second = plan_run(promoted)
    assert first.to_bytes() == second.to_bytes()
    content = {item.relative_path: item.content for item in first.files}
    assert content["tasks/task-a.md"] == body.encode("utf-8")


def test_pure_validator_does_not_read_from_filesystem(monkeypatch: pytest.MonkeyPatch) -> None:
    def fail_read(*_: object, **__: object) -> bytes:
        raise AssertionError("validator must remain in-memory")

    monkeypatch.setattr("pathlib.Path.read_bytes", fail_read)
    monkeypatch.setattr("pathlib.Path.read_text", fail_read)
    plan = plan_run(_promoted())
    assert materialization.validate_materialization_plan(plan) == ()
