from __future__ import annotations

import ast
from pathlib import Path

import study_agent_devkit.capability_gap as capability_gap

ROOT = Path(__file__).parents[3]
PROPOSAL_ROOT = ROOT / "src" / "study_agent_devkit" / "capability_gap"


def test_public_exports_are_additive_and_include_only_proposal_surfaces() -> None:
    exports = set(capability_gap.__all__)
    assert {
        "ProposalEvidenceV1",
        "ProposalDraftV1",
        "ProposalService",
    } <= exports
    assert {
        "DecisionViewV1",
        "ResolutionCommandV1",
        "GapResolutionV1",
        "FlywheelPromotionBundleV1",
        "SQLiteResolutionService",
    } <= exports
    assert "SQLiteProposalStore" not in exports
    assert "_SQLiteProposalStore" not in exports
    assert "_SQLiteResolutionStore" not in exports


def test_proposal_modules_have_no_external_effect_or_forbidden_imports() -> None:
    forbidden = {
        "subprocess",
        "socket",
        "requests",
        "httpx",
        "openai",
        "anthropic",
        "github",
        "flywheel",
        "pathlib",
        "os",
    }
    for path in PROPOSAL_ROOT.glob("proposal_*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                assert all(alias.name.split(".")[0] not in forbidden for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                assert (node.module or "").split(".")[0] not in forbidden


def test_proposal_modules_do_not_mutate_gap05b_schema_files() -> None:
    for path in (
        PROPOSAL_ROOT / "proposal_contracts.py",
        PROPOSAL_ROOT / "proposal_store.py",
        PROPOSAL_ROOT / "proposal_service.py",
    ):
        source = path.read_text(encoding="utf-8")
        assert "SQLiteCapabilityGapStore" not in source
        assert "delivery_import_id" not in source
        assert "sbobby" not in source.lower()
