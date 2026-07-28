from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path

from study_agent_devkit.flywheel.materialization import (
    WorkerBriefRenderInputV1,
    WorkerProfileRenderInputV1,
    render_worker_brief,
    render_worker_profile,
)


def _run(root: Path, project: Path, *args: str) -> None:
    environment = {key: value for key, value in os.environ.items() if key != "PYTHONPATH"}
    subprocess.run(
        [sys.executable, str(root / "scripts" / "flywheel-runner.py"), *args],
        cwd=project,
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )


def test_direct_repo_runner_uses_import_fallback_and_shared_renderers_byte_for_byte(
    tmp_path: Path,
) -> None:
    root = Path(__file__).parents[3]
    project = tmp_path / "project"
    project.mkdir()
    run_args = ("--project", str(project), "--run-id", "run-001")
    _run(root, project, "intake", *run_args, "--feature", "Feature")
    _run(root, project, "context", *run_args)
    _run(root, project, "spec", *run_args)

    tasks = project / "tasks.json"
    tasks.write_text(
        json.dumps(
            {
                "tasks": [
                    {
                        "id": "lesson-worker",
                        "title": "Lesson worker",
                        "worker_profile": "create `lesson-worker`",
                        "context": "context",
                        "what_to_do": ["do"],
                        "files": ["src/x.py"],
                        "acceptance_criteria": ["works"],
                        "verification": ["true"],
                        "out_of_scope": ["ui"],
                        "spec_coverage": ["coverage"],
                        "grilling_evidence": ["approved"],
                    }
                ]
            }
        )
    )
    _run(root, project, "beads", *run_args, "--beads-json", str(tasks))
    _run(root, project, "profiles", *run_args)
    _run(root, project, "briefs", *run_args)

    manifest = json.loads(
        (project / "docs/flywheel-runs/run-001/manifest.json").read_text(encoding="utf-8")
    )
    task_ref = manifest["artifacts"]["task_beads"][0]
    spec_ref = manifest["artifacts"]["spec"]
    context_ref = manifest["artifacts"]["context"]
    profile_ref = manifest["artifacts"]["worker_profiles"]["lesson-worker"]
    expected_profile = render_worker_profile(
        WorkerProfileRenderInputV1(
            profile_id="lesson-worker",
            task_id="lesson-worker",
            task_ref=task_ref,
            task_title="lesson-worker Lesson worker",
            spec_ref=spec_ref,
            context_ref=context_ref,
            reuse_trigger=(
                "Use this worker when a bead has the same implementation shape as "
                "`lesson-worker Lesson worker`."
            ),
            mandate=(
                "Complete recurring work shaped like `lesson-worker` without redesigning "
                "the feature."
            ),
            scope=(
                "Implement the scoped task behavior described by the linked bead and worker brief.",
            ),
            out_of_scope=(
                "Unrelated refactors.",
                "Changing public behavior outside the task acceptance criteria.",
                "Making product, architecture, prompt-policy, or data-model decisions "
                "reserved for the orchestrator.",
            ),
            allowed_inspect=(
                f"`{spec_ref}`",
                f"`{context_ref}`",
                f"`{task_ref}`",
                "applicable `AGENTS.md` files",
            ),
            research_note="not needed",
            allowed_edit=("src/x.py",),
            forbidden_decisions=(
                "architecture boundaries outside the task bead",
                "product behavior not covered by acceptance criteria",
                "new dependencies or provider choices",
                "data model or persistence changes not specified by the orchestrator",
            ),
            quality_gates=(
                "Change stays within the task file/package scope.",
                "Acceptance criteria are implemented or explicitly reported as blocked.",
                "Verification commands from the task bead are run or a concrete reason "
                "is reported.",
                "Acceptance criteria from the bead remain the source of truth:",
                "  - works",
            ),
            verification_commands=("`true`: expected to pass or produce documented output",),
            generated_at=dt.date.today().isoformat(),
        )
    )
    expected_brief = render_worker_brief(
        WorkerBriefRenderInputV1(
            task_id="lesson-worker",
            task_title="lesson-worker Lesson worker",
            spec_ref=spec_ref,
            task_ref=task_ref,
            context_ref=context_ref,
            profile_ref=profile_ref,
        )
    )
    assert (project / "docs/worker-profiles/lesson-worker.md").read_bytes() == expected_profile
    assert (project / "docs/worker-briefs/run-001/lesson-worker.md").read_bytes() == expected_brief
    assert (
        "If verification cannot run, report the reason and the narrowest manual check completed."
        in expected_profile.decode("utf-8")
    )
