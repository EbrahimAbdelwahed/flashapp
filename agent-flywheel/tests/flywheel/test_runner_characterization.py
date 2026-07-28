from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def test_direct_runner_profile_and_brief_commands_consume_shared_renderers(tmp_path: Path) -> None:
    root = Path(__file__).parents[2]
    project = tmp_path / "project"
    subprocess.run(
        [
            sys.executable,
            str(root / "scripts/flywheel-runner.py"),
            "intake",
            "--project",
            str(project),
            "--run-id",
            "run-001",
            "--feature",
            "Feature",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(root / "scripts/flywheel-runner.py"),
            "context",
            "--project",
            str(project),
            "--run-id",
            "run-001",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(root / "scripts/flywheel-runner.py"),
            "spec",
            "--project",
            str(project),
            "--run-id",
            "run-001",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
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
    subprocess.run(
        [
            sys.executable,
            str(root / "scripts/flywheel-runner.py"),
            "beads",
            "--project",
            str(project),
            "--run-id",
            "run-001",
            "--beads-json",
            str(tasks),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(root / "scripts/flywheel-runner.py"),
            "profiles",
            "--project",
            str(project),
            "--run-id",
            "run-001",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(root / "scripts/flywheel-runner.py"),
            "briefs",
            "--project",
            str(project),
            "--run-id",
            "run-001",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert (project / "docs/worker-profiles/lesson-worker.md").is_file()
    brief = (project / "docs/worker-briefs/run-001/lesson-worker.md").read_text()
    assert "docs/worker-profiles/lesson-worker.md" in brief
