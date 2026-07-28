#!/usr/bin/env python3
"""Workflow runner for the internal study-agent flywheel.

The runner is intentionally deterministic: it creates and connects artifacts for
an orchestrator agent, but it does not pretend to replace the agent's judgment
or embed hidden LLM calls.
"""

from __future__ import annotations

import argparse
import base64
import dataclasses
import datetime as dt
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "scripts" / "flywheel-core.py"
sys.path.insert(0, str(ROOT / "src"))

from study_agent_devkit.flywheel.materialization import (  # noqa: E402
    MaterializationContractError,
    MaterializationCorruptionError,
    MaterializationFileV1,
    MaterializationPlanV1,
    WorkerBriefRenderInputV1,
    WorkerProfileRenderInputV1,
    render_worker_brief,
    render_worker_profile,
    _validate_legacy_runner_plan,
)
SCHEMA_VERSION = 1
TEXT_LIMIT = 20_000
COMMAND_OUTPUT_LIMIT = 12_000

RUNNER_COMMANDS: dict[str, dict[str, Any]] = {
    "commands": {
        "summary": "Print a machine-readable command manifest.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "doctor": {
        "summary": "Inspect runner dependencies and optional project state.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "plan": {
        "summary": "Print the recommended command sequence for a feature run.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "intake": {
        "summary": "Create the run manifest and intake artifact.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "context": {
        "summary": "Collect repo context for spec and worker planning.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "spec": {
        "summary": "Create an implementation-ready feature spec scaffold.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "beads": {
        "summary": "Materialize task beads from spec or task JSON.",
        "side_effects": ["local_write", "local_task_graph_write_optional"],
        "supports_dry_run": True,
        "output": "json",
    },
    "briefs": {
        "summary": "Generate worker briefs from task beads.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "profiles": {
        "summary": "Generate reusable worker profiles required by task beads.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "validate": {
        "summary": "Validate spec, task graph, profiles, briefs, decisions, and review readiness.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "dispatch": {
        "summary": "Prepare worker spawn packets for the orchestrator.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "decision-request": {
        "summary": "Create or resolve a structured decision request for a run or task.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "worker-report": {
        "summary": "Record a completed worker report for a dispatched task.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "review": {
        "summary": "Prepare a review report and optionally capture verification command results.",
        "side_effects": ["local_write", "executes_user_commands_optional"],
        "supports_dry_run": True,
        "output": "json",
    },
    "git-lane": {
        "summary": "Inspect or execute branch/stage/commit/push lane.",
        "side_effects": ["local_write", "git_write_optional", "remote_write_optional"],
        "supports_dry_run": True,
        "dangerous_flags": ["--execute", "--push", "--override-gates"],
        "output": "json",
    },
    "optimize": {
        "summary": "Generate workflow optimization proposals for this run.",
        "side_effects": ["local_write"],
        "supports_dry_run": True,
        "output": "json",
    },
    "pr-lane": {
        "summary": "Prepare or execute GitHub PR creation lane.",
        "side_effects": ["local_write", "network_write_optional", "remote_write_optional"],
        "supports_dry_run": True,
        "dangerous_flags": ["--execute", "--override-gates"],
        "output": "json",
    },
    "run": {
        "summary": "Run a sequenced orchestration lane until judgment or missing inputs are required.",
        "side_effects": ["local_write", "executes_user_commands_optional", "local_task_graph_write_optional"],
        "supports_dry_run": True,
        "output": "json",
    },
    "status": {
        "summary": "Show run status and missing phases.",
        "side_effects": ["read_only"],
        "output": "json",
    },
}


@dataclasses.dataclass(frozen=True)
class RunnerPaths:
    project: Path
    run_id: str

    @property
    def run_dir(self) -> Path:
        return self.project / "docs" / "flywheel-runs" / self.run_id

    @property
    def manifest(self) -> Path:
        return self.run_dir / "manifest.json"

    @property
    def specs_dir(self) -> Path:
        return self.project / "docs" / "specs"

    @property
    def tasks_dir(self) -> Path:
        return self.project / "docs" / "tasks" / self.run_id

    @property
    def briefs_dir(self) -> Path:
        return self.project / "docs" / "worker-briefs" / self.run_id

    @property
    def worker_profiles_dir(self) -> Path:
        return self.project / "docs" / "worker-profiles"

    @property
    def decision_requests_dir(self) -> Path:
        return self.project / "docs" / "decision-requests" / self.run_id

    @property
    def reviews_dir(self) -> Path:
        return self.project / "docs" / "reviews"

    @property
    def dispatch_dir(self) -> Path:
        return self.run_dir / "dispatch"


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def today() -> str:
    return dt.date.today().isoformat()


def project_path(value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve()
    return path


def slugify(value: str, fallback: str = "feature") -> str:
    lowered = value.lower()
    lowered = re.sub(r"[^a-z0-9]+", "-", lowered)
    lowered = lowered.strip("-")
    return lowered[:72] or fallback


def rel(path: Path, project: Path) -> str:
    try:
        return str(path.relative_to(project))
    except ValueError:
        return str(path)


def is_inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def read_text(path: Path, limit: int = TEXT_LIMIT) -> str:
    data = path.read_text(encoding="utf-8", errors="replace")
    if len(data) > limit:
        return data[:limit] + "\n\n[truncated]\n"
    return data


def write_text(path: Path, text: str, *, force: bool = False) -> None:
    if path.exists() and not force:
        raise SystemExit(f"Refusing to overwrite existing file without --force: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.{id(text)}.tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.{id(data)}.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def print_json(data: Any) -> None:
    print(json.dumps(data, indent=2, sort_keys=True))


def command(args: list[str], cwd: Path | None = None, check: bool = False) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if check and completed.returncode != 0:
        raise SystemExit(
            "Command failed:\n"
            + " ".join(shlex.quote(item) for item in args)
            + f"\nexit={completed.returncode}\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def shell_command(command_text: str, cwd: Path) -> dict[str, Any]:
    completed = subprocess.run(
        command_text,
        cwd=str(cwd),
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    return {
        "command": command_text,
        "exit_code": completed.returncode,
        "stdout": completed.stdout[-COMMAND_OUTPUT_LIMIT:],
        "stderr": completed.stderr[-COMMAND_OUTPUT_LIMIT:],
    }


def ensure_project_dirs(paths: RunnerPaths) -> None:
    for path in [
        paths.run_dir,
        paths.specs_dir,
        paths.tasks_dir,
        paths.briefs_dir,
        paths.worker_profiles_dir,
        paths.decision_requests_dir,
        paths.reviews_dir,
        paths.dispatch_dir,
    ]:
        path.mkdir(parents=True, exist_ok=True)


def latest_run_id(project: Path) -> str | None:
    root = project / "docs" / "flywheel-runs"
    if not root.exists():
        return None
    manifests = sorted(root.glob("*/manifest.json"), key=manifest_recency_key, reverse=True)
    if not manifests:
        return None
    return manifests[0].parent.name


def manifest_recency_key(path: Path) -> tuple[str, float]:
    try:
        data = load_json(path)
    except SystemExit:
        return "", path.stat().st_mtime
    created_at = str(data.get("created_at") or "")
    return created_at, path.stat().st_mtime


def resolve_run_id(project: Path, requested: str | None) -> str:
    if requested and requested != "latest":
        return requested
    run_id = latest_run_id(project)
    if not run_id:
        raise SystemExit("No flywheel run found. Start with `flywheel-runner.py intake ...`.")
    return run_id


def load_manifest(paths: RunnerPaths) -> dict[str, Any]:
    if not paths.manifest.exists():
        raise SystemExit(f"Run manifest not found: {paths.manifest}")
    data = load_json(paths.manifest)
    if data.get("schema_version") != SCHEMA_VERSION:
        raise SystemExit(f"Unsupported manifest schema in {paths.manifest}: {data.get('schema_version')}")
    return data


def save_manifest(paths: RunnerPaths, manifest: dict[str, Any]) -> None:
    manifest["updated_at"] = now_iso()
    save_json(paths.manifest, manifest)


def append_phase(manifest: dict[str, Any], phase: str, status: str, details: dict[str, Any]) -> None:
    manifest.setdefault("phases", {})[phase] = {
        "status": status,
        "updated_at": now_iso(),
        **details,
    }


def artifact_set(manifest: dict[str, Any], key: str, value: Any) -> None:
    manifest.setdefault("artifacts", {})[key] = value


def artifact_list_append(manifest: dict[str, Any], key: str, value: str) -> None:
    items = list(manifest.setdefault("artifacts", {}).get(key) or [])
    if value not in items:
        items.append(value)
    manifest["artifacts"][key] = items


def artifact_dict_set(manifest: dict[str, Any], key: str, item_key: str, value: str) -> None:
    items = dict(manifest.setdefault("artifacts", {}).get(key) or {})
    items[item_key] = value
    manifest["artifacts"][key] = items


def read_feature(args: argparse.Namespace) -> str:
    if args.feature and args.feature_file:
        raise SystemExit("Use either --feature or --feature-file, not both.")
    if args.feature_file:
        return read_text(project_path(args.feature_file), limit=80_000).strip()
    if args.feature:
        return args.feature.strip()
    raise SystemExit("Provide --feature or --feature-file.")


def default_run_id(title: str) -> str:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M")
    return f"{stamp}-{slugify(title)}"


def extract_title(feature: str, explicit: str | None = None) -> str:
    if explicit:
        return explicit.strip()
    first = next((line.strip("# ").strip() for line in feature.splitlines() if line.strip()), "")
    if len(first) > 90:
        first = first[:87].rstrip() + "..."
    return first or "Untitled feature"


def command_intake(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    feature = read_feature(args)
    title = extract_title(feature, args.title)
    run_id = args.run_id or default_run_id(title)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)

    intake_path = paths.run_dir / "intake.md"
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "project": str(project),
        "created_at": now_iso(),
        "updated_at": now_iso(),
        "feature": {
            "title": title,
            "slug": slugify(title),
            "raw": feature,
        },
        "artifacts": {},
        "phases": {},
        "br_beads": {},
    }
    text = f"""# Intake: {title}

Date: {today()}
Run ID: `{run_id}`
Owner: orchestrator
Project: `{project}`

## Raw Feature Request

{feature}

## Orchestrator Alignment Checklist

- [ ] Restate the intended user outcome.
- [ ] Identify product, architecture, prompt, RAG, eval, data, and UI surfaces.
- [ ] List irreversible or high-cost decisions that need user approval.
- [ ] List safe assumptions that can be made without blocking.
- [ ] Decide whether online research is needed before the spec.

## Initial Questions

- What is the narrowest valuable implementation slice?
- What should be explicitly out of scope for this run?
- What commands prove the implementation is done?
"""
    if args.dry_run:
        print_json({"run_id": run_id, "would_write": [rel(intake_path, project), rel(paths.manifest, project)]})
        return 0

    write_text(intake_path, text, force=args.force)
    artifact_set(manifest, "intake", rel(intake_path, project))
    append_phase(manifest, "intake", "complete", {"path": rel(intake_path, project)})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "manifest": rel(paths.manifest, project), "intake": rel(intake_path, project)})
    return 0


def list_candidate_files(project: Path) -> list[Path]:
    names = [
        "AGENTS.md",
        "README.md",
        "package.json",
        "pnpm-workspace.yaml",
        "tsconfig.base.json",
        "pyproject.toml",
        "Cargo.toml",
        "Makefile",
    ]
    candidates = [project / name for name in names if (project / name).is_file()]
    for dirname in ["docs", "apps", "packages", "src", "scripts"]:
        root = project / dirname
        if root.exists():
            for path in sorted(root.rglob("*")):
                if path.is_file() and path.name in {"README.md", "AGENTS.md"}:
                    candidates.append(path)
    return candidates


def run_rg(project: Path, query: str) -> dict[str, Any]:
    if not shutil.which("rg"):
        return {
            "query": query,
            "available": False,
            "exit_code": 127,
            "stdout": "",
            "stderr": "rg is not installed or not on PATH",
        }
    completed = command(["rg", "-n", "--hidden", "--glob", "!.git", query, str(project)], check=False)
    return {
        "query": query,
        "available": completed.returncode in {0, 1},
        "exit_code": completed.returncode,
        "stdout": completed.stdout[-COMMAND_OUTPUT_LIMIT:],
        "stderr": completed.stderr[-COMMAND_OUTPUT_LIMIT:],
    }


def command_context(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    manifest = load_manifest(paths)

    context_path = paths.run_dir / "context-pack.md"
    candidates = list_candidate_files(project)
    extra_files = []
    for item in args.file:
        path = project_path(item)
        if not path.is_file():
            raise SystemExit(f"Context file not found: {path}")
        if not is_inside(path, project) and not args.allow_external_file:
            raise SystemExit(f"Refusing to include external context file without --allow-external-file: {path}")
        extra_files.append(path)
    all_files = []
    seen: set[Path] = set()
    for path in [*candidates, *extra_files]:
        resolved = path.resolve()
        if resolved in seen or not resolved.is_file():
            continue
        seen.add(resolved)
        all_files.append(resolved)

    sections = [
        f"# Context Pack: {manifest['feature']['title']}",
        "",
        f"Date: {today()}",
        f"Run ID: `{run_id}`",
        f"Project: `{project}`",
        "",
        "## Purpose",
        "",
        "This pack gives the orchestrator and future workers enough repository context to create a precise spec and scoped task graph.",
        "",
        "## Files Read",
        "",
    ]
    if all_files:
        for path in all_files:
            sections.append(f"- `{rel(path, project)}`")
    else:
        sections.append("- No standard context files found.")

    for path in all_files:
        sections.extend(["", f"## `{rel(path, project)}`", "", "```text", read_text(path).rstrip(), "```"])

    if args.query:
        sections.extend(["", "## Search Results", ""])
        for query in args.query:
            result = run_rg(project, query)
            sections.extend(
                [
                    f"### `{query}`",
                    "",
                    f"exit_code: `{result['exit_code']}`",
                    "",
                    "```text",
                    (result["stdout"] or result["stderr"] or "no matches").rstrip(),
                    "```",
                    "",
                ]
            )

    sections.extend(
        [
            "",
            "## Orchestrator Notes",
            "",
            "- Convert rough requirements into explicit acceptance criteria before implementation.",
            "- Keep generated worker scopes narrow and file-bounded.",
            "- Use `br`/`bv` as durable task graph once beads are approved.",
        ]
    )
    if args.dry_run:
        print_json({"run_id": run_id, "would_write": rel(context_path, project), "files": [rel(item, project) for item in all_files]})
        return 0

    write_text(context_path, "\n".join(sections) + "\n", force=args.force)
    artifact_set(manifest, "context", rel(context_path, project))
    append_phase(manifest, "context", "complete", {"path": rel(context_path, project), "files_count": len(all_files)})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "context": rel(context_path, project), "files_count": len(all_files)})
    return 0


def command_spec(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    title = manifest["feature"]["title"]
    spec_path = paths.specs_dir / f"{manifest['feature']['slug']}.md"
    context_ref = manifest.get("artifacts", {}).get("context", "<run context pack>")
    intake_ref = manifest.get("artifacts", {}).get("intake", "<run intake>")
    spec = f"""# Feature Spec: {title}

Status: Draft
Owner: orchestrator
Date: {today()}
Run ID: `{run_id}`

## Grilling Evidence

- Session/artifact: <reference to completed grill-with-docs output>
- Decision state: <approved or blocked>
- ADR/glossary changes: <references or none>

## Goal

<State the concrete user or platform outcome.>

## Problem

<Explain the pain, limitation, or product gap this solves.>

## Source Inputs

- Intake: `{intake_ref}`
- Context pack: `{context_ref}`

## Users

- <Primary user>

## In Scope

- <Concrete behavior>

## Out of Scope

- <Explicit non-goal>

## User Stories

- As a <user>, I can <action>, so that <outcome>.

## Domain Model

Affected entities:

- `<Entity>`: <change or role>

## API / Interface Contract

```ts
// Draft public shape, if relevant.
```

## Prompt Behavior

- Prompt IDs affected:
- Course profile inputs:
- Output schema:
- Grounding requirements:
- Eval fixtures required:

## RAG / Source Grounding

- Required sources:
- Citation behavior:
- Unsupported-answer behavior:

## UX Notes

- Loading state:
- Empty state:
- Error state:
- Accessibility:

## Risks

- <Risk>

## Acceptance Criteria

- [ ] <Observable outcome>

## Verification

- Unit:
- Integration:
- Evals:
- Manual:

## Open Questions

- <Question>

## Task Beads

Provide task beads as either:

```text
- `<task-id>`: <title>
```

or materialize them with:

```bash
{rel(ROOT / "scripts" / "flywheel-runner.py", project)} beads --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --beads-json <tasks.json>
```
"""
    if args.dry_run:
        print_json({"run_id": run_id, "would_write": rel(spec_path, project)})
        return 0

    write_text(spec_path, spec, force=args.force)
    artifact_set(manifest, "spec", rel(spec_path, project))
    append_phase(manifest, "spec", "draft", {"path": rel(spec_path, project)})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "spec": rel(spec_path, project)})
    return 0


def normalize_priority(value: str | int | None) -> tuple[str, str]:
    if value is None:
        return "P2", "2"
    text = str(value).strip().upper()
    if text.startswith("P") and text[1:].isdigit():
        number = text[1:]
        return f"P{number}", number
    if text.isdigit():
        return f"P{text}", text
    return "P2", "2"


def load_beads(args: argparse.Namespace, manifest: dict[str, Any], project: Path) -> list[dict[str, Any]]:
    if args.beads_json:
        data = load_json(project_path(args.beads_json))
        tasks = data.get("tasks", data) if isinstance(data, dict) else data
        if not isinstance(tasks, list):
            raise SystemExit("--beads-json must contain a JSON array or an object with a `tasks` array.")
        return [normalize_task(item) for item in tasks]

    spec_ref = manifest.get("artifacts", {}).get("spec")
    if not spec_ref:
        raise SystemExit("No spec found in manifest. Run `spec` or provide --beads-json.")
    spec_path = project / spec_ref
    tasks = parse_tasks_from_spec(spec_path)
    if not tasks:
        raise SystemExit(
            "No task beads found in the spec. Add `- `<task-id>`: <title>` entries under `## Task Beads` "
            "or provide --beads-json."
        )
    return tasks


def normalize_task(item: Any) -> dict[str, Any]:
    if not isinstance(item, dict):
        raise SystemExit(f"Task entries must be objects, got: {item!r}")
    title = str(item.get("title") or "").strip()
    if not title:
        raise SystemExit(f"Task is missing title: {item!r}")
    local_id = str(item.get("id") or slugify(title)).strip()
    priority_label, br_priority = normalize_priority(item.get("priority"))
    depends_on = item.get("depends_on") or item.get("depends") or []
    if isinstance(depends_on, str):
        depends_on = [part.strip() for part in depends_on.split(",") if part.strip()]
    task = {
        "id": slugify(local_id, fallback="task"),
        "title": title,
        "type": str(item.get("type") or "task"),
        "priority": priority_label,
        "br_priority": br_priority,
        "depends_on": depends_on,
        "outcome": item.get("outcome") or "Define an independently observable end-to-end outcome before dispatch.",
        "slice_strategy": item.get("slice_strategy") or "tracer-bullet",
        "fresh_context_fit": item.get("fresh_context_fit") or "yes",
        "spec_coverage": listify(item.get("spec_coverage") or []),
        "grilling_evidence": listify(item.get("grilling_evidence") or []),
        "worker_profile": item.get("worker_profile") or "none needed",
        "worker_profile_rationale": item.get("worker_profile_rationale") or "No reusable specialization selected yet.",
        "context": item.get("context") or "Derived from the feature spec and context pack.",
        "what_to_do": listify(item.get("what_to_do") or item.get("steps") or ["Implement the scoped behavior described by this bead."]),
        "files": listify(item.get("files") or item.get("likely_files") or []),
        "acceptance_criteria": listify(item.get("acceptance_criteria") or ["Observable behavior satisfies the spec."]),
        "verification": listify(item.get("verification") or ["Run the narrowest relevant verification command."]),
        "out_of_scope": listify(item.get("out_of_scope") or ["Unrelated refactors."]),
    }
    return task


def listify(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return [str(value).strip()] if str(value).strip() else []


def parse_tasks_from_spec(spec_path: Path) -> list[dict[str, Any]]:
    text = read_text(spec_path, limit=120_000)
    in_section = False
    tasks: list[dict[str, Any]] = []
    for line in text.splitlines():
        if line.startswith("## "):
            in_section = line.strip().lower() == "## task beads"
            continue
        if not in_section:
            continue
        match = re.match(r"-\s+`?([a-zA-Z0-9_.-]+)`?\s*:\s*(.+)", line.strip())
        if match:
            tasks.append(normalize_task({"id": match.group(1), "title": match.group(2)}))
    return tasks


def task_markdown(task: dict[str, Any], spec_ref: str, run_id: str) -> str:
    files = task["files"] or ["`<path>`: define likely file boundary before launch"]
    return f"""# Task Bead: {task['id']} {task['title']}

Status: Open
Priority: {task['priority']}
Type: {task['type']}
Depends On: {", ".join(task['depends_on']) if task['depends_on'] else "none"}
Run ID: `{run_id}`
Spec: `{spec_ref}`

## Outcome

{task['outcome']}

## Slice Strategy

{task['slice_strategy']}

Fresh Context Fit: {task['fresh_context_fit']}

## Spec Coverage

{bullets(task['spec_coverage'])}

## Grilling Evidence

{bullets(task['grilling_evidence'])}

## Worker Profile

{task['worker_profile']}

Rationale:

{task['worker_profile_rationale']}

## Context

{task['context']}

## What To Do

{bullets(task['what_to_do'])}

## Likely Files / Packages

{bullets(files)}

## Acceptance Criteria

{checkboxes(task['acceptance_criteria'])}

## Verification

{bullets([f"`{item}`: expected to pass or produce documented output" for item in task['verification']])}

## Out Of Scope

{bullets(task['out_of_scope'])}

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
"""


def bullets(items: list[str]) -> str:
    return "\n".join(f"- {item}" for item in items) if items else "- <none>"


def checkboxes(items: list[str]) -> str:
    return "\n".join(f"- [ ] {item}" for item in items) if items else "- [ ] <observable result>"


def extract_section(text: str, heading: str) -> str:
    pattern = re.compile(rf"^## {re.escape(heading)}\s*$", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        return ""
    start = match.end()
    next_heading = re.search(r"^##\s+", text[start:], flags=re.MULTILINE)
    end = start + next_heading.start() if next_heading else len(text)
    return text[start:end].strip()


def has_placeholder(text: str) -> bool:
    placeholder_patterns = [
        r"<[^>\n]+>",
        r"\bTODO\b",
        r"\bTBD\b",
        r"\bFIXME\b",
        r"Draft public shape",
        r"Observable behavior satisfies the spec",
        r"Run the narrowest relevant verification command",
        r"Derived from the feature spec and context pack",
    ]
    return any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in placeholder_patterns)


def add_issue(issues: list[dict[str, Any]], severity: str, code: str, path: str, message: str) -> None:
    issues.append({"severity": severity, "code": code, "path": path, "message": message})


def validation_exit_code(issues: list[dict[str, Any]], fail_on_warnings: bool = False) -> int:
    if any(issue["severity"] == "error" for issue in issues):
        return 1
    if fail_on_warnings and any(issue["severity"] == "warning" for issue in issues):
        return 1
    return 0


def parse_depends_from_task(text: str) -> list[str]:
    match = re.search(r"^Depends On:\s*(.+)$", text, flags=re.MULTILINE)
    if not match:
        return []
    raw = match.group(1).strip()
    if raw.lower() in {"none", "<ids or none>"}:
        return []
    return [item.strip(" `") for item in raw.split(",") if item.strip()]


def parse_task_title(text: str, fallback: str) -> str:
    match = re.search(r"^# Task Bead:\s+(.+)$", text, flags=re.MULTILINE)
    return match.group(1).strip() if match else fallback


def dependency_cycle(graph: dict[str, list[str]]) -> list[str]:
    visiting: list[str] = []
    visited: set[str] = set()

    def visit(node: str) -> list[str]:
        if node in visiting:
            start = visiting.index(node)
            return [*visiting[start:], node]
        if node in visited:
            return []
        visiting.append(node)
        for dependency in graph.get(node, []):
            if dependency not in graph:
                continue
            cycle = visit(dependency)
            if cycle:
                return cycle
        visiting.pop()
        visited.add(node)
        return []

    for node in graph:
        cycle = visit(node)
        if cycle:
            return cycle
    return []


def parse_task_file_hints(text: str) -> list[str]:
    section = extract_section(text, "Likely Files / Packages")
    hints = []
    for line in section.splitlines():
        line = line.strip()
        if not line.startswith("- "):
            continue
        hints.append(line[2:].strip())
    return hints


def parse_worker_profile_directive(text: str) -> tuple[str, str | None]:
    section = extract_section(text, "Worker Profile")
    first_line = next((line.strip() for line in section.splitlines() if line.strip() and line.strip().lower() != "rationale:"), "")
    match = re.search(r"\b(create|reuse)\b\s+`?([a-zA-Z0-9_.-]+)`?", first_line, flags=re.IGNORECASE)
    if match:
        return match.group(1).lower(), slugify(match.group(2), fallback="worker-profile")
    if "none needed" in section.lower():
        return "none", None
    return "unspecified", None


def parse_task_list_section(text: str, heading: str) -> list[str]:
    section = extract_section(text, heading)
    items = []
    for line in section.splitlines():
        stripped = line.strip()
        if stripped.startswith("- [ ] "):
            items.append(stripped[6:].strip())
        elif stripped.startswith("- "):
            items.append(stripped[2:].strip())
    return [item for item in items if item and item != "<none>"]


def profile_ref_exists(project: Path, manifest: dict[str, Any], profile_id: str) -> bool:
    profile_refs = dict(manifest.get("artifacts", {}).get("worker_profiles") or {})
    ref = profile_refs.get(profile_id)
    if ref and (project / ref).exists():
        return True
    return (project / "docs" / "worker-profiles" / f"{profile_id}.md").exists()


def unresolved_decision_status(text: str) -> tuple[str, str]:
    status_match = re.search(r"^Status:\s*(.+)$", text, flags=re.MULTILINE)
    severity_match = re.search(r"^## Severity\s*\n\s*([a-zA-Z-]+)", text, flags=re.MULTILINE)
    status = status_match.group(1).strip().lower() if status_match else "open"
    severity = severity_match.group(1).strip().lower() if severity_match else "important"
    return status, severity


def profile_coverage(project: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    required: dict[str, list[str]] = {}
    missing: dict[str, list[str]] = {}
    for task_ref in manifest.get("artifacts", {}).get("task_beads") or []:
        task_path = project / task_ref
        if not task_path.exists():
            continue
        action, profile_id = parse_worker_profile_directive(read_text(task_path, limit=80_000))
        if action in {"create", "reuse"} and profile_id:
            required.setdefault(profile_id, []).append(task_ref)
            if not profile_ref_exists(project, manifest, profile_id):
                missing.setdefault(profile_id, []).append(task_ref)
    return {"required": required, "missing": missing, "ok": not missing}


def decision_summary(project: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    open_items = []
    resolved_items = []
    missing_items = []
    for decision_ref in manifest.get("artifacts", {}).get("decision_requests") or []:
        decision_path = project / decision_ref
        if not decision_path.exists():
            missing_items.append(decision_ref)
            continue
        status, severity = unresolved_decision_status(read_text(decision_path, limit=80_000))
        item = {"path": decision_ref, "status": status, "severity": severity}
        if status in {"resolved", "closed", "answered"}:
            resolved_items.append(item)
        else:
            open_items.append(item)
    return {
        "open": open_items,
        "resolved": resolved_items,
        "missing": missing_items,
        "blocking_open": [item for item in open_items if item["severity"] == "blocking"],
    }


def review_evidence_summary(project: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    artifacts = manifest.get("artifacts", {})
    review_ref = artifacts.get("review")
    results_ref = artifacts.get("review_command_results")
    summary: dict[str, Any] = {
        "ok": False,
        "review": review_ref or "",
        "results": results_ref or "",
        "commands_count": 0,
        "failed_commands": [],
        "missing": [],
        "placeholder_scaffold": False,
        "semantic_verdict": "missing",
    }

    if not review_ref:
        summary["missing"].append("review")
    else:
        review_path = project / review_ref
        if not review_path.exists():
            summary["missing"].append(review_ref)
        else:
            review_text = read_text(review_path, limit=80_000)
            summary["placeholder_scaffold"] = any(
                marker in review_text
                for marker in [
                    "<Fix>",
                    "<Gap>",
                    "<Note>",
                    "Blocked | Changes requested | Approved",
                    "- [ ] Review implemented changes",
                    "No commands executed.",
                ]
            )
            verdict_match = re.search(r"^Semantic verdict:\s*(.+)$", review_text, flags=re.MULTILINE | re.IGNORECASE)
            if verdict_match:
                summary["semantic_verdict"] = verdict_match.group(1).strip().lower()
            elif re.search(r"^## Verdict\s*\n\s*Approved\s*$", review_text, flags=re.MULTILINE | re.IGNORECASE):
                summary["semantic_verdict"] = "approved"
            else:
                summary["semantic_verdict"] = "missing"

    if not results_ref:
        summary["missing"].append("review_command_results")
    else:
        results_path = project / results_ref
        if not results_path.exists():
            summary["missing"].append(results_ref)
        else:
            results = load_json(results_path).get("results", [])
            summary["commands_count"] = len(results)
            summary["failed_commands"] = [item for item in results if int(item.get("exit_code", 1)) != 0]

    summary["ok"] = (
        not summary["missing"]
        and summary["commands_count"] > 0
        and not summary["failed_commands"]
        and not summary["placeholder_scaffold"]
        and summary["semantic_verdict"] == "approved"
    )
    return summary


def dispatched_task_ids(project: Path, manifest: dict[str, Any]) -> list[str]:
    dispatch_ref = manifest.get("artifacts", {}).get("worker_dispatch")
    if not dispatch_ref:
        return []
    dispatch_path = project / dispatch_ref
    if not dispatch_path.exists():
        return []
    packets = load_json(dispatch_path).get("packets", [])
    return sorted(str(packet.get("task_id")) for packet in packets if isinstance(packet, dict) and packet.get("task_id"))


def worker_report_status(text: str) -> str:
    match = re.search(r"^Status:\s*(.+)$", text, flags=re.MULTILINE)
    return match.group(1).strip().lower() if match else "missing"


def worker_report_summary(project: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    expected = sorted(Path(ref).stem for ref in manifest.get("artifacts", {}).get("task_beads") or [])
    report_refs = dict(manifest.get("artifacts", {}).get("worker_reports") or {})
    missing = []
    blocked = []
    statuses: dict[str, str] = {}
    for task_id in expected:
        ref = report_refs.get(task_id)
        if not ref:
            missing.append(task_id)
            continue
        report_path = project / ref
        if not report_path.exists():
            missing.append(task_id)
            continue
        report_text = read_text(report_path, limit=80_000)
        status = worker_report_status(report_text)
        statuses[task_id] = status
        if status not in {"complete", "completed", "done"} or any(
            marker in report_text
            for marker in [
                "No behavior summary provided.",
                "No verification result provided.",
            ]
        ):
            blocked.append(task_id)
    return {
        "ok": bool(expected) and not missing and not blocked,
        "expected": expected,
        "reports": report_refs,
        "missing": missing,
        "blocked": blocked,
        "statuses": statuses,
    }


def run_should_use_ready_only(project: Path, run_id: str) -> bool:
    paths = RunnerPaths(project=project, run_id=run_id)
    try:
        manifest = load_manifest(paths)
    except SystemExit:
        return False
    return bool(manifest.get("br_beads"))


def publication_gate_issues(project: Path, paths: RunnerPaths, manifest: dict[str, Any], *, require_git_lane: bool) -> list[str]:
    issues: list[str] = []
    validation_issues = validate_run(project, paths, manifest, stage="final")
    for issue in validation_issues:
        if issue["severity"] == "error":
            issues.append(f"{issue['code']} at {issue['path']}: {issue['message']}")

    profiles = profile_coverage(project, manifest)
    if not profiles["ok"]:
        issues.append(f"missing worker profiles: {sorted(profiles['missing'])}")

    decisions = decision_summary(project, manifest)
    if decisions["blocking_open"]:
        issues.append(f"open blocking decision requests: {[item['path'] for item in decisions['blocking_open']]}")
    if decisions["missing"]:
        issues.append(f"missing decision request files: {decisions['missing']}")

    review = review_evidence_summary(project, manifest)
    if not review["ok"]:
        issues.append("review evidence is incomplete or failing")

    if require_git_lane and not manifest.get("artifacts", {}).get("git_lane"):
        issues.append("git lane artifact is missing")

    return issues


def _materialization_plan_from_runner(
    project: Path, paths: RunnerPaths, manifest: dict[str, Any]
) -> MaterializationPlanV1:
    """Adapt the historical project-wide runner layout to the pure validator.

    The adapter owns filesystem reads and aliases global paths into the
    self-contained run tree.  The shared module remains unaware of the runner's
    directory layout and therefore cannot accidentally gain side effects.
    """
    artifacts = manifest.get("artifacts", {})
    run_id = paths.run_id
    prefix = f"docs/flywheel-runs/{run_id}/"
    aliases: dict[str, str] = {}
    contents: dict[str, bytes] = {}

    def alias_for(key: str, ref: str) -> str:
        path = Path(ref)
        stem = path.name
        if key == "context":
            return "context/context.md"
        if key == "spec":
            return "spec/feature-spec.md"
        if key == "task_beads":
            return f"tasks/{stem}"
        if key == "worker_briefs":
            return f"briefs/{stem}"
        if key == "worker_profiles":
            return f"profiles/{stem}"
        if key == "decisions":
            return f"decisions/{stem}"
        if key == "implementation_goal":
            return "implementation-goal.json"
        if ref.startswith(prefix):
            return ref[len(prefix) :]
        return ref

    def add(key: str, ref: object) -> str | None:
        if not isinstance(ref, str) or not ref:
            return None
        alias = alias_for(key, ref)
        path = project / ref
        if not path.is_file():
            return alias
        aliases[ref] = alias
        contents.setdefault(alias, path.read_bytes())
        return alias

    transformed: dict[str, Any] = dict(manifest)
    transformed["artifacts"] = dict(artifacts)
    for key in ("context", "spec"):
        ref = artifacts.get(key)
        alias = add(key, ref)
        if alias:
            transformed["artifacts"][key] = f"{prefix}{alias}"
    for key in ("decisions", "task_beads", "worker_briefs"):
        values = artifacts.get(key) or []
        if not isinstance(values, list | tuple):
            transformed["artifacts"][key] = values
            continue
        transformed["artifacts"][key] = [
            f"{prefix}{alias}"
            for value in values
            if (alias := add(key, value)) is not None
        ]
    profile_values = artifacts.get("worker_profiles") or {}
    if isinstance(profile_values, dict):
        transformed["artifacts"]["worker_profiles"] = {
            task_id: f"{prefix}{alias}"
            for task_id, value in profile_values.items()
            if (alias := add("worker_profiles", value)) is not None
        }
    goal = artifacts.get("implementation_goal")
    if goal:
        alias = add("implementation_goal", goal)
        if alias:
            transformed["artifacts"]["implementation_goal"] = f"{prefix}{alias}"

    manifest_bytes = json.dumps(
        transformed, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode("utf-8")
    contents["manifest.json"] = manifest_bytes
    files = tuple(
        MaterializationFileV1(path, base64.b64encode(body).decode("ascii"))
        for path, body in sorted(contents.items())
    )
    return MaterializationPlanV1(1, run_id, files)


def shared_materialization_issues(
    project: Path, paths: RunnerPaths, manifest: dict[str, Any], *, stage: str
) -> list[dict[str, Any]]:
    if stage not in {"dispatch", "final"}:
        return []
    try:
        plan = _materialization_plan_from_runner(project, paths, manifest)
        findings = _validate_legacy_runner_plan(plan)
    except (MaterializationContractError, MaterializationCorruptionError, OSError, ValueError) as exc:
        return [{"severity": "error", "code": "materialization-plan", "path": "manifest", "message": str(exc)}]
    return [
        {"severity": item.severity, "code": item.code, "path": item.relative_path or "manifest", "message": item.message}
        for item in findings
    ]


def _validate_dispatch_cli_specific(
    project: Path, paths: RunnerPaths, manifest: dict[str, Any], stage: str
) -> list[dict[str, Any]]:
    """Validate dispatch/final concerns owned only by the CLI control plane."""
    issues = shared_materialization_issues(project, paths, manifest, stage=stage)
    for decision_ref in manifest.get("artifacts", {}).get("decision_requests") or []:
        decision_path = project / decision_ref
        if not decision_path.exists():
            add_issue(issues, "error", "missing-decision-request", decision_ref, "Decision request file does not exist.")
            continue
        status, severity = unresolved_decision_status(read_text(decision_path, limit=80_000))
        if status in {"resolved", "closed", "answered"}:
            continue
        if severity == "blocking":
            add_issue(issues, "error", "blocking-decision-open", decision_ref, "Blocking decision request is still open.")
        elif severity == "important":
            add_issue(issues, "warning", "important-decision-open", decision_ref, "Important decision request is still open.")

    if stage == "final":
        review = review_evidence_summary(project, manifest)
        if review["missing"]:
            add_issue(issues, "error", "missing-review-evidence", "manifest", f"Review evidence is missing: {review['missing']}")
        elif review["commands_count"] == 0:
            add_issue(issues, "error", "review-no-commands", review["results"], "Review captured no verification commands.")
        if review["failed_commands"]:
            for item in review["failed_commands"]:
                add_issue(issues, "error", "review-command-failed", review["results"], f"Review command failed: {item.get('command')}")
        if review["placeholder_scaffold"]:
            add_issue(issues, "error", "review-placeholder", review["review"], "Review report still contains placeholder scaffold markers.")
        if review["semantic_verdict"] != "approved":
            add_issue(issues, "error", "semantic-review-not-approved", review["review"] or "manifest", "Semantic code-quality-governor review is not approved.")

        worker_reports = worker_report_summary(project, manifest)
        if not worker_reports["expected"]:
            add_issue(issues, "error", "missing-worker-dispatch", "manifest", "No dispatched worker packets were found for publication validation.")
        if worker_reports["missing"]:
            add_issue(issues, "error", "missing-worker-report", "manifest", f"Worker reports are missing for task(s): {worker_reports['missing']}")
        if worker_reports["blocked"]:
            add_issue(issues, "error", "worker-report-not-complete", "manifest", f"Worker reports are not complete for task(s): {worker_reports['blocked']}")
    return issues


def validate_run(project: Path, paths: RunnerPaths, manifest: dict[str, Any], stage: str = "auto") -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    artifacts = manifest.get("artifacts", {})
    if stage == "auto":
        if not artifacts.get("task_beads"):
            stage = "spec"
        elif artifacts.get("worker_dispatch") and artifacts.get("worker_reports") and artifacts.get("review"):
            stage = "final"
        else:
            stage = "dispatch"

    if stage in {"dispatch", "final"}:
        return _validate_dispatch_cli_specific(project, paths, manifest, stage)

    spec_ref = artifacts.get("spec")
    if not spec_ref:
        add_issue(issues, "error", "missing-spec", "manifest", "No spec artifact is linked in the manifest.")
    else:
        spec_path = project / spec_ref
        if not spec_path.exists():
            add_issue(issues, "error", "missing-spec-file", spec_ref, "Spec file does not exist.")
        else:
            spec_text = read_text(spec_path, limit=160_000)
            required_sections = ["Grilling Evidence", "Goal", "Problem", "In Scope", "Out of Scope", "Acceptance Criteria", "Verification"]
            for section in required_sections:
                content = extract_section(spec_text, section)
                if not content:
                    add_issue(issues, "error", "missing-spec-section", spec_ref, f"Spec section `{section}` is missing or empty.")
                elif has_placeholder(content):
                    add_issue(issues, "error", "spec-placeholder", spec_ref, f"Spec section `{section}` still contains placeholder text.")

            if re.search(r"^Status:\s*Draft\s*$", spec_text, re.MULTILINE):
                severity = "warning" if stage == "spec" else "error"
                add_issue(issues, severity, "spec-draft", spec_ref, "Spec status is still Draft.")

            if extract_section(spec_text, "Open Questions") and not re.search(r"## Open Questions\s*\n\s*(-\s+none|none)\b", spec_text, re.IGNORECASE):
                add_issue(issues, "warning", "open-questions", spec_ref, "Spec has open questions; confirm they do not block implementation.")

    return issues


def validation_markdown(title: str, run_id: str, issues: list[dict[str, Any]]) -> str:
    lines = [
        f"# Validation Report: {title}",
        "",
        f"Date: {today()}",
        f"Run ID: `{run_id}`",
        "",
        "## Summary",
        "",
        f"- Errors: `{sum(1 for item in issues if item['severity'] == 'error')}`",
        f"- Warnings: `{sum(1 for item in issues if item['severity'] == 'warning')}`",
        "",
        "## Findings",
        "",
    ]
    if not issues:
        lines.append("- No validation findings.")
    else:
        for issue in issues:
            lines.append(f"- [{issue['severity'].upper()}] `{issue['code']}` `{issue['path']}`: {issue['message']}")
    lines.extend(
        [
            "",
            "## Gate",
            "",
            "The run is dispatch-ready only when there are no errors. Warnings require orchestrator judgment.",
        ]
    )
    return "\n".join(lines) + "\n"


def command_validate(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    issues = validate_run(project, paths, manifest, stage=args.stage)
    report_path = paths.run_dir / "validation.md"
    json_path = paths.run_dir / "validation.json"
    payload = {
        "run_id": run_id,
        "project": str(project),
        "ok": validation_exit_code(issues, args.fail_on_warnings) == 0,
        "issues": issues,
    }
    if args.dry_run:
        print_json(payload | {"would_write": [rel(report_path, project), rel(json_path, project)]})
        return validation_exit_code(issues, args.fail_on_warnings)

    write_text(report_path, validation_markdown(manifest["feature"]["title"], run_id, issues), force=True)
    save_json(json_path, payload)
    artifact_set(manifest, "validation", rel(report_path, project))
    artifact_set(manifest, "validation_json", rel(json_path, project))
    append_phase(manifest, "validate", "passed" if payload["ok"] else "failed", {"path": rel(report_path, project), "issues": len(issues)})
    save_manifest(paths, manifest)
    print_json(payload)
    return validation_exit_code(issues, args.fail_on_warnings)


def command_ready_ids(project: Path) -> set[str]:
    result = command([sys.executable, str(CORE), "ready", "--project", str(project)], check=False)
    if result.returncode != 0:
        return set()
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return set()
    if not isinstance(payload, list):
        return set()
    return {str(item.get("id")) for item in payload if isinstance(item, dict) and item.get("id")}


def worker_prompt(
    project: Path,
    run_id: str,
    task_id: str,
    task_ref: str,
    brief_ref: str,
    spec_ref: str,
    context_ref: str,
    br_id: str | None,
) -> str:
    br_line = f"- `br` bead id: `{br_id}`" if br_id else "- `br` bead id: not materialized or not linked"
    return f"""You are a Codex worker implementing one scoped flywheel task.

You are not alone in this codebase. Other agents or the user may have active changes. Do not revert unrelated edits; inspect and work with the current tree.

Project: `{project}`
Run ID: `{run_id}`
Task ID: `{task_id}`
{br_line}

Read first:
- `{spec_ref}`
- `{context_ref}`
- `{task_ref}`
- `{brief_ref}`
- Applicable `AGENTS.md` files for any path you touch.

Assignment:
- Implement only the task described by `{task_ref}` and `{brief_ref}`.
- Keep the change small, reviewable, and within the file/package scope listed in the task.
- If scope is unclear or product/architecture risk appears, write a decision request instead of guessing.
- Add or update tests for changed behavior.
- Run the verification commands listed in the task bead.

Coordination protocol:
- If `br` is available and a bead id is listed, claim/update that bead before editing.
- If Agent Mail is active, reserve the likely file paths before editing and release reservations at the end.
- Leave progress in the task bead or coordination thread if work is partial.

Final report format:
- Files changed:
- Behavior implemented:
- Verification commands and outcomes:
- Open questions or blockers:
- Follow-up beads needed:
"""


def command_dispatch(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)

    issues = validate_run(project, paths, manifest, stage="dispatch")
    if validation_exit_code(issues, fail_on_warnings=False) != 0 and not args.skip_validate:
        payload = {"run_id": run_id, "ok": False, "reason": "validation failed", "issues": issues}
        print_json(payload)
        return 1

    task_refs = manifest.get("artifacts", {}).get("task_beads") or []
    brief_refs = manifest.get("artifacts", {}).get("worker_briefs") or []
    brief_by_id = {Path(ref).stem: ref for ref in brief_refs}
    spec_ref = manifest.get("artifacts", {}).get("spec", "<spec path>")
    context_ref = manifest.get("artifacts", {}).get("context", "<context pack>")
    br_by_task = manifest.get("br_beads", {})
    ready_ids = command_ready_ids(project) if args.ready_only else set()

    packets = []
    for task_ref in task_refs:
        task_id = Path(task_ref).stem
        br_id = br_by_task.get(task_id)
        if args.ready_only:
            if not br_id or br_id not in ready_ids:
                continue
        if args.task and task_id not in set(args.task):
            continue
        if task_id not in brief_by_id:
            continue
        if args.max_workers and len(packets) >= args.max_workers:
            break
        task_text = read_text(project / task_ref, limit=80_000)
        file_hints = parse_task_file_hints(task_text)
        prompt = worker_prompt(project, run_id, task_id, task_ref, brief_by_id[task_id], spec_ref, context_ref, br_id)
        packet = {
            "task_id": task_id,
            "br_id": br_id,
            "task": task_ref,
            "brief": brief_by_id[task_id],
            "file_hints": file_hints,
            "spawn_agent": {
                "agent_type": "worker",
                "fork_context": False,
                "message": prompt,
            },
            "coordination_commands": {
                "claim_br": f"{rel(CORE, project)} update-bead --project {shlex.quote(str(project))} --id {shlex.quote(str(br_id))} --claim" if br_id else "",
                "reserve_agent_mail": "Use flywheel-core.py start-session with --reserve for the file_hints if Agent Mail is active.",
            },
            "required_report_fields": [
                "Files changed",
                "Behavior implemented",
                "Verification commands and outcomes",
                "Open questions or blockers",
                "Follow-up beads needed",
            ],
        }
        packets.append(packet)

    dispatch_json = paths.dispatch_dir / "worker-dispatch.json"
    dispatch_md = paths.dispatch_dir / "worker-dispatch.md"
    payload = {
        "run_id": run_id,
        "project": str(project),
        "packets": packets,
        "notes": [
            "The local CLI cannot invoke Codex spawn_agent directly; the orchestrator should call multi_agent_v1.spawn_agent with each packet's spawn_agent object.",
            "Use max_workers and ready_only to keep parallelism bounded.",
        ],
    }

    lines = [
        f"# Worker Dispatch: {manifest['feature']['title']}",
        "",
        f"Date: {today()}",
        f"Run ID: `{run_id}`",
        "",
        "## Orchestrator Instructions",
        "",
        "Call `multi_agent_v1.spawn_agent` once per packet using the `spawn_agent` object in `worker-dispatch.json`.",
        "Do not spawn two workers that own overlapping file scopes unless the task graph explicitly allows it.",
        "",
        "## Packets",
        "",
    ]
    if not packets:
        lines.append("- No dispatchable packets.")
    for packet in packets:
        lines.extend(
            [
                f"### `{packet['task_id']}`",
                "",
                f"- Task: `{packet['task']}`",
                f"- Brief: `{packet['brief']}`",
                f"- br id: `{packet['br_id'] or 'none'}`",
                f"- File hints: {', '.join(packet['file_hints']) if packet['file_hints'] else 'none'}",
                "",
                "```text",
                packet["spawn_agent"]["message"],
                "```",
                "",
            ]
        )

    if args.dry_run:
        print_json(payload | {"would_write": [rel(dispatch_json, project), rel(dispatch_md, project)]})
        return 0

    save_json(dispatch_json, payload)
    write_text(dispatch_md, "\n".join(lines), force=args.force)
    artifact_set(manifest, "worker_dispatch", rel(dispatch_json, project))
    artifact_set(manifest, "worker_dispatch_report", rel(dispatch_md, project))
    append_phase(manifest, "dispatch", "prepared", {"packets": len(packets), "path": rel(dispatch_json, project)})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "dispatch": rel(dispatch_json, project), "packets": len(packets)})
    return 0 if packets else 1


def command_optimize(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    issues = validate_run(project, paths, manifest, stage="auto")
    artifacts = manifest.get("artifacts", {})
    profiles = profile_coverage(project, manifest)
    decisions = decision_summary(project, manifest)
    review = review_evidence_summary(project, manifest)
    worker_reports = worker_report_summary(project, manifest)
    proposals: list[dict[str, str]] = []

    if any(issue["code"] == "spec-placeholder" for issue in issues):
        proposals.append(
            {
                "classification": "apply-now",
                "target": "feature-spec-architect",
                "proposal": "Before task bead generation, run validation and reject specs with placeholder sections.",
                "why": "Prevents workers from implementing vague scaffolds.",
            }
        )
    if any(issue["code"] == "missing-file-scope" for issue in issues):
        proposals.append(
            {
                "classification": "apply-now",
                "target": "implementation-orchestrator",
                "proposal": "Require every bead to include likely file/package boundaries before dispatch.",
                "why": "Reduces worker collisions and broad edits.",
            }
        )
    if any(issue["code"] == "broad-file-scope" for issue in issues):
        proposals.append(
            {
                "classification": "review-first",
                "target": "implementation-orchestrator",
                "proposal": "Refine broad likely-file scopes before dispatching future workers or promote broad-scope warnings to blocking for publication-sensitive runs.",
                "why": "Broad scopes increase worker collisions and make review less attributable.",
            }
        )
    if not artifacts.get("worker_dispatch"):
        proposals.append(
            {
                "classification": "apply-now",
                "target": "orchestrator",
                "proposal": "Generate dispatch packets before spawning workers.",
                "why": "Makes worker prompts durable and repeatable.",
            }
        )
    if not artifacts.get("review_command_results"):
        proposals.append(
            {
                "classification": "review-first",
                "target": "code-quality-governor",
                "proposal": "Capture verification commands in the review phase before git publication.",
                "why": "Makes merge readiness auditable.",
            }
        )
    elif not review["ok"]:
        proposals.append(
            {
                "classification": "apply-now",
                "target": "code-quality-governor",
                "proposal": "Require passing command evidence and an explicit approved semantic code-quality-governor verdict before status, git, or PR publication.",
                "why": "Command output alone does not prove that correctness, maintainability, prompt/eval safety, and open-source readiness were reviewed.",
            }
        )
    if worker_reports["missing"] or worker_reports["blocked"]:
        proposals.append(
            {
                "classification": "apply-now",
                "target": "orchestrator",
                "proposal": "Ingest one complete worker report per dispatched packet before final validation and publication.",
                "why": "Dispatch packets prove work was assigned; worker reports prove the assigned work completed or exposed a blocker.",
            }
        )
    if profiles["missing"]:
        proposals.append(
            {
                "classification": "apply-now",
                "target": "worker-profile-factory",
                "proposal": "Generate or link all task-declared worker profiles before briefs and dispatch.",
                "why": "Workers should not start specialized work without the reusable role contract promised by the bead.",
            }
        )
    if decisions["blocking_open"]:
        proposals.append(
            {
                "classification": "review-first",
                "target": "orchestrator",
                "proposal": "Resolve blocking decision requests before launching more implementation workers.",
                "why": "Blocking decisions represent product, architecture, safety, dependency, release, or nontrivial implementation risk.",
            }
        )
    dispatch_ref = artifacts.get("worker_dispatch")
    if dispatch_ref and (project / dispatch_ref).exists():
        dispatch_payload = load_json(project / dispatch_ref)
        packets = dispatch_payload.get("packets", [])
        if packets and not any(packet.get("br_id") for packet in packets):
            proposals.append(
                {
                    "classification": "review-first",
                    "target": "implementation-orchestrator",
                    "proposal": "Prefer `dispatch --ready-only` after `--create-br-beads` so dependency readiness is enforced by `br ready`.",
                    "why": "Dispatching all task files can launch dependent work before blockers are complete.",
                }
            )
    if not proposals:
        proposals.append(
            {
                "classification": "defer",
                "target": "workflow",
                "proposal": "No immediate workflow changes found from this run.",
                "why": "Current artifacts are complete enough for the configured checks.",
            }
        )

    report_path = paths.run_dir / "workflow-optimization.md"
    json_path = paths.run_dir / "workflow-optimization.json"
    lines = [
        f"# Workflow Optimization: {manifest['feature']['title']}",
        "",
        f"Date: {today()}",
        f"Run ID: `{run_id}`",
        "",
        "## Inputs Reviewed",
        "",
        f"- Manifest: `{rel(paths.manifest, project)}`",
        f"- Validation issues: `{len(issues)}`",
        f"- Review results: `{artifacts.get('review_command_results', 'none')}`",
        f"- Worker reports complete: `{worker_reports['ok']}`",
        "",
        "## Proposals",
        "",
    ]
    for item in proposals:
        lines.extend(
            [
                f"### {item['classification']}: `{item['target']}`",
                "",
                item["proposal"],
                "",
                f"Why: {item['why']}",
                "",
            ]
        )

    payload = {"run_id": run_id, "project": str(project), "proposals": proposals}
    if args.dry_run:
        print_json(payload | {"would_write": [rel(report_path, project), rel(json_path, project)]})
        return 0

    write_text(report_path, "\n".join(lines), force=args.force)
    save_json(json_path, payload)
    artifact_set(manifest, "workflow_optimization", rel(report_path, project))
    artifact_set(manifest, "workflow_optimization_json", rel(json_path, project))
    append_phase(manifest, "optimize", "prepared", {"path": rel(report_path, project), "proposals": len(proposals)})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "workflow_optimization": rel(report_path, project), "proposals": len(proposals)})
    return 0


def command_pr_lane(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    ensure_git_project(project)

    branch = git(["branch", "--show-current"], project).stdout.strip()
    title = args.title or manifest["feature"]["title"]
    body_path = paths.run_dir / "pr-body.md"
    pr_lane_path = paths.run_dir / "pr-lane.md"
    validation_ref = manifest.get("artifacts", {}).get("validation", "not generated")
    review_ref = manifest.get("artifacts", {}).get("review", "not generated")
    optimization_ref = manifest.get("artifacts", {}).get("workflow_optimization", "not generated")
    body = f"""## Summary

- Run ID: `{run_id}`
- Feature: {manifest['feature']['title']}
- Spec: `{manifest.get('artifacts', {}).get('spec', 'missing')}`
- Validation: `{validation_ref}`
- Review: `{review_ref}`
- Workflow optimization: `{optimization_ref}`

## Verification

See `{manifest.get('artifacts', {}).get('review_command_results', 'review command results not captured')}`.

## Orchestrator Notes

- Confirm no validation errors remain before marking the PR ready.
- Confirm worker reports have been reviewed.
- Confirm Agent Mail was not used as durable source of truth unless strict-ready.
"""
    command_args = [
        "gh",
        "pr",
        "create",
        "--title",
        title,
        "--body-file",
        str(body_path),
    ]
    if args.base:
        command_args.extend(["--base", args.base])
    if args.draft:
        command_args.append("--draft")
    command_text = " ".join(shlex.quote(item) for item in command_args)
    executed: dict[str, Any] | None = None

    if args.execute and pr_lane_path.exists() and not args.force:
        raise SystemExit(f"Refusing to execute remote PR creation before overwriting existing local lane without --force: {pr_lane_path}")

    if args.execute and not args.override_gates:
        gate_issues = publication_gate_issues(project, paths, manifest, require_git_lane=True)
        if gate_issues:
            raise SystemExit("PR execution blocked by publication gates:\n" + "\n".join(f"- {item}" for item in gate_issues))

    if args.execute:
        write_text(body_path, body, force=True)
        result = command(command_args, cwd=project)
        executed = {
            "command": command_text,
            "exit_code": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
        }
        if result.returncode != 0:
            raise SystemExit(result.stderr.strip() or "gh pr create failed")

    lines = [
        f"# PR Lane: {manifest['feature']['title']}",
        "",
        f"Date: {today()}",
        f"Run ID: `{run_id}`",
        f"Current branch: `{branch or '<detached>'}`",
        "",
        "## PR Body",
        "",
        f"- Body file: `{rel(body_path, project)}`",
        "",
        "## Proposed Command",
        "",
        f"- `{command_text}`",
        "",
        "## Execution",
        "",
    ]
    if executed:
        lines.append(f"- Executed with exit `{executed['exit_code']}`.")
        if executed["stdout"]:
            lines.extend(["", "```text", executed["stdout"], "```"])
    else:
        lines.append("- Not executed. Re-run with `--execute` after push/auth intent is explicit.")

    if args.dry_run:
        print_json({"run_id": run_id, "would_write": [rel(body_path, project), rel(pr_lane_path, project)], "command": command_text})
        return 0

    if not body_path.exists():
        write_text(body_path, body, force=args.force)
    write_text(pr_lane_path, "\n".join(lines) + "\n", force=args.force or bool(executed))
    artifact_set(manifest, "pr_body", rel(body_path, project))
    artifact_set(manifest, "pr_lane", rel(pr_lane_path, project))
    append_phase(manifest, "pr_lane", "executed" if executed else "prepared", {"path": rel(pr_lane_path, project), "command": command_text})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "pr_lane": rel(pr_lane_path, project), "executed": bool(executed), "command": command_text})
    return 0


def command_run(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = args.run_id
    outputs: list[dict[str, Any]] = []
    if args.dry_run and not run_id:
        if args.feature:
            run_id = default_run_id(extract_title(args.feature))
        elif args.feature_file:
            run_id = default_run_id(extract_title(read_text(project_path(args.feature_file), limit=4000)))

    def call(argv: list[str]) -> int:
        full = [sys.executable, str(ROOT / "scripts" / "flywheel-runner.py"), *argv]
        if args.dry_run:
            outputs.append(
                {
                    "command": " ".join(shlex.quote(item) for item in full),
                    "exit_code": 0,
                    "stdout": "",
                    "stderr": "dry-run: command not executed",
                }
            )
            return 0
        result = command(full)
        outputs.append(
            {
                "command": " ".join(shlex.quote(item) for item in full),
                "exit_code": result.returncode,
                "stdout": result.stdout[-COMMAND_OUTPUT_LIMIT:],
                "stderr": result.stderr[-COMMAND_OUTPUT_LIMIT:],
            }
        )
        return result.returncode

    if args.feature or args.feature_file:
        intake_args = ["intake", "--project", str(project)]
        if run_id:
            intake_args.extend(["--run-id", run_id])
        if args.feature:
            intake_args.extend(["--feature", args.feature])
        if args.feature_file:
            intake_args.extend(["--feature-file", args.feature_file])
        if args.force:
            intake_args.append("--force")
        code = call(intake_args)
        if code != 0:
            print_json({"ok": False, "stopped_at": "intake", "outputs": outputs})
            return code
        if not run_id:
            try:
                payload = json.loads(outputs[-1]["stdout"])
                run_id = payload.get("run_id")
            except json.JSONDecodeError:
                run_id = "latest"
    else:
        run_id = resolve_run_id(project, run_id or "latest")

    phases = args.phase or ["context", "spec", "beads", "profiles", "briefs", "validate", "dispatch", "review", "optimize", "git-lane", "pr-lane", "status"]
    for phase in phases:
        if phase == "intake":
            continue
        if phase == "context":
            argv = ["context", "--project", str(project), "--run-id", str(run_id)]
            for query in args.query:
                argv.extend(["--query", query])
            if args.force:
                argv.append("--force")
        elif phase == "spec":
            argv = ["spec", "--project", str(project), "--run-id", str(run_id)]
            if args.force:
                argv.append("--force")
        elif phase == "beads":
            if not args.beads_json:
                outputs.append(
                    {
                        "command": "beads",
                        "exit_code": 2,
                        "stdout": "",
                        "stderr": "beads phase requires --beads-json; stop for orchestrator task graph generation.",
                    }
                )
                print_json({"ok": False, "stopped_at": "beads", "reason": "missing --beads-json", "outputs": outputs})
                return 2
            argv = ["beads", "--project", str(project), "--run-id", str(run_id), "--beads-json", args.beads_json]
            if args.create_br_beads:
                argv.append("--create-br-beads")
            if args.force:
                argv.append("--force")
        elif phase == "profiles":
            argv = ["profiles", "--project", str(project), "--run-id", str(run_id)]
            if args.force:
                argv.append("--force")
        elif phase == "briefs":
            argv = ["briefs", "--project", str(project), "--run-id", str(run_id)]
            if args.force:
                argv.append("--force")
        elif phase == "validate":
            argv = ["validate", "--project", str(project), "--run-id", str(run_id), "--stage", "dispatch"]
            if args.force:
                argv.append("--force")
        elif phase == "dispatch":
            argv = ["dispatch", "--project", str(project), "--run-id", str(run_id)]
            if args.ready_only or run_should_use_ready_only(project, str(run_id)):
                argv.append("--ready-only")
            if args.skip_validate:
                argv.append("--skip-validate")
            if args.force:
                argv.append("--force")
        elif phase == "review":
            argv = ["review", "--project", str(project), "--run-id", str(run_id)]
            for review_command in args.command:
                argv.extend(["--command", review_command])
            if args.force:
                argv.append("--force")
        elif phase == "optimize":
            argv = ["optimize", "--project", str(project), "--run-id", str(run_id)]
            if args.force:
                argv.append("--force")
        elif phase == "git-lane":
            argv = ["git-lane", "--project", str(project), "--run-id", str(run_id)]
            if args.force:
                argv.append("--force")
        elif phase == "pr-lane":
            argv = ["pr-lane", "--project", str(project), "--run-id", str(run_id), "--draft"]
            if args.force:
                argv.append("--force")
        elif phase == "status":
            argv = ["status", "--project", str(project), "--run-id", str(run_id)]
        else:
            raise SystemExit(f"Unknown run phase: {phase}")

        code = call(argv)
        if code != 0:
            print_json({"ok": False, "stopped_at": phase, "outputs": outputs})
            return code

    print_json({"ok": True, "run_id": run_id, "outputs": outputs})
    return 0


def create_br_beads(project: Path, tasks: list[dict[str, Any]], labels: str) -> dict[str, Any]:
    created: dict[str, Any] = {}
    for task in tasks:
        description = "\n".join(
            [
                task["context"],
                "",
                "Acceptance criteria:",
                *[f"- {item}" for item in task["acceptance_criteria"]],
                "",
                "Verification:",
                *[f"- {item}" for item in task["verification"]],
            ]
        )
        result = command(
            [
                sys.executable,
                str(CORE),
                "create-bead",
                "--project",
                str(project),
                "--title",
                task["title"],
                "--type",
                task["type"],
                "--priority",
                task["br_priority"],
                "--description",
                description,
                "--labels",
                labels,
                "--slug",
                task["id"],
            ],
            check=True,
        )
        payload = json.loads(result.stdout)
        created[task["id"]] = payload.get("id")

    for task in tasks:
        for dep in task["depends_on"]:
            if dep not in created:
                continue
            command(
                [
                    sys.executable,
                    str(CORE),
                    "add-dependency",
                    "--project",
                    str(project),
                    "--issue",
                    str(created[task["id"]]),
                    "--depends-on",
                    str(created[dep]),
                ],
                check=True,
            )
    return created


def command_beads(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    spec_ref = manifest.get("artifacts", {}).get("spec", "<spec path>")
    tasks = load_beads(args, manifest, project)
    task_ids = [task["id"] for task in tasks]
    duplicate_ids = sorted({task_id for task_id in task_ids if task_ids.count(task_id) > 1})
    normalized_titles = [slugify(task["title"]) for task in tasks]
    duplicate_titles = sorted({title for title in normalized_titles if normalized_titles.count(title) > 1})
    if duplicate_ids or duplicate_titles:
        raise SystemExit(
            "Task graph contains duplicates: "
            f"ids={duplicate_ids or 'none'}, normalized_titles={duplicate_titles or 'none'}"
        )
    written = []
    for task in tasks:
        path = paths.tasks_dir / f"{task['id']}.md"
        if not args.dry_run:
            write_text(path, task_markdown(task, spec_ref, run_id), force=args.force)
        written.append(rel(path, project))

    br_created: dict[str, Any] = {}
    if args.create_br_beads and not args.dry_run:
        labels = args.labels or f"flywheel,{run_id}"
        br_created = create_br_beads(project, tasks, labels)
        manifest["br_beads"].update(br_created)

    if args.dry_run:
        print_json({"run_id": run_id, "would_write": written, "would_create_br_beads": args.create_br_beads})
        return 0

    artifact_set(manifest, "task_beads", written)
    append_phase(
        manifest,
        "beads",
        "complete",
        {"count": len(tasks), "paths": written, "br_created": br_created},
    )
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "task_beads": written, "br_created": br_created})
    return 0


def worker_profile_markdown(
    profile_id: str,
    task_id: str,
    task_ref: str,
    task_text: str,
    spec_ref: str,
    context_ref: str,
    args: argparse.Namespace,
) -> str:
    task_title = parse_task_title(task_text, task_id)
    file_hints = parse_task_file_hints(task_text)
    acceptance = parse_task_list_section(task_text, "Acceptance Criteria")
    verification = parse_task_list_section(task_text, "Verification")
    allowed_edit = args.allowed_edit or file_hints or [f"`{task_ref}`: task artifact only until the profile is narrowed"]
    allowed_inspect = args.allowed_inspect or [f"`{spec_ref}`", f"`{context_ref}`", f"`{task_ref}`", "applicable `AGENTS.md` files"]
    forbidden = args.forbidden_decision or [
        "architecture boundaries outside the task bead",
        "product behavior not covered by acceptance criteria",
        "new dependencies or provider choices",
        "data model or persistence changes not specified by the orchestrator",
    ]
    gates = args.quality_gate or [
        "Change stays within the task file/package scope.",
        "Acceptance criteria are implemented or explicitly reported as blocked.",
        "Verification commands from the task bead are run or a concrete reason is reported.",
    ]
    if acceptance:
        gates.append("Acceptance criteria from the bead remain the source of truth:")
        gates.extend([f"  - {item}" for item in acceptance])
    verification_commands = args.verification or verification or ["Run the verification commands listed in the task bead."]
    research = args.research_note or "not needed"
    mandate = args.mandate or f"Complete recurring work shaped like `{task_id}` without redesigning the feature."
    reuse_trigger = args.reuse_trigger or f"Use this worker when a bead has the same implementation shape as `{task_title}`."
    scope_items = args.scope or ["Implement the scoped task behavior described by the linked bead and worker brief."]
    out_of_scope = args.out_of_scope or [
        "Unrelated refactors.",
        "Changing public behavior outside the task acceptance criteria.",
        "Making product, architecture, prompt-policy, or data-model decisions reserved for the orchestrator.",
    ]
    rendered = render_worker_profile(
        WorkerProfileRenderInputV1(
            profile_id=profile_id,
            task_id=task_id,
            task_ref=task_ref,
            task_title=task_title,
            spec_ref=spec_ref,
            context_ref=context_ref,
            reuse_trigger=reuse_trigger,
            mandate=mandate,
            scope=tuple(scope_items),
            out_of_scope=tuple(out_of_scope),
            allowed_inspect=tuple(allowed_inspect),
            research_note=research,
            allowed_edit=tuple(allowed_edit),
            forbidden_decisions=tuple(forbidden),
            quality_gates=tuple(gates),
            verification_commands=tuple(verification_commands),
            generated_at=today(),
        )
    )
    return rendered.decode("utf-8")


def command_profiles(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    task_refs = manifest.get("artifacts", {}).get("task_beads") or []
    if not task_refs:
        raise SystemExit("No task beads found in manifest. Run `beads` first.")

    spec_ref = manifest.get("artifacts", {}).get("spec", "<spec path>")
    context_ref = manifest.get("artifacts", {}).get("context", "<context pack>")
    written: dict[str, str] = {}
    skipped: list[str] = []
    selected_tasks = set(args.task)
    known_task_ids = {Path(ref).stem for ref in task_refs}
    unknown_tasks = sorted(selected_tasks - known_task_ids)
    if unknown_tasks:
        raise SystemExit(f"Unknown task id(s): {', '.join(unknown_tasks)}")
    for task_ref in task_refs:
        task_id = Path(task_ref).stem
        if selected_tasks and task_id not in selected_tasks:
            continue
        task_text = read_text(project / task_ref, limit=100_000)
        action, parsed_profile_id = parse_worker_profile_directive(task_text)
        profile_id = parsed_profile_id
        if action != "create" or not profile_id:
            skipped.append(task_id)
            continue
        profile_path = paths.worker_profiles_dir / f"{profile_id}.md"
        if not args.dry_run:
            write_text(
                profile_path,
                worker_profile_markdown(profile_id, task_id, task_ref, task_text, spec_ref, context_ref, args),
                force=args.force,
            )
            artifact_dict_set(manifest, "worker_profiles", profile_id, rel(profile_path, project))
        written[profile_id] = rel(profile_path, project)

    if args.dry_run:
        print_json({"run_id": run_id, "would_write": written, "skipped_tasks": skipped})
        return 0

    append_phase(manifest, "profiles", "complete", {"count": len(written), "paths": written, "skipped_tasks": skipped})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "worker_profiles": written, "skipped_tasks": skipped})
    return 0


def command_briefs(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    task_paths = manifest.get("artifacts", {}).get("task_beads") or []
    if not task_paths:
        raise SystemExit("No task beads found in manifest. Run `beads` first.")
    spec_ref = manifest.get("artifacts", {}).get("spec", "<spec path>")
    written = []
    for task_ref in task_paths:
        task_path = project / task_ref
        task_id = task_path.stem
        brief_path = paths.briefs_dir / f"{task_id}.md"
        task_text = read_text(task_path)
        title_match = re.search(r"^# Task Bead:\s+(.+)$", task_text, re.MULTILINE)
        title = title_match.group(1) if title_match else task_id
        profile_action, profile_id = parse_worker_profile_directive(task_text)
        profile_refs = dict(manifest.get("artifacts", {}).get("worker_profiles") or {})
        profile_ref = profile_refs.get(profile_id or "") or (
            rel(paths.worker_profiles_dir / f"{profile_id}.md", project) if profile_id and (paths.worker_profiles_dir / f"{profile_id}.md").exists() else ""
        )
        context_ref = manifest.get("artifacts", {}).get("context", "<context pack>")
        brief = render_worker_brief(
            WorkerBriefRenderInputV1(
                task_id=task_id,
                task_title=title,
                spec_ref=spec_ref,
                task_ref=task_ref,
                context_ref=context_ref,
                profile_ref=profile_ref or None,
            )
        ).decode("utf-8")
        if not args.dry_run:
            write_text(brief_path, brief, force=args.force)
        written.append(rel(brief_path, project))

    if args.dry_run:
        print_json({"run_id": run_id, "would_write": written})
        return 0

    artifact_set(manifest, "worker_briefs", written)
    append_phase(manifest, "briefs", "complete", {"count": len(written), "paths": written})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "worker_briefs": written})
    return 0


def parse_decision_options(options: list[str]) -> list[dict[str, str]]:
    parsed = []
    for raw in options:
        parts = [part.strip() for part in raw.split("|", 2)]
        if len(parts) != 3 or not all(parts):
            raise SystemExit("Each --option must use `id|label|consequence`.")
        parsed.append({"id": slugify(parts[0], fallback="option"), "label": parts[1], "consequence": parts[2]})
    if not parsed:
        raise SystemExit("Provide at least one --option `id|label|consequence`.")
    return parsed


def decision_request_markdown(args: argparse.Namespace, run_id: str, decision_id: str, task_ref: str | None) -> str:
    options = parse_decision_options(args.option)
    recommended = slugify(args.recommendation, fallback="option") if args.recommendation else options[0]["id"]
    if recommended not in {item["id"] for item in options}:
        raise SystemExit(f"--recommendation must match one option id: {', '.join(item['id'] for item in options)}")
    task_label = args.task or "run"
    task_link = f"`{task_ref}`" if task_ref else "`run-level`"
    option_lines: list[str] = []
    for index, item in enumerate(options, 1):
        option_lines.extend(
            [
                f"{index}. `{item['id']}`: {item['label']}",
                f"   - Consequence: {item['consequence']}",
                "",
            ]
        )
    return f"""# Decision Request: {decision_id}

Status: Open
Run ID: `{run_id}`
Bead: {task_label}
Agent: {args.agent}
Created: {dt.datetime.now().strftime("%Y-%m-%d %H:%M")}

## Severity

{args.severity}

## Decision Type

{args.decision_type}

## Question

{args.question}

## Context

{args.context}

## Options

{chr(10).join(option_lines).rstrip()}

## Recommendation

Recommended option: `{recommended}`

Reason:

{args.reason}

## Default If Unanswered

{args.default_if_unanswered}

## Links

- {task_link}

## Resolution

Answered by:
Answered at:
Decision:
Follow-up beads:
"""


def resolve_decision_request(text: str, resolution: str, answered_by: str) -> str:
    updated = re.sub(r"^Status:\s*.+$", "Status: Resolved", text, count=1, flags=re.MULTILINE)
    resolution_block = f"""## Resolution

Answered by: {answered_by}
Answered at: {dt.datetime.now().strftime("%Y-%m-%d %H:%M")}
Decision: {resolution}
Follow-up beads:
"""
    if re.search(r"^## Resolution\s*$", updated, flags=re.MULTILINE):
        start = re.search(r"^## Resolution\s*$", updated, flags=re.MULTILINE)
        assert start is not None
        next_heading = re.search(r"^##\s+", updated[start.end() :], flags=re.MULTILINE)
        end = start.end() + next_heading.start() if next_heading else len(updated)
        updated = updated[: start.start()] + resolution_block + updated[end:]
    else:
        updated = updated.rstrip() + "\n\n" + resolution_block
    return updated.rstrip() + "\n"


def command_decision_request(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    if args.resolve and not args.id:
        raise SystemExit("--resolve requires --id so the target decision is unambiguous.")
    decision_id = slugify(args.id or f"{args.task or 'run'}-{args.question if args.question else 'decision'}", fallback="decision")
    decision_path = paths.decision_requests_dir / f"{decision_id}.md"

    if args.resolve:
        if not decision_path.exists():
            raise SystemExit(f"Decision request not found: {decision_path}")
        if args.dry_run:
            print_json({"run_id": run_id, "would_resolve": rel(decision_path, project), "decision": args.resolve})
            return 0
        write_text(decision_path, resolve_decision_request(read_text(decision_path, limit=80_000), args.resolve, args.answered_by), force=True)
        artifact_list_append(manifest, "decision_requests", rel(decision_path, project))
        append_phase(manifest, "decision_request", "resolved", {"path": rel(decision_path, project), "decision": args.resolve})
        save_manifest(paths, manifest)
        print_json({"run_id": run_id, "decision_request": rel(decision_path, project), "resolved": True})
        return 0

    missing = [name for name in ["question", "context", "reason", "default_if_unanswered"] if not getattr(args, name)]
    if missing:
        raise SystemExit("Missing required fields for a new decision request: " + ", ".join(f"--{item.replace('_', '-')}" for item in missing))
    parsed_options = parse_decision_options(args.option)
    recommended = slugify(args.recommendation, fallback="option") if args.recommendation else parsed_options[0]["id"]
    if recommended not in {item["id"] for item in parsed_options}:
        raise SystemExit(f"--recommendation must match one option id: {', '.join(item['id'] for item in parsed_options)}")

    task_ref = None
    if args.task:
        task_refs = manifest.get("artifacts", {}).get("task_beads") or []
        for ref in task_refs:
            if Path(ref).stem == args.task:
                task_ref = ref
                break
        if not task_ref:
            raise SystemExit(f"Task `{args.task}` is not linked in this run.")

    if args.dry_run:
        print_json({"run_id": run_id, "would_write": rel(decision_path, project), "id": decision_id})
        return 0

    write_text(decision_path, decision_request_markdown(args, run_id, decision_id, task_ref), force=args.force)
    artifact_list_append(manifest, "decision_requests", rel(decision_path, project))
    append_phase(manifest, "decision_request", "open", {"path": rel(decision_path, project), "severity": args.severity})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "decision_request": rel(decision_path, project), "resolved": False})
    return 0


def worker_report_markdown(args: argparse.Namespace, run_id: str, task_ref: str, brief_ref: str) -> str:
    files_changed = args.file_changed or ["No files changed."]
    behaviors = args.behavior or ["No behavior summary provided."]
    verification = args.verification or ["No verification result provided."]
    blockers = args.blocker or ["None."]
    followups = args.followup or ["None."]
    return f"""# Worker Report: {args.task}

Status: {args.status}
Run ID: `{run_id}`
Task: `{task_ref}`
Brief: `{brief_ref}`
Agent: {args.agent}
Reported: {dt.datetime.now().strftime("%Y-%m-%d %H:%M")}

## Files Changed

{bullets(files_changed)}

## Behavior Implemented

{bullets(behaviors)}

## Verification

{bullets(verification)}

## Open Questions Or Blockers

{bullets(blockers)}

## Follow-up Beads Needed

{bullets(followups)}
"""


def command_worker_report(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    task_refs = manifest.get("artifacts", {}).get("task_beads") or []
    brief_refs = manifest.get("artifacts", {}).get("worker_briefs") or []
    task_ref = next((ref for ref in task_refs if Path(ref).stem == args.task), "")
    brief_ref = next((ref for ref in brief_refs if Path(ref).stem == args.task), "")
    if not task_ref:
        raise SystemExit(f"Task `{args.task}` is not linked in this run.")
    if not brief_ref:
        raise SystemExit(f"Worker brief for task `{args.task}` is not linked in this run.")
    if args.status == "complete" and not args.behavior:
        raise SystemExit("Complete worker reports require at least one --behavior entry.")
    if args.status == "complete" and not args.verification:
        raise SystemExit("Complete worker reports require at least one --verification entry.")

    report_dir = project / "docs" / "worker-reports" / run_id
    report_path = report_dir / f"{args.task}.md"
    if args.dry_run:
        print_json({"run_id": run_id, "would_write": rel(report_path, project), "task": args.task, "status": args.status})
        return 0

    write_text(report_path, worker_report_markdown(args, run_id, task_ref, brief_ref), force=args.force)
    artifact_dict_set(manifest, "worker_reports", args.task, rel(report_path, project))
    append_phase(manifest, "worker_report", "recorded", {"task": args.task, "status": args.status, "path": rel(report_path, project)})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "worker_report": rel(report_path, project), "task": args.task, "status": args.status})
    return 0 if args.status.lower() in {"complete", "completed", "done"} else 1


def command_review(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    review_path = paths.reviews_dir / f"{run_id}.md"
    results = [shell_command(item, project) for item in args.command]
    result_json_path = paths.run_dir / "review-command-results.json"
    has_commands = bool(results)
    failed = [item for item in results if item["exit_code"] != 0]
    verdict_label = args.semantic_verdict.replace("-", " ").title()
    findings = args.finding or ["No semantic findings recorded." if args.semantic_verdict == "approved" else "Semantic review is pending."]
    test_gaps = args.test_gap or ["No additional test gaps recorded." if args.semantic_verdict == "approved" else "Semantic review has not recorded test gaps yet."]
    architecture_notes = args.architecture_note or ["No architecture notes recorded." if args.semantic_verdict == "approved" else "Semantic review has not recorded architecture notes yet."]
    prompt_eval_notes = args.prompt_eval_note or ["No prompt/eval notes recorded." if args.semantic_verdict == "approved" else "Semantic review has not recorded prompt/eval notes yet."]
    lines = [
        f"# Review Report: {manifest['feature']['title']}",
        "",
        f"Date: {today()}",
        "Reviewer: code-quality-governor",
        f"Run ID: `{run_id}`",
        "",
        "## Inputs",
        "",
        f"- Spec: `{manifest.get('artifacts', {}).get('spec', '<missing>')}`",
        f"- Task beads: {len(manifest.get('artifacts', {}).get('task_beads') or [])}",
        f"- Worker briefs: {len(manifest.get('artifacts', {}).get('worker_briefs') or [])}",
        "",
        "## Findings",
        "",
        *[f"- {item}" for item in findings],
        "",
        "## Required Fixes",
        "",
        "- None detected by captured commands or semantic review." if has_commands and not failed and args.semantic_verdict == "approved" else "- Review is incomplete until verification commands pass and semantic review is approved.",
        "",
        "## Test Gaps",
        "",
        *[f"- {item}" for item in test_gaps],
        "",
        "## Verification Commands",
        "",
    ]
    if results:
        for result in results:
            status = "passed" if result["exit_code"] == 0 else "failed"
            lines.append(f"- `{result['command']}`: {status} (`exit={result['exit_code']}`)")
    else:
        lines.append("- No commands executed. Add `--command '<cmd>'` to capture verification output.")
    lines.extend(
        [
            "",
            "## Architecture Notes",
            "",
            *[f"- {item}" for item in architecture_notes],
            "",
            "## Prompt / Eval Notes",
            "",
            *[f"- {item}" for item in prompt_eval_notes],
            "",
            "## Verdict",
            "",
            f"Semantic verdict: {verdict_label}",
        ]
    )
    if args.dry_run:
        print_json({"run_id": run_id, "would_write": [rel(review_path, project), rel(result_json_path, project)]})
        return 0

    write_text(review_path, "\n".join(lines) + "\n", force=args.force)
    save_json(result_json_path, {"run_id": run_id, "results": results, "has_commands": has_commands, "commands_exit_ok": not failed if has_commands else False})
    artifact_set(manifest, "review", rel(review_path, project))
    artifact_set(manifest, "review_command_results", rel(result_json_path, project))
    append_phase(manifest, "review", "prepared", {"path": rel(review_path, project), "commands": len(results)})
    save_manifest(paths, manifest)
    exit_code = 0 if has_commands and not failed else 1
    if args.allow_empty and not has_commands:
        exit_code = 0
    print_json({"run_id": run_id, "review": rel(review_path, project), "commands_exit_ok": exit_code == 0, "semantic_verdict": args.semantic_verdict})
    return exit_code


def git(args: list[str], project: Path, check: bool = False) -> subprocess.CompletedProcess[str]:
    return command(["git", *args], cwd=project, check=check)


def ensure_git_project(project: Path) -> None:
    result = git(["rev-parse", "--is-inside-work-tree"], project)
    if result.returncode != 0 or result.stdout.strip() != "true":
        raise SystemExit(f"git-lane requires a git worktree: {project}")


def command_git_lane(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    ensure_project_dirs(paths)
    manifest = load_manifest(paths)
    lane_path = paths.run_dir / "git-lane.md"
    ensure_git_project(project)

    branch = git(["branch", "--show-current"], project).stdout.strip()
    status = git(["status", "--short"], project).stdout.rstrip()
    staged = git(["diff", "--cached", "--stat"], project).stdout.rstrip()
    unstaged = git(["diff", "--stat"], project).stdout.rstrip()
    commands: list[str] = []
    executed: list[dict[str, Any]] = []

    target_branch = args.branch or f"codex/{manifest['feature']['slug']}"
    if args.execute and lane_path.exists() and not args.force:
        raise SystemExit(f"Refusing to execute git mutations before overwriting existing local lane without --force: {lane_path}")
    if args.execute and not args.override_gates:
        gate_issues = publication_gate_issues(project, paths, manifest, require_git_lane=False)
        if gate_issues:
            raise SystemExit("git execution blocked by publication gates:\n" + "\n".join(f"- {item}" for item in gate_issues))

    if args.create_branch:
        commands.append(f"git switch -c {shlex.quote(target_branch)}")
        if args.execute:
            result = git(["switch", "-c", target_branch], project)
            executed.append({"command": commands[-1], "exit_code": result.returncode, "stderr": result.stderr.strip()})
            if result.returncode != 0:
                raise SystemExit(result.stderr.strip() or "git branch creation failed")
            branch = target_branch

    for path in args.stage:
        commands.append(f"git add {shlex.quote(path)}")
        if args.execute:
            result = git(["add", path], project)
            executed.append({"command": commands[-1], "exit_code": result.returncode, "stderr": result.stderr.strip()})
            if result.returncode != 0:
                raise SystemExit(result.stderr.strip() or "git add failed")

    if args.commit_message:
        commands.append(f"git commit -m {shlex.quote(args.commit_message)}")
        if args.execute:
            result = git(["commit", "-m", args.commit_message], project)
            executed.append({"command": commands[-1], "exit_code": result.returncode, "stderr": result.stderr.strip()})
            if result.returncode != 0:
                raise SystemExit(result.stderr.strip() or "git commit failed")

    if args.push:
        commands.append(f"git push -u origin {shlex.quote(target_branch if args.create_branch else branch)}")
        if args.execute:
            push_branch = target_branch if args.create_branch else branch
            if not push_branch:
                raise SystemExit("Cannot push without a current branch or --branch.")
            result = git(["push", "-u", "origin", push_branch], project)
            executed.append({"command": commands[-1], "exit_code": result.returncode, "stderr": result.stderr.strip()})
            if result.returncode != 0:
                raise SystemExit(result.stderr.strip() or "git push failed")

    lines = [
        f"# Git Lane: {manifest['feature']['title']}",
        "",
        f"Date: {today()}",
        f"Run ID: `{run_id}`",
        f"Project: `{project}`",
        "",
        "## Current State",
        "",
        f"- Current branch: `{branch or '<detached>'}`",
        f"- Target branch: `{target_branch}`",
        "",
        "## Status",
        "",
        "```text",
        status or "clean",
        "```",
        "",
        "## Diff Summary",
        "",
        "### Staged",
        "",
        "```text",
        staged or "none",
        "```",
        "",
        "### Unstaged",
        "",
        "```text",
        unstaged or "none",
        "```",
        "",
        "## Proposed Commands",
        "",
    ]
    if commands:
        lines.extend([f"- `{item}`" for item in commands])
    else:
        lines.append("- No mutating commands requested. Use explicit flags such as `--create-branch`, `--stage`, `--commit-message`, and `--push`.")

    lines.extend(["", "## Executed Commands", ""])
    if executed:
        for item in executed:
            lines.append(f"- `{item['command']}`: exit `{item['exit_code']}`")
    else:
        lines.append("- None. Re-run with `--execute` to apply requested git steps.")

    if args.dry_run:
        print_json({"run_id": run_id, "would_write": rel(lane_path, project), "commands": commands})
        return 0

    write_text(lane_path, "\n".join(lines) + "\n", force=args.force)
    artifact_set(manifest, "git_lane", rel(lane_path, project))
    append_phase(manifest, "git_lane", "prepared" if not args.execute else "executed", {"path": rel(lane_path, project), "commands": commands})
    save_manifest(paths, manifest)
    print_json({"run_id": run_id, "git_lane": rel(lane_path, project), "executed": bool(executed)})
    return 0


def command_commands(_: argparse.Namespace) -> int:
    print_json(
        {
            "ok": True,
            "tool": "flywheel-runner.py",
            "description": "Deterministic orchestration runner for Codex-led feature work.",
            "stdout": "All commands emit JSON on stdout. Logs and subprocess stderr are captured inside JSON fields when applicable.",
            "global_conventions": {
                "--project": "Target product/codebase path.",
                "--run-id": "Run id; defaults to latest where supported.",
                "--dry-run": "Show intended writes without changing files on write commands.",
                "--force": "Overwrite generated artifacts for the same run on write commands.",
            },
            "commands": RUNNER_COMMANDS,
        }
    )
    return 0


def command_doctor(args: argparse.Namespace) -> int:
    project = project_path(args.project) if args.project else None
    checks: dict[str, Any] = {
        "python": {
            "ok": True,
            "version": sys.version.split()[0],
        },
        "runner": {
            "ok": Path(__file__).exists(),
            "path": str(Path(__file__).resolve()),
        },
        "core": {
            "ok": CORE.exists(),
            "path": str(CORE),
        },
        "rg": {
            "ok": shutil.which("rg") is not None,
            "path": shutil.which("rg"),
        },
        "git": {
            "ok": shutil.which("git") is not None,
            "path": shutil.which("git"),
        },
    }
    if project:
        latest = latest_run_id(project) if project.exists() else None
        checks["project"] = {
            "ok": project.exists(),
            "path": str(project),
            "has_git": (project / ".git").exists(),
            "has_flywheel_runs": (project / "docs" / "flywheel-runs").exists(),
            "latest_run_id": latest,
        }
    ok = all(bool(item.get("ok")) for item in checks.values())
    print_json({"ok": ok, "checks": checks})
    return 0 if ok else 1


def command_status(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    run_id = resolve_run_id(project, args.run_id)
    paths = RunnerPaths(project=project, run_id=run_id)
    manifest = load_manifest(paths)
    expected = [
        "intake",
        "context",
        "spec",
        "validation",
        "task_beads",
        "worker_briefs",
        "worker_dispatch",
        "worker_reports",
        "review",
        "workflow_optimization",
        "git_lane",
        "pr_lane",
    ]
    artifacts = manifest.get("artifacts", {})
    missing = [item for item in expected if not artifacts.get(item)]
    profiles = profile_coverage(project, manifest)
    decisions = decision_summary(project, manifest)
    validation_issues = validate_run(project, paths, manifest, stage="final")
    review = review_evidence_summary(project, manifest)
    worker_reports = worker_report_summary(project, manifest)
    output = {
        "run_id": run_id,
        "title": manifest["feature"]["title"],
        "project": str(project),
        "artifacts": artifacts,
        "missing": missing,
        "worker_profiles": profiles,
        "decision_requests": decisions,
        "validation_issues": validation_issues,
        "review_evidence": review,
        "worker_reports": worker_reports,
        "phases": manifest.get("phases", {}),
        "br_beads": manifest.get("br_beads", {}),
    }
    print_json(output)
    return 0 if (
        not missing
        and profiles["ok"]
        and not decisions["blocking_open"]
        and not decisions["missing"]
        and not any(issue["severity"] == "error" for issue in validation_issues)
        and review["ok"]
        and worker_reports["ok"]
    ) else 1


def command_plan(args: argparse.Namespace) -> int:
    project = project_path(args.project)
    feature = args.feature or "<feature description>"
    title = extract_title(feature if feature != "<feature description>" else "new-feature", args.title)
    run_id = args.run_id or default_run_id(title)
    runner = rel(ROOT / "scripts" / "flywheel-runner.py", project)
    commands = [
        f"{runner} intake --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --feature {shlex.quote(feature)}",
        f"{runner} context --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --query '<relevant-term>'",
        f"{runner} spec --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)}",
        f"{runner} validate --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --stage spec",
        f"{runner} beads --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --beads-json '<tasks.json>' --create-br-beads",
        f"{runner} profiles --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)}",
        f"{runner} briefs --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)}",
        f"{runner} validate --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --stage dispatch",
        f"{runner} dispatch --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --ready-only",
        f"{runner} worker-report --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --task '<task-id>' --file-changed '<path>: <summary>' --behavior '<summary>' --verification '<command>: passed'",
        f"{runner} review --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --command '<verification command>' --semantic-verdict approved",
        f"{runner} optimize --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)}",
        f"{runner} git-lane --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)}",
        f"{runner} pr-lane --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)} --draft",
        f"{runner} status --project {shlex.quote(str(project))} --run-id {shlex.quote(run_id)}",
    ]
    print_json(
        {
            "run_id": run_id,
            "project": str(project),
            "commands": commands,
            "notes": [
                "The orchestrator fills the spec and task JSON between phases.",
                "Use --create-br-beads only after task scope is approved.",
                "Use profiles before briefs when a bead says `create <profile>`.",
                "Use decision-request for material blockers instead of chat-only questions.",
                "Use dispatch output with multi_agent_v1.spawn_agent to launch real Codex workers.",
                "Use worker-report once per dispatched task after reading worker final reports.",
                "Use --semantic-verdict approved only after a real code-quality-governor review.",
                "Use git-lane --execute only when branch/stage/commit/push intent is explicit.",
                "Use pr-lane --execute only after push and GitHub auth intent are explicit.",
            ],
        }
    )
    return 0


def add_project(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project", required=True, help="Target product/codebase path.")


def add_run(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--run-id", default="latest", help="Flywheel run id. Defaults to latest run for this project.")


def add_common_write(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--dry-run", action="store_true", help="Show intended writes without changing files.")
    parser.add_argument("--force", action="store_true", help="Overwrite generated artifacts for the same run.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="End-to-end workflow runner for orchestrator agents.")
    sub = parser.add_subparsers(dest="command", required=True)

    commands = sub.add_parser("commands", help="Print a machine-readable command manifest.")
    commands.set_defaults(func=command_commands)

    doctor = sub.add_parser("doctor", help="Inspect runner dependencies and optional project state.")
    doctor.add_argument("--project", help="Optional target product/codebase path.")
    doctor.set_defaults(func=command_doctor)

    plan = sub.add_parser("plan", help="Print the recommended command sequence for a feature run.")
    add_project(plan)
    plan.add_argument("--feature", default="")
    plan.add_argument("--title")
    plan.add_argument("--run-id")
    plan.set_defaults(func=command_plan)

    intake = sub.add_parser("intake", help="Create the run manifest and intake artifact.")
    add_project(intake)
    intake.add_argument("--feature")
    intake.add_argument("--feature-file")
    intake.add_argument("--title")
    intake.add_argument("--run-id")
    add_common_write(intake)
    intake.set_defaults(func=command_intake)

    context = sub.add_parser("context", help="Collect repo context for spec and worker planning.")
    add_project(context)
    add_run(context)
    context.add_argument("--file", action="append", default=[], help="Additional file to include in the context pack.")
    context.add_argument("--query", action="append", default=[], help="ripgrep query to capture in the context pack.")
    context.add_argument("--allow-external-file", action="store_true", help="Allow --file paths outside the target project.")
    add_common_write(context)
    context.set_defaults(func=command_context)

    spec = sub.add_parser("spec", help="Create an implementation-ready feature spec scaffold.")
    add_project(spec)
    add_run(spec)
    add_common_write(spec)
    spec.set_defaults(func=command_spec)

    beads = sub.add_parser("beads", help="Materialize task beads from spec or task JSON.")
    add_project(beads)
    add_run(beads)
    beads.add_argument("--beads-json", help="JSON array or object with `tasks` array.")
    beads.add_argument("--create-br-beads", action="store_true", help="Create matching br beads through flywheel-core.py.")
    beads.add_argument("--labels", default="", help="Labels for created br beads.")
    add_common_write(beads)
    beads.set_defaults(func=command_beads)

    briefs = sub.add_parser("briefs", help="Generate worker briefs from task beads.")
    add_project(briefs)
    add_run(briefs)
    add_common_write(briefs)
    briefs.set_defaults(func=command_briefs)

    profiles = sub.add_parser("profiles", help="Generate reusable worker profiles required by task beads.")
    add_project(profiles)
    add_run(profiles)
    profiles.add_argument("--task", action="append", default=[], help="Only generate profiles for this task id. Can be repeated.")
    profiles.add_argument("--reuse-trigger")
    profiles.add_argument("--mandate")
    profiles.add_argument("--scope", action="append", default=[])
    profiles.add_argument("--out-of-scope", action="append", default=[])
    profiles.add_argument("--research-note", default="")
    profiles.add_argument("--allowed-edit", action="append", default=[])
    profiles.add_argument("--allowed-inspect", action="append", default=[])
    profiles.add_argument("--forbidden-decision", action="append", default=[])
    profiles.add_argument("--quality-gate", action="append", default=[])
    profiles.add_argument("--verification", action="append", default=[])
    add_common_write(profiles)
    profiles.set_defaults(func=command_profiles)

    validate = sub.add_parser("validate", help="Validate spec, task graph, profiles, briefs, decisions, and review readiness.")
    add_project(validate)
    add_run(validate)
    validate.add_argument("--stage", choices=["auto", "spec", "dispatch", "final"], default="auto")
    validate.add_argument("--fail-on-warnings", action="store_true")
    add_common_write(validate)
    validate.set_defaults(func=command_validate)

    dispatch = sub.add_parser("dispatch", help="Prepare worker spawn packets for the orchestrator.")
    add_project(dispatch)
    add_run(dispatch)
    dispatch.add_argument("--task", action="append", default=[], help="Only dispatch this task id. Can be repeated.")
    dispatch.add_argument("--max-workers", type=int, default=0, help="Maximum packets to emit. 0 means no limit.")
    dispatch.add_argument("--ready-only", action="store_true", help="Dispatch only br-ready tasks when br ids are linked.")
    dispatch.add_argument("--skip-validate", action="store_true", help="Prepare packets even if validation has errors.")
    add_common_write(dispatch)
    dispatch.set_defaults(func=command_dispatch)

    decision = sub.add_parser("decision-request", help="Create or resolve a structured decision request for a run or task.")
    add_project(decision)
    add_run(decision)
    decision.add_argument("--id", help="Decision id. Defaults to a slug from task and question.")
    decision.add_argument("--task", help="Linked task id.")
    decision.add_argument("--agent", default="orchestrator")
    decision.add_argument("--severity", choices=["blocking", "important", "optional"], default="blocking")
    decision.add_argument("--decision-type", choices=["product", "architecture", "implementation", "safety", "dependency", "release"], default="implementation")
    decision.add_argument("--question")
    decision.add_argument("--context")
    decision.add_argument("--option", action="append", default=[], help="Decision option as `id|label|consequence`. Repeat for multiple options.")
    decision.add_argument("--recommendation")
    decision.add_argument("--reason")
    decision.add_argument("--default-if-unanswered")
    decision.add_argument("--resolve", help="Resolve the decision with this answer. Requires --id.")
    decision.add_argument("--answered-by", default="orchestrator")
    add_common_write(decision)
    decision.set_defaults(func=command_decision_request)

    worker_report = sub.add_parser("worker-report", help="Record a completed worker report for a dispatched task.")
    add_project(worker_report)
    add_run(worker_report)
    worker_report.add_argument("--task", required=True, help="Task id this report satisfies.")
    worker_report.add_argument("--agent", default="worker")
    worker_report.add_argument("--status", choices=["complete", "blocked", "partial"], default="complete")
    worker_report.add_argument("--file-changed", action="append", default=[], help="Changed file summary. Repeatable.")
    worker_report.add_argument("--behavior", action="append", default=[], help="Implemented behavior summary. Repeatable.")
    worker_report.add_argument("--verification", action="append", default=[], help="Verification command/outcome. Repeatable.")
    worker_report.add_argument("--blocker", action="append", default=[], help="Open blocker or question. Repeatable.")
    worker_report.add_argument("--followup", action="append", default=[], help="Follow-up bead recommendation. Repeatable.")
    add_common_write(worker_report)
    worker_report.set_defaults(func=command_worker_report)

    review = sub.add_parser("review", help="Prepare a review report and optionally capture verification commands.")
    add_project(review)
    add_run(review)
    review.add_argument("--command", action="append", default=[], help="Verification command to run from the target project.")
    review.add_argument("--allow-empty", action="store_true", help="Allow a scaffold-only review report. This is not merge-ready.")
    review.add_argument("--semantic-verdict", choices=["pending", "approved", "changes-requested", "blocked"], default="pending")
    review.add_argument("--finding", action="append", default=[], help="Semantic review finding. Repeatable.")
    review.add_argument("--test-gap", action="append", default=[], help="Semantic review test gap. Repeatable.")
    review.add_argument("--architecture-note", action="append", default=[], help="Semantic review architecture note. Repeatable.")
    review.add_argument("--prompt-eval-note", action="append", default=[], help="Semantic review prompt/eval note. Repeatable.")
    add_common_write(review)
    review.set_defaults(func=command_review)

    git_lane = sub.add_parser("git-lane", help="Inspect or execute branch/stage/commit/push lane.")
    add_project(git_lane)
    add_run(git_lane)
    git_lane.add_argument("--branch")
    git_lane.add_argument("--create-branch", action="store_true")
    git_lane.add_argument("--stage", action="append", default=[])
    git_lane.add_argument("--commit-message")
    git_lane.add_argument("--push", action="store_true")
    git_lane.add_argument("--execute", action="store_true", help="Run requested mutating git commands.")
    git_lane.add_argument("--override-gates", action="store_true", help="Allow execution even when final validation/review gates are not green.")
    add_common_write(git_lane)
    git_lane.set_defaults(func=command_git_lane)

    optimize = sub.add_parser("optimize", help="Generate workflow optimization proposals for this run.")
    add_project(optimize)
    add_run(optimize)
    add_common_write(optimize)
    optimize.set_defaults(func=command_optimize)

    pr_lane = sub.add_parser("pr-lane", help="Prepare or execute GitHub PR creation lane.")
    add_project(pr_lane)
    add_run(pr_lane)
    pr_lane.add_argument("--title")
    pr_lane.add_argument("--base")
    pr_lane.add_argument("--draft", action="store_true")
    pr_lane.add_argument("--execute", action="store_true", help="Run gh pr create. Requires network/auth.")
    pr_lane.add_argument("--override-gates", action="store_true", help="Allow execution even when final validation/review/git gates are not green.")
    add_common_write(pr_lane)
    pr_lane.set_defaults(func=command_pr_lane)

    run = sub.add_parser("run", help="Run a sequenced orchestration lane until judgment or missing inputs are required.")
    add_project(run)
    run.add_argument("--feature")
    run.add_argument("--feature-file")
    run.add_argument("--run-id")
    run.add_argument("--query", action="append", default=[])
    run.add_argument("--beads-json")
    run.add_argument("--create-br-beads", action="store_true")
    run.add_argument("--ready-only", action="store_true", help="Force ready-only dispatch during the run. Runs with linked br beads use ready-only automatically.")
    run.add_argument("--phase", action="append", help="Phase to run, repeated in order. Defaults to the full lane.")
    run.add_argument("--command", action="append", default=[], help="Review command to execute during review phase.")
    run.add_argument("--skip-validate", action="store_true")
    add_common_write(run)
    run.set_defaults(func=command_run)

    status = sub.add_parser("status", help="Show run status and missing phases.")
    add_project(status)
    add_run(status)
    status.set_defaults(func=command_status)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
