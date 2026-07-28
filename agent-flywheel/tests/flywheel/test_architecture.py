from __future__ import annotations

import ast
from pathlib import Path


def test_materialization_module_has_no_effectful_or_capability_gap_imports() -> None:
    path = (
        Path(__file__).parents[2] / "src" / "study_agent_devkit" / "flywheel" / "materialization.py"
    )
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    forbidden = {
        "asyncio",
        "capability_gap",
        "os",
        "pathlib",
        "requests",
        "socket",
        "subprocess",
        "urllib",
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert not {alias.name.split(".", 1)[0] for alias in node.names} & forbidden
        elif isinstance(node, ast.ImportFrom) and node.module:
            assert node.module.split(".", 1)[0] not in forbidden
