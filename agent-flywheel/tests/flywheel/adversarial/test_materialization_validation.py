from __future__ import annotations

import base64
import json
from typing import cast

import pytest

import study_agent_devkit.flywheel.materialization as materialization
from study_agent_devkit.flywheel.materialization import (
    MaterializationFileV1,
    MaterializationPlanV1,
    PromotedRunInputV1,
    RunArtifactV1,
    plan_run,
    validate_materialization_plan,
)

TASK_BODY = """# Task Bead: lesson-worker Build lesson worker

Status: Approved
Depends On: none

## Outcome

Build the bounded lesson worker.

## Slice Strategy

tracer-bullet
Fresh Context Fit: yes

## Spec Coverage

- Worker behavior is grounded in the approved spec.

## Grilling Evidence

- Approved architecture review.

## Worker Profile

create `lesson-worker`

Rationale:

The lesson worker shape recurs across study workflows.

## Context

Use the approved context pack and no ambient files.

## What To Do

- Implement the bounded lesson worker.

## Likely Files / Packages

- `src/study_agent/lesson.py`

## Acceptance Criteria

- [ ] Worker behavior is deterministic at the boundary.

## Verification

- `pytest -q tests/lesson`

## Out Of Scope

- Product UI and provider SDKs.
"""


def _input(task_body: str = TASK_BODY) -> PromotedRunInputV1:
    spec = RunArtifactV1(
        "spec",
        "lesson-spec",
        """# Feature Spec: Lesson

Status: Approved

## Grilling Evidence

- Approved review.

## Goal

Lesson worker goal.

## Problem

Lesson worker problem.

## In Scope

- Lesson worker behavior.

## Out of Scope

- Product UI.

## Acceptance Criteria

- [ ] Lesson worker is bounded.

## Verification

- pytest -q tests/lesson
""",
        (),
    )
    task = RunArtifactV1("task", "lesson-worker", task_body, ())
    return PromotedRunInputV1(
        1, "run-001", "Lesson worker", "docs/specs/lesson.md", "# Context\n", spec, (), (task,)
    )


def _plan_with_manifest(
    manifest: dict[str, object], *extra: MaterializationFileV1
) -> MaterializationPlanV1:
    manifest_file = MaterializationFileV1(
        "manifest.json",
        base64.b64encode(
            json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
        ).decode("ascii"),
    )
    files = tuple(
        sorted(
            (manifest_file, *(item for item in extra if item.relative_path != "manifest.json")),
            key=lambda item: item.relative_path,
        )
    )
    return MaterializationPlanV1(1, "run-001", files)


def _valid_plan() -> MaterializationPlanV1:
    return plan_run(_input())


def _manifest(plan: MaterializationPlanV1) -> dict[str, object]:
    return cast(
        dict[str, object],
        json.loads(
            next(item.content for item in plan.files if item.relative_path == "manifest.json")
        ),
    )


def _replace_file(plan: MaterializationPlanV1, path: str, body: bytes) -> MaterializationPlanV1:
    replacement = MaterializationFileV1(path, base64.b64encode(body).decode("ascii"))
    files = tuple(replacement if item.relative_path == path else item for item in plan.files)
    return MaterializationPlanV1(plan.schema_version, plan.run_id, files)


@pytest.mark.parametrize("heading", materialization._REQUIRED_TASK_SECTIONS)
def test_plan_rejects_each_missing_runner_task_heading(heading: str) -> None:
    body = TASK_BODY.replace(f"## {heading}", f"## Missing {heading}", 1)
    with pytest.raises(
        materialization.MaterializationContractError, match="incomplete_task_contract"
    ):
        plan_run(_input(body))


@pytest.mark.parametrize(
    ("body", "error"),
    [
        (TASK_BODY.replace("Status: Approved", "Status: Draft"), "invalid_artifact_body"),
        (TASK_BODY.replace("Build the bounded lesson worker.", "TODO", 1), "invalid_artifact_body"),
        (
            TASK_BODY.replace("create `lesson-worker`", "reuse `lesson-worker`"),
            "unsupported_worker_profile_directive",
        ),
        (
            TASK_BODY.replace("create `lesson-worker`", "create `bad/profile`"),
            "unsupported_worker_profile_directive",
        ),
        (
            TASK_BODY.replace("create `lesson-worker`", "create lesson-worker extra"),
            "unsupported_worker_profile_directive",
        ),
    ],
)
def test_plan_rejects_draft_placeholder_reuse_and_invalid_create_directives(
    body: str, error: str
) -> None:
    with pytest.raises(materialization.MaterializationContractError, match=error):
        plan_run(_input(body))


def test_run_artifact_rejects_duplicate_dependencies() -> None:
    with pytest.raises(materialization.MaterializationContractError, match="duplicate_dependency"):
        RunArtifactV1("task", "duplicate", TASK_BODY, ("same", "same"))


def test_public_validator_rejects_legacy_manifest_controls() -> None:
    original_plan = _valid_plan()
    original = _manifest(original_plan)
    files = tuple(item for item in original_plan.files if item.relative_path != "manifest.json")
    findings = validate_materialization_plan(
        _plan_with_manifest({**original, "_legacy_runner": True}, *files)
    )
    assert any(f.code == "legacy-manifest-field" for f in findings)


def test_legacy_adapter_accepts_br_ids_from_manifest_values_only() -> None:
    original_plan = _valid_plan()
    original = _manifest(original_plan)
    task_path = "tasks/lesson-worker.md"
    task = next(item.content for item in original_plan.files if item.relative_path == task_path)
    task = task.replace(b"Depends On: none", b"Depends On: BR-123")
    files = tuple(
        MaterializationFileV1(
            task_path,
            base64.b64encode(task).decode("ascii"),
        )
        if item.relative_path == task_path
        else item
        for item in original_plan.files
        if item.relative_path != "manifest.json"
    )
    legacy_manifest = {**original, "br_beads": {"lesson-worker": "BR-123"}}
    findings = materialization._validate_legacy_runner_plan(
        _plan_with_manifest(legacy_manifest, *files)
    )
    assert not any(f.code == "unknown-dependency" for f in findings)


def test_validator_binds_profile_and_brief_bytes_to_task_contract() -> None:
    plan = _valid_plan()
    profile_path = next(
        item.relative_path for item in plan.files if item.relative_path.startswith("profiles/")
    )
    brief_path = next(
        item.relative_path for item in plan.files if item.relative_path.startswith("briefs/")
    )
    profile = next(item.content for item in plan.files if item.relative_path == profile_path)
    brief = next(item.content for item in plan.files if item.relative_path == brief_path)
    assert any(
        finding.code == "profile-content-mismatch"
        for finding in validate_materialization_plan(
            _replace_file(plan, profile_path, profile + b"\n")
        )
    )
    assert any(
        finding.code == "brief-content-mismatch"
        for finding in validate_materialization_plan(_replace_file(plan, brief_path, brief + b"\n"))
    )


def test_validator_accepts_forward_nonlexical_acyclic_dependencies() -> None:
    base = _input()
    first = TASK_BODY.replace("lesson-worker Build lesson worker", "a-worker Alpha worker").replace(
        "create `lesson-worker`", "none needed"
    )
    later = TASK_BODY.replace("lesson-worker Build lesson worker", "z-worker Zeta worker").replace(
        "Depends On: none", "Depends On: a-worker"
    ).replace("create `lesson-worker`", "none needed")
    plan = plan_run(
        PromotedRunInputV1(
            1,
            "run-001",
            base.feature_title,
            base.source_ref,
            base.context_body,
            base.spec,
            (),
            (
                RunArtifactV1("task", "z-worker", later, ("a-worker",)),
                RunArtifactV1("task", "a-worker", first, ()),
            ),
        )
    )
    assert not validate_materialization_plan(plan)


def test_plan_rejects_draft_adr_body() -> None:
    adr = RunArtifactV1(
        "adr",
        "adr-001",
        "# ADR-001: Draft\n\nStatus: Draft\n\n## Decision\nPending.\n",
        (),
    )
    with pytest.raises(materialization.MaterializationContractError, match="invalid_adr_body"):
        plan_run(
            PromotedRunInputV1(
                1,
                "run-001",
                "Lesson worker",
                "docs/specs/lesson.md",
                "# Context\n",
                _input().spec,
                (adr,),
                _input().tasks,
            )
        )


def test_validator_reports_missing_context_and_manifest_references() -> None:
    original = _manifest(_valid_plan())
    artifacts = dict(cast(dict[str, object], original["artifacts"]))
    artifacts["context"] = "context/missing.md"
    plan = _plan_with_manifest({**original, "artifacts": artifacts})
    findings = validate_materialization_plan(plan)
    assert any(
        f.code == "missing-artifact" and f.relative_path == "manifest.json" for f in findings
    )


def test_validator_rejects_swapped_and_outside_manifest_references() -> None:
    original_plan = _valid_plan()
    original = _manifest(original_plan)
    artifacts = dict(cast(dict[str, object], original["artifacts"]))
    artifacts["spec"] = "tasks/lesson-worker.md"
    artifacts["task_beads"] = ("../outside.md",)
    swapped = _plan_with_manifest({**original, "artifacts": artifacts}, *original_plan.files[1:])
    findings = validate_materialization_plan(swapped)
    assert any(f.code in {"missing-task", "missing-artifact"} for f in findings)

    swapped_refs = dict(cast(dict[str, object], original["artifacts"]))
    swapped_refs["spec"] = "tasks/lesson-worker.md"
    swapped_refs["task_beads"] = ("spec/feature-spec.md",)
    swapped_only = _plan_with_manifest(
        {**original, "artifacts": swapped_refs}, *original_plan.files[1:]
    )
    assert any(
        f.code == "missing-task-section" for f in validate_materialization_plan(swapped_only)
    )


def test_profile_renderer_maps_goal_scope_invariants_and_verification_losslessly() -> None:
    plan = _valid_plan()
    profile = next(
        item.content.decode("utf-8")
        for item in plan.files
        if item.relative_path.startswith("profiles/")
    )
    brief = next(
        item.content.decode("utf-8")
        for item in plan.files
        if item.relative_path.startswith("briefs/")
    )
    assert "Build the bounded lesson worker." in profile
    assert "src/study_agent/lesson.py" in profile
    assert "Worker behavior is deterministic at the boundary." in profile
    assert "pytest -q tests/lesson" in profile
    assert "Product UI and provider SDKs." in profile
    assert "Build the bounded lesson worker." in brief
    assert "src/study_agent/lesson.py" in brief
    assert "Worker behavior is deterministic at the boundary." in brief
    assert "pytest -q tests/lesson" in brief
    assert "Product UI and provider SDKs." in brief


def test_dependency_unknown_and_cycle_are_rejected() -> None:
    task_a = RunArtifactV1(
        "task",
        "a",
        TASK_BODY.replace("lesson-worker", "a").replace("Depends On: none", "Depends On: b"),
        ("b",),
    )
    task_b = RunArtifactV1(
        "task",
        "b",
        TASK_BODY.replace("lesson-worker", "b").replace("Depends On: none", "Depends On: a"),
        ("a",),
    )
    with pytest.raises(materialization.MaterializationContractError, match="dependency_cycle"):
        plan_run(_input_for_tasks((task_a, task_b)))

    unknown = RunArtifactV1(
        "task",
        "a",
        TASK_BODY.replace("lesson-worker", "a").replace("Depends On: none", "Depends On: missing"),
        ("missing",),
    )
    with pytest.raises(materialization.MaterializationContractError, match="unknown_dependency"):
        _input_for_tasks((unknown,))


def _input_for_tasks(tasks: tuple[RunArtifactV1, ...]) -> PromotedRunInputV1:
    spec = RunArtifactV1(
        "spec",
        "lesson-spec",
        """# Feature Spec: Lesson

Status: Approved

## Grilling Evidence

- Approved review.

## Goal

Lesson worker goal.

## Problem

Lesson worker problem.

## In Scope

- Lesson worker behavior.

## Out of Scope

- Product UI.

## Acceptance Criteria

- [ ] Lesson worker is bounded.

## Verification

- pytest -q tests/lesson
""",
        (),
    )
    return PromotedRunInputV1(
        1, "run-001", "Lesson worker", "docs/specs/lesson.md", "# Context\n", spec, (), tasks
    )
