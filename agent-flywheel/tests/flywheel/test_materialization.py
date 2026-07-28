from __future__ import annotations

import base64
import json

import pytest

from study_agent_devkit.flywheel.materialization import (
    MaterializationContractError,
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


def _input(*, task_body: str = TASK_BODY, goal: bytes | None = None) -> PromotedRunInputV1:
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
    adr = RunArtifactV1("adr", "adr-001", "# ADR-001\n\nStatus: Accepted\n", ())
    task = RunArtifactV1("task", "lesson-worker", task_body, ())
    return PromotedRunInputV1(
        1,
        "run-001",
        "Lesson worker",
        "docs/specs/lesson.md",
        "# Context\n",
        spec,
        (adr,),
        (task,),
        goal,
    )


def test_all_codecs_round_trip_and_preserve_exact_bodies() -> None:
    value = _input(goal=b'{"authorized":true}')
    assert PromotedRunInputV1.from_bytes(value.to_bytes()) == value
    plan = plan_run(value)
    assert MaterializationPlanV1.from_bytes(plan.to_bytes()) == plan
    assert validate_materialization_plan(plan) == ()
    contents = {item.relative_path: item.content for item in plan.files}
    assert contents["tasks/lesson-worker.md"].decode() == TASK_BODY
    assert contents["decisions/adr-001.md"].startswith(b"# ADR-001")
    assert json.loads(contents["manifest.json"])["artifacts"]["worker_profiles"] == {
        "lesson-worker": "docs/flywheel-runs/run-001/profiles/lesson-worker.md"
    }


def test_plan_contains_self_contained_manifest_refs_and_optional_goal() -> None:
    plan = plan_run(_input(goal=b'{"goal":"authorized_not_started"}'))
    paths = {item.relative_path for item in plan.files}
    assert paths == {
        "briefs/lesson-worker.md",
        "context/context.md",
        "decisions/adr-001.md",
        "implementation-goal.json",
        "manifest.json",
        "profiles/lesson-worker.md",
        "spec/feature-spec.md",
        "tasks/lesson-worker.md",
    }
    manifest = json.loads(
        next(item.content for item in plan.files if item.relative_path == "manifest.json")
    )
    assert manifest["artifacts"]["implementation_goal"] == (
        "docs/flywheel-runs/run-001/implementation-goal.json"
    )
    assert validate_materialization_plan(plan) == ()


@pytest.mark.parametrize(
    "path",
    ["", "/absolute", "../escape", "a/../b", "a\\b", "a//b", "a/./b", "a\x00b"],
)
def test_paths_are_run_tree_relative(path: str) -> None:
    with pytest.raises(MaterializationContractError):
        MaterializationFileV1(path, base64.b64encode(b"x").decode())


def test_casefold_collisions_and_boolean_schema_are_rejected() -> None:
    first = MaterializationFileV1("A.md", base64.b64encode(b"a").decode())
    second = MaterializationFileV1("a.md", base64.b64encode(b"b").decode())
    with pytest.raises(MaterializationContractError):
        MaterializationPlanV1(1, "run-001", (first, second))
    payload = json.loads(MaterializationPlanV1(1, "run-001", (first,)).to_bytes())
    payload["schema_version"] = True
    with pytest.raises(ValueError):
        MaterializationPlanV1.from_bytes(
            json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
        )


@pytest.mark.parametrize(
    "body, expected",
    [
        (TASK_BODY.replace("## Context", "## Context\n\nTODO", 1), "invalid_artifact_body"),
        (
            TASK_BODY.replace("create `lesson-worker`", "reuse `lesson-worker`"),
            "unsupported_worker_profile_directive",
        ),
        (TASK_BODY.replace("## Verification", "## Missing", 1), "incomplete_task_contract"),
    ],
)
def test_plan_rejects_unsafe_task_contracts(body: str, expected: str) -> None:
    with pytest.raises(MaterializationContractError, match=expected):
        plan_run(_input(task_body=body))


def test_dependency_unknown_and_cycle_are_rejected() -> None:
    spec = RunArtifactV1(
        "spec",
        "spec-1",
        """# Feature Spec

Status: Approved

## Grilling Evidence

- Approved review.

## Goal

Goal.

## Problem

Problem.

## In Scope

- Scope.

## Out of Scope

- UI.

## Acceptance Criteria

- [ ] Works.

## Verification

- pytest
""",
        (),
    )
    task_a = RunArtifactV1(
        "task",
        "a",
        TASK_BODY.replace("lesson-worker", "a").replace("Depends On: none", "Depends On: missing"),
        ("missing",),
    )
    with pytest.raises(MaterializationContractError, match="unknown_dependency"):
        PromotedRunInputV1(1, "run-001", "x", "docs/spec.md", "ctx", spec, (), (task_a,))
