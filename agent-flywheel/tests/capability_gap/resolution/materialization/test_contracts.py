from __future__ import annotations

import json
from pathlib import Path

import pytest
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    CapabilityGapCorruptionError,
    FlywheelPromotionReceiptV1,
    LocalFlywheelPromotionSink,
)
from study_agent_devkit.capability_gap.resolution_contracts import MAX_RECEIPT_BYTES

from ._support import accepted_bundle


def test_receipt_factory_uses_exact_bundle_and_sink_domains(tmp_path: Path) -> None:
    service, bundle, _ = accepted_bundle(tmp_path, sink=LocalFlywheelPromotionSink(tmp_path))
    first = FlywheelPromotionReceiptV1.for_bundle(bundle, "a" * 64)
    second = FlywheelPromotionReceiptV1.for_bundle(bundle, "b" * 64)
    assert first.promotion_id == bundle.promotion_id
    assert first.run_id == bundle.materialization_plan.run_id
    assert first.sink_id == "a" * 64
    assert first.receipt_id != second.receipt_id
    assert first.file_manifest_digest == second.file_manifest_digest
    assert first.promotion_bundle_fingerprint == second.promotion_bundle_fingerprint
    assert FlywheelPromotionReceiptV1.from_bytes(first.to_bytes()).to_bytes() == first.to_bytes()
    service.close()


@pytest.mark.parametrize(
    "field,value",
    [
        ("receipt_id", "0" * 64),
        ("promotion_id", "0" * 64),
        ("sink_id", "0" * 64),
        ("promotion_bundle_fingerprint", "0" * 64),
        ("run_id", "other-run"),
        ("file_manifest_digest", "0" * 64),
        ("status", "not-materialized"),
    ],
)
def test_receipt_crosslink_tampering_is_rejected(
    tmp_path: Path, field: str, value: str
) -> None:
    service, bundle, _ = accepted_bundle(tmp_path, sink=LocalFlywheelPromotionSink(tmp_path))
    receipt = FlywheelPromotionReceiptV1.for_bundle(bundle, "a" * 64)
    raw = json.loads(receipt.to_bytes())
    raw[field] = value
    with pytest.raises(CapabilityGapCorruptionError):
        FlywheelPromotionReceiptV1.from_bytes(canonical_json_bytes(raw))
    service.close()


def test_receipt_codec_rejects_unknown_bool_noncanonical_and_bounds(tmp_path: Path) -> None:
    service, bundle, _ = accepted_bundle(tmp_path, sink=LocalFlywheelPromotionSink(tmp_path))
    receipt = FlywheelPromotionReceiptV1.for_bundle(bundle, "a" * 64)
    raw = json.loads(receipt.to_bytes())
    raw["unknown"] = "field"
    with pytest.raises(CapabilityGapCorruptionError):
        FlywheelPromotionReceiptV1.from_bytes(canonical_json_bytes(raw))
    raw = json.loads(receipt.to_bytes())
    raw["schema_version"] = True
    with pytest.raises(CapabilityGapCorruptionError):
        FlywheelPromotionReceiptV1.from_bytes(canonical_json_bytes(raw))
    with pytest.raises(CapabilityGapCorruptionError):
        FlywheelPromotionReceiptV1.from_bytes(
            json.dumps(json.loads(receipt.to_bytes()), indent=2).encode()
        )
    with pytest.raises(CapabilityGapCorruptionError):
        FlywheelPromotionReceiptV1.from_bytes(b"{" + b"x" * MAX_RECEIPT_BYTES + b"}")
    service.close()
