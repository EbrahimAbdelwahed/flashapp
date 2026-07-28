from __future__ import annotations

import ast
from pathlib import Path


def test_local_sink_firewall_allows_only_filesystem_adapter_dependencies() -> None:
    path = (
        Path(__file__).parents[4]
        / "src"
        / "study_agent_devkit"
        / "capability_gap"
        / "local_flywheel_promotion.py"
    )
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    forbidden = {
        "subprocess",
        "runner",
        "br",
        "dispatch",
        "git",
        "github",
        "network",
        "provider",
        "requests",
        "socket",
        "urllib",
        "study_agent",
    }
    allowed_modules = {
        "ctypes",
        "errno",
        "os",
        "platform",
        "secrets",
        "stat",
        "sys",
        "collections",
        "contextlib",
        "hashlib",
        "typing",
        "study_agent_devkit",
        "contracts",
        "resolution_contracts",
        "__future__",
    }
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".", 1)[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".", 1)[0])
    assert not imported & forbidden
    assert imported <= allowed_modules

    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert not calls & {"run", "Popen", "check_call", "check_output", "system"}
