from __future__ import annotations

import ast
from pathlib import Path

ROOT = Path(__file__).parents[3]
CAPABILITY_GAP = ROOT / "src" / "study_agent_devkit" / "capability_gap"


def test_pre_github_capability_gap_modules_have_no_external_effect_imports() -> None:
    forbidden = {
        "git",
        "github",
        "gh",
        "subprocess",
        "urllib",
        "http",
        "model",
        "provider",
        "shell",
    }
    for path in CAPABILITY_GAP.glob("*.py"):
        if path.name.startswith("github") or path.name == "__init__.py":
            continue
        tree = ast.parse(path.read_text(), filename=str(path))
        imports = {
            alias.name.split(".")[0]
            for node in ast.walk(tree)
            if isinstance(node, ast.Import)
            for alias in node.names
        }
        imports |= {
            node.module.split(".")[0]
            for node in ast.walk(tree)
            if isinstance(node, ast.ImportFrom) and node.module
        }
        assert imports.isdisjoint(forbidden), path


def test_github_adapter_has_no_git_gh_shell_or_model_provider_lane() -> None:
    forbidden = ("subprocess", "shell=True", "import git", "import gh", "model")
    for path in (
        CAPABILITY_GAP / "github_contracts.py",
        CAPABILITY_GAP / "github_service.py",
        CAPABILITY_GAP / "github_store.py",
        CAPABILITY_GAP / "github_rest.py",
    ):
        text = path.read_text()
        assert "noqa" not in text
        for token in forbidden:
            assert token not in text
