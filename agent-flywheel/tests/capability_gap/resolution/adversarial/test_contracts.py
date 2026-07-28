from __future__ import annotations

import json
from datetime import UTC, datetime

import pytest
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    ApprovedArtifactV1,
    CapabilityGapCorruptionError,
    DraftArtifactKind,
    GapResolutionV1,
    GrillReceiptV1,
    GrillSubjectKind,
    ImplementationGoalV1,
    RequestedAuthority,
    ResolutionCommandV1,
    ResolutionOutcome,
)

ZERO = "0" * 64
ONE = "1" * 64


def _receipt(kind: GrillSubjectKind = GrillSubjectKind.PROPOSAL) -> GrillReceiptV1:
    return GrillReceiptV1(kind, ZERO, "receipt", ONE)


def _accepted_command() -> ResolutionCommandV1:
    return ResolutionCommandV1(
        1, ZERO, ONE, ResolutionOutcome.ACCEPTED, "safe", None, None, (_receipt(),)
    )


@pytest.mark.parametrize("field", ("unknown",))
def test_closed_codecs_reject_unknown_fields(field: str) -> None:
    raw = json.loads(_accepted_command().to_bytes())
    raw[field] = "x"
    with pytest.raises(CapabilityGapCorruptionError):
        ResolutionCommandV1.from_bytes(canonical_json_bytes(raw))


def test_codecs_reject_noncanonical_bool_oversize_and_unknown_enum() -> None:
    command = _accepted_command()
    raw = json.loads(command.to_bytes())
    raw["schema_version"] = True
    with pytest.raises(CapabilityGapCorruptionError):
        ResolutionCommandV1.from_bytes(canonical_json_bytes(raw))
    with pytest.raises(CapabilityGapCorruptionError):
        ResolutionCommandV1.from_bytes(
            json.dumps(json.loads(command.to_bytes()), indent=2).encode()
        )
    raw["schema_version"] = 1
    raw["outcome"] = "not-an-outcome"
    with pytest.raises(CapabilityGapCorruptionError):
        ResolutionCommandV1.from_bytes(canonical_json_bytes(raw))
    with pytest.raises(CapabilityGapCorruptionError):
        ResolutionCommandV1.from_bytes(b"{" + b"x" * (128 * 1024) + b"}")


def test_resolution_codec_rejects_hash_and_crosslink_drift() -> None:
    command = ResolutionCommandV1(1, ZERO, ONE, ResolutionOutcome.REJECTED, None, None, None, ())
    now = datetime(2026, 1, 3, tzinfo=UTC)
    fingerprint = command.authority_receipt_fingerprint
    resolution = GapResolutionV1(
        1,
        GapResolutionV1.derive_id(
            ZERO, ONE, command, fingerprint, RequestedAuthority.PLANNING_ONLY, now
        ),
        ZERO,
        ONE,
        ResolutionOutcome.REJECTED,
        None,
        None,
        None,
        (),
        fingerprint,
        RequestedAuthority.PLANNING_ONLY,
        now,
    )
    raw = json.loads(resolution.to_bytes())
    raw["proposal_id"] = ONE
    with pytest.raises(CapabilityGapCorruptionError):
        GapResolutionV1.from_bytes(canonical_json_bytes(raw))
    raw = json.loads(resolution.to_bytes())
    raw["authority_receipt_fingerprint"] = ONE
    with pytest.raises(CapabilityGapCorruptionError):
        GapResolutionV1.from_bytes(canonical_json_bytes(raw))
    raw = json.loads(resolution.to_bytes())
    raw["resolution_id"] = ONE
    with pytest.raises(CapabilityGapCorruptionError):
        GapResolutionV1.from_bytes(canonical_json_bytes(raw))


def test_nested_codecs_reject_drift_and_invalid_goal() -> None:
    artifact = ApprovedArtifactV1(DraftArtifactKind.SPEC, "SPEC", "approved", "body", ())
    raw = json.loads(artifact.to_bytes())
    raw["artifact_state"] = "draft"
    with pytest.raises(CapabilityGapCorruptionError):
        ApprovedArtifactV1.from_bytes(canonical_json_bytes(raw))
    goal_id = ImplementationGoalV1.derive_id(ZERO, "SPEC", ("BEAD",), "authorized_not_started")
    goal = ImplementationGoalV1(1, goal_id, ZERO, "SPEC", ("BEAD",), "authorized_not_started")
    raw = json.loads(goal.to_bytes())
    raw["goal_id"] = ONE
    with pytest.raises(CapabilityGapCorruptionError):
        ImplementationGoalV1.from_bytes(canonical_json_bytes(raw))


def test_duplicate_command_cannot_target_itself() -> None:
    with pytest.raises(ValueError):
        ResolutionCommandV1(1, ZERO, ONE, ResolutionOutcome.DUPLICATE, None, None, ZERO, ())


def test_architecture_firewall_does_not_export_public_store() -> None:
    import study_agent_devkit.capability_gap as capability_gap

    assert "_SQLiteResolutionStore" not in capability_gap.__all__
    assert not hasattr(capability_gap, "SQLiteResolutionStore")
