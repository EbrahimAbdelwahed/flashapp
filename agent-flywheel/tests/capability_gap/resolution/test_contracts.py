from __future__ import annotations

import json

import pytest
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    ApprovedArtifactV1,
    CapabilityGapCorruptionError,
    DecisionViewV1,
    DraftArtifactKind,
    GrillReceiptV1,
    GrillSubjectKind,
    ResolutionCommandV1,
    ResolutionOutcome,
)
from study_agent_devkit.capability_gap.proposal_contracts import RequestedAuthority


def test_command_union_roundtrips_and_rejects_noncanonical_branches() -> None:
    zero = "0" * 64
    commands = (
        ResolutionCommandV1(1, zero, zero, ResolutionOutcome.REJECTED, None, None, None, ()),
        ResolutionCommandV1(1, zero, zero, ResolutionOutcome.DEFERRED, None, "later", None, ()),
        ResolutionCommandV1(1, zero, zero, ResolutionOutcome.DUPLICATE, None, None, "1" * 64, ()),
        ResolutionCommandV1(
            1,
            zero,
            zero,
            ResolutionOutcome.ACCEPTED,
            "safe",
            None,
            None,
            (GrillReceiptV1(GrillSubjectKind.PROPOSAL, zero, "r-proposal", "1" * 64),),
        ),
    )
    for command in commands:
        assert ResolutionCommandV1.from_bytes(command.to_bytes()) == command
    raw = json.loads(commands[0].to_bytes())
    raw["selected_option_id"] = "safe"
    with pytest.raises(CapabilityGapCorruptionError):
        ResolutionCommandV1.from_bytes(canonical_json_bytes(raw))


def test_decision_view_roundtrip_and_bool_schema_rejection() -> None:
    zero = "0" * 64
    view = DecisionViewV1(
        1,
        zero,
        zero,
        RequestedAuthority.PLANNING_ONLY,
        ("safe", "small"),
        ("bead-a",),
        "1" * 64,
    )
    assert DecisionViewV1.from_bytes(view.to_bytes()) == view
    raw = json.loads(view.to_bytes())
    raw["schema_version"] = True
    with pytest.raises(CapabilityGapCorruptionError):
        DecisionViewV1.from_bytes(canonical_json_bytes(raw))


def test_decision_view_constructor_matches_decoder_option_limit() -> None:
    zero = "0" * 64
    with pytest.raises(ValueError):
        DecisionViewV1(
            1,
            zero,
            zero,
            RequestedAuthority.PLANNING_ONLY,
            ("a", "b", "c", "d", "e", "f"),
            ("bead",),
            "1" * 64,
        )


def test_approved_artifact_preserves_ordered_unique_dependencies() -> None:
    artifact = ApprovedArtifactV1(
        DraftArtifactKind.BEAD,
        "BEAD-A",
        "approved",
        "body",
        ("BEAD-C", "BEAD-B"),
    )
    assert ApprovedArtifactV1.from_bytes(artifact.to_bytes()) == artifact
