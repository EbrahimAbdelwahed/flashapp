from __future__ import annotations

import time
from dataclasses import replace
from pathlib import Path

import pytest

from study_agent_devkit.capability_gap import (
    GitHubPublicationAuthorizationV1,
    GitHubPublicationCollisionError,
    GitHubPublicationCorruptionError,
    GitHubPublicationRetryableError,
    SQLiteGitHubPublicationStore,
)

from ._support import close_fixture, fixture


def test_sqlite_schema_has_closed_projection_and_unique_publication_promotion(
    tmp_path: Path,
) -> None:
    service, _promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    columns = tuple(
        row[1:] for row in store.connection.execute("PRAGMA table_info(github_publications)")
    )
    assert columns == (
        ("publication_pk", "INTEGER", 0, None, 1),
        ("publication_id", "TEXT", 1, None, 0),
        ("promotion_id", "TEXT", 1, None, 0),
        ("sink_id", "TEXT", 1, None, 0),
        ("owner", "TEXT", 1, None, 0),
        ("repository", "TEXT", 1, None, 0),
        ("base_ref", "TEXT", 1, None, 0),
        ("base_oid", "TEXT", 1, None, 0),
        ("request_bytes", "BLOB", 1, None, 0),
        ("receipt_bytes", "BLOB", 0, None, 0),
        ("lease_token", "TEXT", 0, None, 0),
        ("lease_until", "REAL", 0, None, 0),
    )
    indexes = {
        tuple(item[2] for item in store.connection.execute(f"PRAGMA index_info({row[1]!s})"))
        for row in store.connection.execute("PRAGMA index_list(github_publications)")
        if row[3] == "u"
    }
    assert indexes == {("publication_id",), ("promotion_id",)}
    close_fixture(service, resolution, store)


def test_request_bytes_are_source_of_truth_and_projection_tamper_is_corruption(
    tmp_path: Path,
) -> None:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    store.connection.execute(
        "UPDATE github_publications SET owner='forged' WHERE promotion_id=?",
        (promotion.promotion_id,),
    )
    with pytest.raises(GitHubPublicationCorruptionError):
        store.get_by_promotion_id(promotion.promotion_id)
    close_fixture(service, resolution, store)


def test_duplicate_publication_and_promotion_claims_collide(tmp_path: Path) -> None:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    row = store.get_by_promotion_id(promotion.promotion_id)
    assert row is not None
    request = row[0]
    with pytest.raises(GitHubPublicationCollisionError):
        store.claim(
            request.__class__(
                request.schema_version,
                "e" * 64,
                request.promotion_id,
                request.resolution_id,
                request.proposal_id,
                request.decision_id,
                request.sink_id,
                request.owner,
                request.repository,
                request.base_ref,
                request.base_oid,
                request.branch_name,
                request.commit_message,
                request.pr_title,
                request.pr_body,
                request.marker,
                request.files,
                request.promotion_bundle_fingerprint,
                request.materialization_plan_fingerprint,
                request.tree_manifest_fingerprint,
                request.authorization_fingerprint,
                request.request_fingerprint,
                request.commit_author_name,
                request.commit_author_email,
                request.commit_committer_name,
                request.commit_committer_email,
                request.commit_timestamp,
            )
        )
    close_fixture(service, resolution, store)


def test_corrupt_request_or_receipt_fails_before_client_effects(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    store.connection.execute(
        "UPDATE github_publications SET request_bytes=? WHERE promotion_id=?",
        (b"{}", promotion.promotion_id),
    )
    api.calls.clear()
    with pytest.raises(GitHubPublicationCorruptionError):
        store.get_by_promotion_id(promotion.promotion_id)
    assert api.calls == []
    close_fixture(service, resolution, store)


def test_corrupt_receipt_fails_before_client_effects(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    store.connection.execute(
        "UPDATE github_publications SET receipt_bytes=? WHERE promotion_id=?",
        (b"{}", promotion.promotion_id),
    )
    api.calls.clear()
    with pytest.raises(GitHubPublicationCorruptionError):
        store.get_by_promotion_id(promotion.promotion_id)
    assert api.calls == []
    close_fixture(service, resolution, store)


def test_execution_lease_fences_concurrent_holder_and_expires(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, authority, _source2, store = fixture(tmp_path)
    view = service._view_config(promotion, "octo", "study", "main", service.sink_id)
    authorization = authority.authorize(view)
    assert isinstance(authorization, GitHubPublicationAuthorizationV1)
    request = service._plan_request(view, authorization, api.base_oid)
    claimed, receipt, _winner = store.claim(request)
    assert claimed == request and receipt is None
    now = [time.time()]
    token = store.acquire_execution_lease(request)
    other = SQLiteGitHubPublicationStore(
        tmp_path / "github.sqlite3", clock=lambda: now[0], lease_ttl=10
    )
    with pytest.raises(GitHubPublicationRetryableError):
        other.acquire_execution_lease(request)
    now[0] += 301.0
    takeover = other.acquire_execution_lease(request)
    assert takeover != token
    with pytest.raises(GitHubPublicationRetryableError):
        store.renew_execution_lease(request, token)
    other.close()
    close_fixture(service, resolution, store)


@pytest.mark.parametrize(
    "token,until",
    [("a" * 63, 100.0), ("a" * 64, float("inf")), (None, 100.0)],
)
def test_malformed_lease_pair_is_corruption(
    tmp_path: Path, token: str | None, until: float
) -> None:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    store.connection.execute(
        "UPDATE github_publications SET receipt_bytes=NULL, lease_token=?, "
        "lease_until=? WHERE promotion_id=?",
        (token, until, promotion.promotion_id),
    )
    with pytest.raises(GitHubPublicationCorruptionError):
        store.get_by_promotion_id(promotion.promotion_id)
    close_fixture(service, resolution, store)


def test_receipt_full_target_binding_is_corruption(tmp_path: Path) -> None:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    row = store.get_by_promotion_id(promotion.promotion_id)
    assert row is not None and row[1] is not None
    receipt = row[1]
    body = receipt._body()
    body["owner"] = "attacker"
    forged = replace(receipt, owner="attacker", receipt_id=receipt.derive_id(body))
    store.connection.execute(
        "UPDATE github_publications SET receipt_bytes=? WHERE promotion_id=?",
        (forged.to_bytes(), promotion.promotion_id),
    )
    with pytest.raises(GitHubPublicationCorruptionError):
        store.get_by_promotion_id(promotion.promotion_id)
    close_fixture(service, resolution, store)
