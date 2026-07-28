from __future__ import annotations

import json
from pathlib import Path

import pytest
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    AcceptedPromotionViewV1,
    FlywheelPromotionBundleV1,
    GitHubPublicationAuthorizationV1,
    GitHubPublicationCorruptionError,
    GitHubPublicationFileV1,
    GitHubPublicationReceiptV1,
    GitHubPublicationRequestV1,
    GitHubPublicationValidationError,
    plan_fingerprint,
    promotion_fingerprint,
)

from ._support import close_fixture, fixture


def _published_request(
    tmp_path: Path,
) -> tuple[FlywheelPromotionBundleV1, GitHubPublicationRequestV1]:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    row = store.get_by_promotion_id(promotion.promotion_id)
    assert row is not None
    close_fixture(service, resolution, store)
    return promotion, row[0]


def test_request_is_closed_and_contains_no_credential_or_domain_data(tmp_path: Path) -> None:
    promotion, request = _published_request(tmp_path)
    raw = json.loads(request.to_bytes())
    assert set(raw) == {
        "authorization_fingerprint", "base_oid", "base_ref", "branch_name",
        "commit_author_email", "commit_author_name", "commit_committer_email",
        "commit_committer_name", "commit_message", "commit_timestamp", "decision_id",
        "files", "materialization_plan_fingerprint", "marker", "owner", "pr_body",
        "pr_title", "promotion_bundle_fingerprint", "promotion_id", "proposal_id",
        "publication_id", "request_fingerprint", "repository", "resolution_id",
        "schema_version", "sink_id", "tree_manifest_fingerprint",
    }
    forbidden = {"credential", "token", "learner", "delivery", "source_path", "model", "provider"}
    assert not any(any(word in str(value).lower() for word in forbidden) for value in raw.values())
    assert len(promotion_fingerprint(promotion)) == 64
    assert len(plan_fingerprint(promotion.materialization_plan)) == 64


@pytest.mark.parametrize("field", ["schema_version", "publication_id", "request_fingerprint"])
def test_request_codec_rejects_unknown_boolean_or_noncanonical_fields(
    tmp_path: Path, field: str
) -> None:
    _promotion, request = _published_request(tmp_path)
    raw = json.loads(request.to_bytes())
    raw["unknown"] = 1
    with pytest.raises(GitHubPublicationCorruptionError):
        GitHubPublicationRequestV1.from_bytes(canonical_json_bytes(raw))
    raw = json.loads(request.to_bytes())
    raw[field] = True
    with pytest.raises(GitHubPublicationCorruptionError):
        GitHubPublicationRequestV1.from_bytes(canonical_json_bytes(raw))
    with pytest.raises(GitHubPublicationCorruptionError):
        GitHubPublicationRequestV1.from_bytes(
            json.dumps(json.loads(request.to_bytes()), indent=2).encode()
        )


def test_malformed_file_element_is_typed_corruption_not_attribute_error(
    tmp_path: Path,
) -> None:
    _promotion, request = _published_request(tmp_path)
    raw = json.loads(request.to_bytes())
    raw["files"] = ["not-an-object"]
    with pytest.raises(GitHubPublicationCorruptionError):
        GitHubPublicationRequestV1.from_bytes(canonical_json_bytes(raw))


def test_file_path_and_base64_boundaries_are_closed() -> None:
    with pytest.raises(GitHubPublicationValidationError):
        GitHubPublicationFileV1("docs/flywheel-runs/run/../escape.txt", "YQ==")
    with pytest.raises(GitHubPublicationValidationError):
        GitHubPublicationFileV1("docs/flywheel-runs/run/file.txt", "not-base64!")


def test_authorization_and_receipt_codecs_reject_extra_keys_and_boolean_ints(
    tmp_path: Path,
) -> None:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    view = AcceptedPromotionViewV1(promotion, "octo", "study", "main", "a" * 64)
    authorization = GitHubPublicationAuthorizationV1.create(view, authorization_id="d" * 64)
    raw = json.loads(authorization.to_bytes())
    raw["unexpected"] = 1
    with pytest.raises(GitHubPublicationCorruptionError):
        GitHubPublicationAuthorizationV1.from_bytes(canonical_json_bytes(raw))
    raw = json.loads(authorization.to_bytes())
    raw["schema_version"] = True
    with pytest.raises(GitHubPublicationCorruptionError):
        GitHubPublicationAuthorizationV1.from_bytes(canonical_json_bytes(raw))
    service.publish(promotion.promotion_id)
    row = store.get_by_promotion_id(promotion.promotion_id)
    assert row is not None and row[1] is not None
    receipt = row[1]
    receipt_raw = json.loads(receipt.to_bytes())
    receipt_raw["pull_request_number"] = True
    with pytest.raises(GitHubPublicationCorruptionError):
        GitHubPublicationReceiptV1.from_bytes(canonical_json_bytes(receipt_raw))
    close_fixture(service, resolution, store)
