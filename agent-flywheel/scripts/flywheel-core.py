#!/usr/bin/env python3
"""Structured wrappers around br, bv, and Agent Mail."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
LOCAL_BIN = Path.home() / ".local" / "bin"
MAIL_ENV_OVERRIDES: dict[str, str] = {}

CORE_COMMANDS: dict[str, dict[str, Any]] = {
    "commands": {
        "summary": "Print a machine-readable command manifest.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "versions": {
        "summary": "Inspect required tool availability and versions.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "init": {
        "summary": "Initialize a project for br-backed task tracking.",
        "side_effects": ["local_write"],
        "output": "json",
    },
    "create-bead": {
        "summary": "Create a br task bead with structured defaults.",
        "side_effects": ["local_write"],
        "output": "json",
    },
    "ready": {
        "summary": "List br-ready task beads.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "update-bead": {
        "summary": "Update a br task bead.",
        "side_effects": ["local_write"],
        "output": "json",
    },
    "close-bead": {
        "summary": "Close a br task bead.",
        "side_effects": ["local_write"],
        "dangerous_flags": ["--force"],
        "output": "json",
    },
    "add-dependency": {
        "summary": "Add a dependency edge between br task beads.",
        "side_effects": ["local_write"],
        "output": "json",
    },
    "triage": {
        "summary": "Run bv robot triage.",
        "side_effects": ["local_write_optional"],
        "output": "json",
    },
    "agent-mail-preflight": {
        "summary": "Inspect Agent Mail readiness for a project.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "start-session": {
        "summary": "Start an Agent Mail session and optionally reserve files.",
        "side_effects": ["local_write", "coordination_write"],
        "output": "json",
    },
    "reserve": {
        "summary": "Reserve files in Agent Mail.",
        "side_effects": ["coordination_write"],
        "output": "json",
    },
    "release-reservations": {
        "summary": "Release Agent Mail reservations by id or path.",
        "side_effects": ["coordination_write"],
        "output": "json",
    },
    "send": {
        "summary": "Send an Agent Mail message.",
        "side_effects": ["coordination_write", "external_communication"],
        "output": "json",
    },
    "status": {
        "summary": "Inspect Agent Mail robot status.",
        "side_effects": ["read_only"],
        "output": "json",
    },
    "reservations": {
        "summary": "Inspect Agent Mail reservations.",
        "side_effects": ["read_only"],
        "output": "json",
    },
}


def env() -> dict[str, str]:
    current = os.environ.copy()
    current["PATH"] = f"{LOCAL_BIN}:{current.get('PATH', '')}"
    current.update(MAIL_ENV_OVERRIDES)
    return current


def run(args: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        env=env(),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if check and completed.returncode != 0:
        raise SystemExit(
            "Command failed:\n"
            + " ".join(args)
            + f"\nexit={completed.returncode}\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def is_mailbox_lock_busy(stderr: str) -> bool:
    return "mailbox activity lock is busy" in stderr or "Resource is temporarily busy" in stderr


def require_tool(name: str) -> None:
    result = run(["/usr/bin/env", "bash", "-lc", f"command -v {name}"], check=False)
    if result.returncode != 0:
        raise SystemExit(f"Missing required tool: {name}")


def project_path(value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve()
    return path


def sqlite_url(path: Path) -> str:
    return f"sqlite:///{path}"


def configure_mail_env(args: argparse.Namespace) -> None:
    storage_root = getattr(args, "mailbox_storage_root", None)
    database_url = getattr(args, "mailbox_database_url", None)
    http_port = getattr(args, "mailbox_http_port", None)

    if storage_root:
        root = project_path(storage_root)
        root.mkdir(parents=True, exist_ok=True)
        MAIL_ENV_OVERRIDES["STORAGE_ROOT"] = str(root)
        MAIL_ENV_OVERRIDES["DATABASE_URL"] = database_url or sqlite_url(root / "storage.sqlite3")
        if not (root / ".git").exists():
            run(["git", "init"], cwd=root)
    elif database_url:
        MAIL_ENV_OVERRIDES["DATABASE_URL"] = database_url

    if http_port:
        MAIL_ENV_OVERRIDES["HTTP_PORT"] = str(http_port)


def print_json(data: Any) -> None:
    print(json.dumps(data, indent=2, sort_keys=True))


def parse_stdout(stdout: str) -> Any:
    try:
        return json.loads(stdout) if stdout.strip() else None
    except json.JSONDecodeError:
        return stdout.strip()


def run_probe(cmd: list[str]) -> dict[str, Any]:
    result = run(cmd, check=False)
    return {
        "ok": result.returncode == 0,
        "exit_code": result.returncode,
        "stdout": parse_stdout(result.stdout),
        "stderr": result.stderr.strip(),
    }


def ensure_project(path: Path, git: bool = True) -> None:
    path.mkdir(parents=True, exist_ok=True)
    if git and not (path / ".git").exists():
        run(["git", "init"], cwd=path)
    if not (path / ".beads").exists():
        run(["br", "init"], cwd=path)


def command_versions(_: argparse.Namespace) -> int:
    versions = {}
    for tool in ["br", "bv", "mcp-agent-mail", "am"]:
        result = run([tool, "--version"], check=False)
        versions[tool] = {
            "available": result.returncode == 0,
            "version": result.stdout.strip() if result.returncode == 0 else "",
            "stderr": result.stderr.strip() if result.returncode != 0 else "",
        }
    print_json(versions)
    return 0 if all(item["available"] for item in versions.values()) else 1


def command_commands(_: argparse.Namespace) -> int:
    print_json(
        {
            "ok": True,
            "tool": "flywheel-core.py",
            "description": "Structured wrappers around br, bv, and Agent Mail for Codex coordination.",
            "stdout": "All wrapper commands emit JSON-compatible output on stdout.",
            "commands": CORE_COMMANDS,
        }
    )
    return 0


def command_init(args: argparse.Namespace) -> int:
    require_tool("br")
    path = project_path(args.project)
    ensure_project(path, git=not args.no_git)
    print_json({"project": str(path), "git": (path / ".git").exists(), "beads": (path / ".beads").exists()})
    return 0


def parse_issue_id(stdout: str) -> str:
    try:
        data = json.loads(stdout)
    except json.JSONDecodeError:
        return stdout.strip().splitlines()[-1].strip()
    for key in ["id", "identifier"]:
        if data.get(key):
            return str(data[key])
    issue = data.get("issue")
    if isinstance(issue, dict) and issue.get("id"):
        return str(issue["id"])
    if isinstance(data.get("issues"), list) and data["issues"] and data["issues"][0].get("id"):
        return str(data["issues"][0]["id"])
    return stdout.strip()


def command_create_bead(args: argparse.Namespace) -> int:
    require_tool("br")
    path = project_path(args.project)
    ensure_project(path)
    cmd = [
        "br",
        "create",
        args.title,
        "--type",
        args.type,
        "--priority",
        args.priority,
        "--json",
    ]
    if args.description:
        cmd.extend(["--description", args.description])
    if args.labels:
        cmd.extend(["--labels", args.labels])
    if args.slug:
        cmd.extend(["--slug", args.slug])
    if args.status:
        cmd.extend(["--status", args.status])
    result = run(cmd, cwd=path)
    issue_id = parse_issue_id(result.stdout)
    print_json({"project": str(path), "id": issue_id, "raw": json.loads(result.stdout)})
    return 0


def command_ready(args: argparse.Namespace) -> int:
    require_tool("br")
    path = project_path(args.project)
    result = run(["br", "ready", "--json"], cwd=path)
    print(result.stdout.strip())
    return 0


def command_update_bead(args: argparse.Namespace) -> int:
    require_tool("br")
    path = project_path(args.project)
    cmd = ["br", "update", args.id, "--json"]
    if args.claim:
        cmd.append("--claim")
    if args.status:
        cmd.extend(["--status", args.status])
    if args.priority:
        cmd.extend(["--priority", args.priority])
    if args.assignee is not None:
        cmd.extend(["--assignee", args.assignee])
    if args.notes:
        cmd.extend(["--notes", args.notes])
    result = run(cmd, cwd=path)
    print(result.stdout.strip())
    return 0


def command_close_bead(args: argparse.Namespace) -> int:
    require_tool("br")
    path = project_path(args.project)
    cmd = ["br", "close", args.id, "--json"]
    if args.reason:
        cmd.extend(["--reason", args.reason])
    if args.force:
        cmd.append("--force")
    result = run(cmd, cwd=path)
    print(result.stdout.strip())
    return 0


def command_add_dependency(args: argparse.Namespace) -> int:
    require_tool("br")
    path = project_path(args.project)
    result = run(["br", "dep", "add", args.issue, args.depends_on, "--json"], cwd=path)
    print(result.stdout.strip())
    return 0


def command_triage(args: argparse.Namespace) -> int:
    require_tool("bv")
    path = project_path(args.project)
    result = run(["bv", "--robot-triage", "-f", "json"], cwd=path)
    print(result.stdout.strip())
    return 0


def command_start_session(args: argparse.Namespace) -> int:
    require_tool("am")
    path = project_path(args.project)
    cmd = [
        "am",
        "macros",
        "start-session",
        "--project",
        str(path),
        "--program",
        args.program,
        "--model",
        args.model,
        "--task",
        args.task,
        "--json",
    ]
    if args.agent_name:
        cmd.extend(["--agent-name", args.agent_name])
    for reserve in args.reserve:
        cmd.extend(["--reserve", reserve])
    if args.reserve_reason:
        cmd.extend(["--reserve-reason", args.reserve_reason])
    if args.reserve_ttl:
        cmd.extend(["--reserve-ttl", str(args.reserve_ttl)])
    result = run(cmd)
    print(result.stdout.strip())
    return 0


def command_agent_mail_preflight(args: argparse.Namespace) -> int:
    require_tool("am")
    path = project_path(args.project)
    checks: dict[str, Any] = {"project": str(path), "mail_env": dict(MAIL_ENV_OVERRIDES)}
    for name, cmd in {
        "locks": ["am", "doctor", "locks", "--json"],
        "doctor_health": ["am", "doctor", "health"],
        "doctor_check": ["am", "doctor", "check", "--json"],
        "status": ["am", "robot", "status", "--project", str(path), "--json"],
        "archive_db_drift": [
            "am",
            "doctor",
            "fix",
            "--only",
            "fm-archive-state-files-archive-db-drift-anomalies",
            "--list",
            "--json",
        ],
        "message_artifacts": [
            "am",
            "doctor",
            "fix",
            "--only",
            "fm-archive-state-files-archive-message-artifact-anomalies",
            "--list",
            "--json",
        ],
        "reservation_parity": [
            "am",
            "doctor",
            "fix",
            "--only",
            "fm-db-state-files-reservation-db-archive-parity",
            "--list",
            "--json",
        ],
    }.items():
        checks[name] = run_probe(cmd)

    doctor_payload = checks["doctor_check"]["stdout"]
    status_payload = checks["status"]["stdout"]
    doctor_healthy = bool(isinstance(doctor_payload, dict) and doctor_payload.get("healthy") is True)
    robot_health = status_payload.get("health") if isinstance(status_payload, dict) else None

    detect_only_names = ["archive_db_drift", "message_artifacts", "reservation_parity"]
    detect_only_findings = []
    for name in detect_only_names:
        payload = checks[name]["stdout"]
        if isinstance(payload, dict) and int(payload.get("findings_count") or 0) > 0:
            detect_only_findings.append(
                {
                    "name": name,
                    "findings_count": payload.get("findings_count"),
                    "severity": payload.get("severity"),
                    "auto_fixable": False,
                }
            )

    basic_command_ok = all(checks[key]["ok"] for key in ["locks", "doctor_check", "status"])
    command_ok = all(item["ok"] for key, item in checks.items() if key not in {"project", "mail_env"})
    doctor_health_ok = bool(checks["doctor_health"]["ok"])
    deep_health_ok = doctor_health_ok and not detect_only_findings

    checks["basic_command_ok"] = basic_command_ok
    checks["command_ok"] = command_ok
    checks["doctor_healthy"] = doctor_healthy
    checks["doctor_health_ok"] = doctor_health_ok
    checks["robot_health"] = robot_health
    checks["detect_only_findings"] = detect_only_findings
    checks["deep_health_ok"] = deep_health_ok
    checks["functional"] = basic_command_ok and robot_health not in {"error", None}
    checks["usable"] = checks["functional"] and doctor_healthy
    checks["ready"] = checks["usable"] and deep_health_ok and robot_health == "ok"
    print_json(checks)
    return 0 if checks["ready"] else 1


def command_reserve(args: argparse.Namespace) -> int:
    require_tool("am")
    path = project_path(args.project)
    cmd = ["am", "file_reservations", "reserve", str(path), args.agent, *args.paths, "--reason", args.reason]
    if args.ttl:
        cmd.extend(["--ttl", str(args.ttl)])
    if args.exclusive:
        cmd.append("--exclusive")
    else:
        cmd.append("--shared")
    result = run(cmd, check=False)
    if result.returncode != 0 and args.exclusive and is_mailbox_lock_busy(result.stderr):
        fallback = [
            "am",
            "macros",
            "start-session",
            "--project",
            str(path),
            "--program",
            args.program,
            "--model",
            args.model,
            "--agent-name",
            args.agent,
            "--task",
            f"Reserve files for {args.reason or 'flywheel work'}",
            "--json",
        ]
        for reserve_path in args.paths:
            fallback.extend(["--reserve", reserve_path])
        if args.reason:
            fallback.extend(["--reserve-reason", args.reason])
        if args.ttl:
            fallback.extend(["--reserve-ttl", str(args.ttl)])
        result = run(fallback)
    elif result.returncode != 0:
        raise SystemExit(
            "Command failed:\n"
            + " ".join(cmd)
            + f"\nexit={result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    print(result.stdout.strip())
    return 0


def command_release_reservations(args: argparse.Namespace) -> int:
    require_tool("am")
    path = project_path(args.project)
    cmd = ["am", "file_reservations", "release", str(path), args.agent]
    for reservation_id in args.ids:
        cmd.extend(["--ids", str(reservation_id)])
    for release_path in args.paths:
        cmd.extend(["--paths", release_path])
    result = run(cmd)
    print(result.stdout.strip())
    return 0


def command_send(args: argparse.Namespace) -> int:
    require_tool("am")
    path = project_path(args.project)
    cmd = [
        "am",
        "mail",
        "send",
        "--project",
        str(path),
        "--from",
        args.sender,
        "--to",
        args.to,
        "--subject",
        args.subject,
        "--body",
        args.body,
        "--thread-id",
        args.thread_id,
        "--importance",
        args.importance,
        "--json",
    ]
    if args.ack_required:
        cmd.append("--ack-required")
    result = run(cmd)
    print(result.stdout.strip())
    return 0


def command_status(args: argparse.Namespace) -> int:
    require_tool("am")
    path = project_path(args.project)
    cmd = ["am", "robot", "status", "--project", str(path), "--json"]
    if args.agent:
        cmd.extend(["--agent", args.agent])
    result = run(cmd)
    print(result.stdout.strip())
    return 0


def command_reservations(args: argparse.Namespace) -> int:
    require_tool("am")
    path = project_path(args.project)
    cmd = ["am", "reservations", "--project", str(path), "--json"]
    if args.agent:
        cmd.extend(["--agent", args.agent])
    if args.all:
        cmd.append("--all")
    if args.conflicts:
        cmd.append("--conflicts")
    if args.expiring:
        cmd.extend(["--expiring", str(args.expiring)])
    result = run(cmd)
    print(result.stdout.strip())
    return 0


def add_mailbox_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--mailbox-storage-root",
        help="Override Agent Mail STORAGE_ROOT for isolated flywheel runs.",
    )
    parser.add_argument(
        "--mailbox-database-url",
        help="Override Agent Mail DATABASE_URL. Defaults to sqlite:///<storage-root>/storage.sqlite3 when storage root is set.",
    )
    parser.add_argument(
        "--mailbox-http-port",
        type=int,
        help="Override Agent Mail HTTP_PORT for commands that start or inspect a server.",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Wrapper over br/bv/Agent Mail")
    sub = parser.add_subparsers(dest="command", required=True)

    commands = sub.add_parser("commands", help="Print a machine-readable command manifest.")
    commands.set_defaults(func=command_commands)

    versions = sub.add_parser("versions", help="Inspect required tool availability and versions.")
    versions.set_defaults(func=command_versions)

    init = sub.add_parser("init", help="Initialize a project for br-backed task tracking.")
    init.add_argument("--project", required=True)
    init.add_argument("--no-git", action="store_true")
    init.set_defaults(func=command_init)

    create = sub.add_parser("create-bead", help="Create a br task bead with structured defaults.")
    create.add_argument("--project", required=True)
    create.add_argument("--title", required=True)
    create.add_argument("--type", default="task")
    create.add_argument("--priority", default="2")
    create.add_argument("--description", default="")
    create.add_argument("--labels", default="")
    create.add_argument("--slug", default="")
    create.add_argument("--status", default="")
    create.set_defaults(func=command_create_bead)

    ready = sub.add_parser("ready", help="List br-ready task beads.")
    ready.add_argument("--project", required=True)
    ready.set_defaults(func=command_ready)

    update = sub.add_parser("update-bead", help="Update a br task bead.")
    update.add_argument("--project", required=True)
    update.add_argument("--id", required=True)
    update.add_argument("--claim", action="store_true")
    update.add_argument("--status")
    update.add_argument("--priority")
    update.add_argument("--assignee")
    update.add_argument("--notes")
    update.set_defaults(func=command_update_bead)

    close = sub.add_parser("close-bead", help="Close a br task bead.")
    close.add_argument("--project", required=True)
    close.add_argument("--id", required=True)
    close.add_argument("--reason", default="")
    close.add_argument("--force", action="store_true")
    close.set_defaults(func=command_close_bead)

    dep = sub.add_parser("add-dependency", help="Add a dependency edge between br task beads.")
    dep.add_argument("--project", required=True)
    dep.add_argument("--issue", required=True)
    dep.add_argument("--depends-on", required=True)
    dep.set_defaults(func=command_add_dependency)

    triage = sub.add_parser("triage", help="Run bv robot triage.")
    triage.add_argument("--project", required=True)
    triage.set_defaults(func=command_triage)

    preflight = sub.add_parser("agent-mail-preflight", help="Inspect Agent Mail readiness for a project.")
    preflight.add_argument("--project", required=True)
    add_mailbox_options(preflight)
    preflight.set_defaults(func=command_agent_mail_preflight)

    start = sub.add_parser("start-session", help="Start an Agent Mail session and optionally reserve files.")
    start.add_argument("--project", required=True)
    start.add_argument("--agent-name")
    start.add_argument("--task", required=True)
    start.add_argument("--program", default="codex")
    start.add_argument("--model", default="gpt-5")
    start.add_argument("--reserve", action="append", default=[])
    start.add_argument("--reserve-reason", default="")
    start.add_argument("--reserve-ttl", type=int)
    add_mailbox_options(start)
    start.set_defaults(func=command_start_session)

    reserve = sub.add_parser("reserve", help="Reserve files in Agent Mail.")
    reserve.add_argument("--project", required=True)
    reserve.add_argument("--agent", required=True)
    reserve.add_argument("--reason", default="")
    reserve.add_argument("--exclusive", action="store_true")
    reserve.add_argument("--ttl", type=int)
    reserve.add_argument("--program", default="codex")
    reserve.add_argument("--model", default="gpt-5")
    add_mailbox_options(reserve)
    reserve.add_argument("paths", nargs="+")
    reserve.set_defaults(func=command_reserve)

    release = sub.add_parser("release-reservations", help="Release Agent Mail reservations by id or path.")
    release.add_argument("--project", required=True)
    release.add_argument("--agent", required=True)
    release.add_argument("--ids", action="append", default=[])
    release.add_argument("--paths", action="append", default=[])
    add_mailbox_options(release)
    release.set_defaults(func=command_release_reservations)

    send = sub.add_parser("send", help="Send an Agent Mail message.")
    send.add_argument("--project", required=True)
    send.add_argument("--from", dest="sender", required=True)
    send.add_argument("--to", required=True)
    send.add_argument("--thread-id", required=True)
    send.add_argument("--subject", required=True)
    send.add_argument("--body", required=True)
    send.add_argument("--importance", default="normal")
    send.add_argument("--ack-required", action="store_true")
    add_mailbox_options(send)
    send.set_defaults(func=command_send)

    status = sub.add_parser("status", help="Inspect Agent Mail robot status.")
    status.add_argument("--project", required=True)
    status.add_argument("--agent")
    add_mailbox_options(status)
    status.set_defaults(func=command_status)

    reservations = sub.add_parser("reservations", help="Inspect Agent Mail reservations.")
    reservations.add_argument("--project", required=True)
    reservations.add_argument("--agent")
    reservations.add_argument("--all", action="store_true")
    reservations.add_argument("--conflicts", action="store_true")
    reservations.add_argument("--expiring", type=int)
    add_mailbox_options(reservations)
    reservations.set_defaults(func=command_reservations)

    args = parser.parse_args()
    configure_mail_env(args)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
