from __future__ import annotations

import ast
from pathlib import Path


def test_capability_gap_package_has_no_authority_or_external_effect_imports() -> None:
    root = Path(__file__).parents[2] / "src" / "study_agent_devkit" / "capability_gap"
    forbidden = {
        "asyncio",
        "flywheel",
        "github",
        "httpx",
        "requests",
        "socket",
        "subprocess",
        "urllib",
    }
    for path in root.glob("*.py"):
        if path.name.startswith("github"):
            continue
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = {alias.name.split(".", 1)[0] for alias in node.names}
                assert not names & forbidden, path
            elif isinstance(node, ast.ImportFrom) and node.module:
                assert node.module.split(".", 1)[0] not in forbidden, path


def test_candidate_contract_source_does_not_define_delivery_identity() -> None:
    contracts = (
        Path(__file__).parents[2]
        / "src"
        / "study_agent_devkit"
        / "capability_gap"
        / "contracts.py"
    ).read_text(encoding="utf-8")
    # Import context is the sole exception; snapshots and evidence must not
    # gain a delivery-id field by accident.
    assert "class CandidateSnapshot" in contracts
    assert "delivery_import_id: str" not in contracts.split("class CandidateSnapshot", 1)[1]
