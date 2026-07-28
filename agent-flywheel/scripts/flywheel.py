#!/usr/bin/env python3
"""Local control CLI for the internal agent flywheel.

This CLI intentionally uses the file-based artifact layout. It gives the
orchestrator a stable local surface before br/bv/Agent Mail are installed and
continues to be useful as a lightweight inspector after those tools are added.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = ROOT / "sandbox" / "sample-flow"
LOCAL_BIN = str(Path.home() / ".local" / "bin")


@dataclass
class Task:
    id: str
    title: str
    status: str
    priority: str
    type: str
    depends_on: str
    worker_profile: str
    path: str


@dataclass
class DecisionRequest:
    id: str
    bead: str
    status: str
    severity: str
    decision_type: str
    path: str


@dataclass
class WorkerProfile:
    id: str
    path: str


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def line_value(text: str, label: str, default: str = "") -> str:
    match = re.search(rf"^\s*{re.escape(label)}:\s*(.+?)\s*$", text, re.MULTILINE)
    return match.group(1).strip() if match else default


def heading_title(text: str, prefix: str) -> tuple[str, str]:
    match = re.search(rf"^\s*# {re.escape(prefix)}:\s+(\S+)\s*(.*?)\s*$", text, re.MULTILINE)
    if not match:
        return "", ""
    return match.group(1).strip(), match.group(2).strip()


def section(text: str, title: str) -> str:
    match = re.search(
        rf"^\s*## {re.escape(title)}\s*\n(?P<body>.*?)(?=^\s*## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    return match.group("body").strip() if match else ""


def project_path(project: str | None) -> Path:
    if not project:
        return DEFAULT_PROJECT
    path = Path(project)
    if not path.is_absolute():
        path = ROOT / path
    return path


def iter_markdown(base: Path, subdir: str) -> Iterable[Path]:
    directory = base / "docs" / subdir
    if not directory.exists():
        return []
    return sorted(directory.rglob("*.md"))


def parse_tasks(base: Path) -> list[Task]:
    tasks: list[Task] = []
    for path in iter_markdown(base, "tasks"):
        text = read(path)
        task_id, title = heading_title(text, "Task Bead")
        worker_profile = section(text, "Worker Profile").splitlines()[0].strip() if section(text, "Worker Profile") else ""
        tasks.append(
            Task(
                id=task_id,
                title=title,
                status=line_value(text, "Status"),
                priority=line_value(text, "Priority"),
                type=line_value(text, "Type"),
                depends_on=line_value(text, "Depends On", "none"),
                worker_profile=worker_profile,
                path=rel(path),
            )
        )
    return tasks


def parse_decisions(base: Path) -> list[DecisionRequest]:
    decisions: list[DecisionRequest] = []
    for path in iter_markdown(base, "decision-requests"):
        text = read(path)
        decision_id, _ = heading_title(text, "Decision Request")
        decisions.append(
            DecisionRequest(
                id=decision_id,
                bead=line_value(text, "Bead"),
                status=line_value(text, "Status"),
                severity=section(text, "Severity").splitlines()[0].strip() if section(text, "Severity") else "",
                decision_type=section(text, "Decision Type").splitlines()[0].strip() if section(text, "Decision Type") else "",
                path=rel(path),
            )
        )
    return decisions


def parse_profiles(base: Path) -> list[WorkerProfile]:
    profiles: list[WorkerProfile] = []
    for path in iter_markdown(base, "worker-profiles"):
        text = read(path)
        profile_id, _ = heading_title(text, "Worker Profile")
        profiles.append(WorkerProfile(id=profile_id, path=rel(path)))
    return profiles


def ready_tasks(tasks: list[Task]) -> list[Task]:
    done = {task.id for task in tasks if task.status.lower() == "done"}
    ready: list[Task] = []
    for task in tasks:
        if task.status.lower() not in {"ready", "open"}:
            continue
        deps = [dep.strip() for dep in task.depends_on.split(",") if dep.strip() and dep.strip().lower() != "none"]
        if all(dep in done for dep in deps):
            ready.append(task)
    return ready


def doctor(base: Path) -> tuple[list[str], dict[str, object]]:
    problems: list[str] = []
    tasks = parse_tasks(base)
    decisions = parse_decisions(base)
    profiles = parse_profiles(base)
    task_ids = {task.id for task in tasks}
    profile_ids = {profile.id for profile in profiles}

    if not tasks:
        problems.append("no tasks found")
    for task in tasks:
        if not task.id:
            problems.append(f"task id missing in {task.path}")
        if not task.status:
            problems.append(f"task status missing in {task.path}")
        if not task.priority:
            problems.append(f"task priority missing in {task.path}")
        if not task.worker_profile:
            problems.append(f"worker profile decision missing in {task.path}")
        profile_match = re.search(r"`([^`]+)`", task.worker_profile)
        if profile_match and task.worker_profile.startswith("reuse") and profile_match.group(1) not in profile_ids:
            problems.append(f"task {task.id} reuses missing profile {profile_match.group(1)}")

    for decision in decisions:
        if not decision.id:
            problems.append(f"decision id missing in {decision.path}")
        if decision.bead not in task_ids:
            problems.append(f"decision {decision.id} references missing bead {decision.bead}")
        if decision.severity not in {"blocking", "important", "optional"}:
            problems.append(f"decision {decision.id} has invalid severity {decision.severity!r}")
        if not decision.decision_type:
            problems.append(f"decision type missing in {decision.path}")

    report = {
        "project": rel(base) if base.is_relative_to(ROOT) else str(base),
        "tasks": len(tasks),
        "ready_tasks": len(ready_tasks(tasks)),
        "decision_requests": len(decisions),
        "worker_profiles": len(profiles),
        "core_tools": {cmd: bool(shutil.which(cmd, path=f"{LOCAL_BIN}:{os.environ.get('PATH', '')}")) for cmd in ["br", "bv", "mcp-agent-mail", "am"]},
        "problems": problems,
    }
    return problems, report


def print_data(data: object, as_json: bool) -> None:
    if as_json:
        print(json.dumps(data, indent=2, sort_keys=True))
        return
    if isinstance(data, list):
        for item in data:
            if hasattr(item, "__dataclass_fields__"):
                print(json.dumps(asdict(item), sort_keys=True))
            else:
                print(item)
    else:
        print(json.dumps(data, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect local flywheel artifacts")
    parser.add_argument("--project", help="project artifact root, default sandbox/sample-flow")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ["status", "tasks", "ready", "decisions", "profiles", "doctor"]:
        command_parser = sub.add_parser(command)
        command_parser.add_argument("--json", action="store_true", help="emit JSON")

    args = parser.parse_args()
    base = project_path(args.project)

    if args.command == "status":
        problems, report = doctor(base)
        print_data(report, args.json)
        return 1 if problems else 0
    if args.command == "tasks":
        print_data([asdict(task) for task in parse_tasks(base)], args.json)
        return 0
    if args.command == "ready":
        print_data([asdict(task) for task in ready_tasks(parse_tasks(base))], args.json)
        return 0
    if args.command == "decisions":
        print_data([asdict(decision) for decision in parse_decisions(base)], args.json)
        return 0
    if args.command == "profiles":
        print_data([asdict(profile) for profile in parse_profiles(base)], args.json)
        return 0
    if args.command == "doctor":
        problems, report = doctor(base)
        print_data(report, args.json)
        return 1 if problems else 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
