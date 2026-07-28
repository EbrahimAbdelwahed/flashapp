from __future__ import annotations

from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from study_agent_devkit.capability_gap import (
    AcceptedPromotionViewV1,
    GitHubPublicationAuthorizationV1,
    GitHubPublicationCollisionError,
    GitHubPublicationCorruptionError,
    GitHubPublicationReceiptV1,
    GitHubPublicationRequestV1,
    GitHubPublicationService,
    GitHubPublicationTamperError,
    GitHubPublicationUnavailableError,
    GitHubPullRequestV1,
    GitHubTreeEntryV1,
)

from ._support import (
    BASE_REF,
    OWNER,
    REPOSITORY,
    SINK_ID,
    Authority,
    ScriptedApi,
    Source,
    close_fixture,
    fixture,
)


def test_accepted_publication_maps_exact_run_paths_bytes_and_metadata(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    receipt = service.publish(promotion.promotion_id)
    row = store.get_by_promotion_id(promotion.promotion_id)
    assert row is not None
    request = row[0]
    expected = {
        f"docs/flywheel-runs/{promotion.materialization_plan.run_id}/{item.relative_path}": (
            item.content
        )
        for item in promotion.materialization_plan.files
    }
    assert {item.repository_path: item.content for item in request.files} == expected
    assert request.branch_name == f"codex/capability-gap-{promotion.promotion_id[:24]}"
    assert request.commit_timestamp == "1970-01-01T00:00:00Z"
    assert request.marker in request.commit_message + request.pr_body
    assert api.commits[receipt.commit_oid].parent_oids == (request.base_oid,)
    final_tree = api.trees[api.commits[receipt.commit_oid].tree_oid]
    assert any(
        entry.path == "README.md" and entry.oid == "a" * len(request.base_oid)
        for entry in final_tree
    )
    assert all(
        entry.path.startswith(f"docs/flywheel-runs/{promotion.materialization_plan.run_id}/")
        or entry.path == "README.md"
        for entry in final_tree
    )
    assert api.calls.count("create_blob") == len(expected)
    assert api.calls.count("create_tree") == 1
    assert api.calls.count("create_commit") == 1
    assert api.calls.count("create_ref") == 1
    assert api.calls.count("create_pull_request") == 1
    close_fixture(service, resolution, store)


@pytest.mark.parametrize("bad_kind", ["unknown", "rejected", "forged", "corrupt"])
def test_unknown_nonaccepted_forged_or_corrupt_source_stops_before_authority_and_api(
    tmp_path: Path, bad_kind: str
) -> None:
    service0, promotion, resolution, _src0, _api0, _auth0, _src02, store0 = fixture(tmp_path)
    close_fixture(service0, resolution, store0)
    api = ScriptedApi()
    authority = Authority()
    if bad_kind == "unknown":
        source = Source(None)
    elif bad_kind == "rejected":
        source = Source((SimpleNamespace(outcome="rejected"), promotion))
    elif bad_kind == "forged":
        source = Source(
            SimpleNamespace(promotion_id=promotion.promotion_id, to_bytes=lambda: b"forged")
        )
    else:
        source = Source(SimpleNamespace(promotion_id=promotion.promotion_id))
    from study_agent_devkit.capability_gap import SQLiteGitHubPublicationStore

    store = SQLiteGitHubPublicationStore(tmp_path / f"{bad_kind}.sqlite3")
    service = GitHubPublicationService(
        source,
        authority,
        api,
        store,
        owner=OWNER,
        repository=REPOSITORY,
        base_ref=BASE_REF,
        sink_id=SINK_ID,
    )
    with pytest.raises((GitHubPublicationUnavailableError, GitHubPublicationCorruptionError)):
        service.publish(promotion.promotion_id)
    assert authority.calls == 0
    assert api.calls == []
    store.close()


@pytest.mark.parametrize("field", ["owner", "repository", "base_ref"])
def test_authorization_target_binding_is_exact(tmp_path: Path, field: str) -> None:
    service0, promotion, resolution0, _src0, _api0, _auth0, _src02, store0 = fixture(tmp_path)
    close_fixture(service0, resolution0, store0)
    kwargs = {"owner": OWNER, "repository": REPOSITORY, "base_ref": BASE_REF}
    kwargs[field] = "other" if field != "base_ref" else "develop"
    auth = GitHubPublicationAuthorizationV1.create(
        AcceptedPromotionViewV1(
            promotion, kwargs["owner"], kwargs["repository"], kwargs["base_ref"], SINK_ID
        ),
        authorization_id="d" * 64,
    )
    api = ScriptedApi()
    authority = Authority(result=auth)
    source = Source(promotion)
    from study_agent_devkit.capability_gap import SQLiteGitHubPublicationStore

    store = SQLiteGitHubPublicationStore(tmp_path / "binding.sqlite3")
    service = GitHubPublicationService(
        source,
        authority,
        api,
        store,
        owner=OWNER,
        repository=REPOSITORY,
        base_ref=BASE_REF,
        sink_id=SINK_ID,
    )
    with pytest.raises(GitHubPublicationCollisionError):
        service.publish(promotion.promotion_id)
    assert api.calls == []
    store.close()


@pytest.mark.parametrize("loss", ["create_commit", "create_ref", "create_pull_request"])
def test_process_loss_after_remote_step_converges_without_duplicate_branch_or_pr(
    tmp_path: Path, loss: str
) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    api.fail_after = loss
    with pytest.raises(RuntimeError):
        service.publish(promotion.promotion_id)
    api.calls.clear()
    receipt = service.publish(promotion.promotion_id)
    assert len(api.pull_requests) == 1
    assert list(ref for ref in api.refs if ref.startswith("refs/heads/codex/capability-gap-")) == [
        f"refs/heads/{receipt.branch_name}"
    ]
    stored = store.get_by_promotion_id(promotion.promotion_id)
    assert stored is not None
    assert stored[1] == receipt
    close_fixture(service, resolution, store)


def test_pr_conflict_after_remote_creation_relists_without_duplicate(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    original_create = api.create_pull_request

    def create_then_conflict(
        owner: str,
        repository: str,
        head_ref: str,
        base_ref: str,
        title: str,
        body: str,
        *,
        draft: bool,
    ) -> GitHubPullRequestV1:
        original_create(owner, repository, head_ref, base_ref, title, body, draft=draft)
        raise GitHubPublicationCollisionError("remote_conflict_after_create")

    with patch.object(api, "create_pull_request", side_effect=create_then_conflict):
        receipt = service.publish(promotion.promotion_id)
    assert len(api.pull_requests) == 1
    stored = store.get_by_promotion_id(promotion.promotion_id)
    assert stored is not None
    assert stored[1] == receipt
    close_fixture(service, resolution, store)


def test_exact_retry_after_restart_returns_receipt_without_source_authority_or_api(
    tmp_path: Path,
) -> None:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(tmp_path)
    first = service.publish(promotion.promotion_id)
    store.close()
    source2 = Source(None)
    authority2 = Authority()
    api2 = ScriptedApi()
    from study_agent_devkit.capability_gap import SQLiteGitHubPublicationStore

    store2 = SQLiteGitHubPublicationStore(tmp_path / "github.sqlite3")
    service2 = GitHubPublicationService(
        source2,
        authority2,
        api2,
        store2,
        owner=OWNER,
        repository=REPOSITORY,
        base_ref=BASE_REF,
        sink_id=SINK_ID,
    )
    assert service2.publish(promotion.promotion_id).to_bytes() == first.to_bytes()
    assert source2.calls == 0 and authority2.calls == 0 and api2.calls == []
    resolution.close()
    store2.close()


def test_process_loss_before_receipt_persistence_reconciles_exact_remote_state(
    tmp_path: Path,
) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    original = store.persist_receipt
    calls = {"count": 0}

    def lose_once(
        request: GitHubPublicationRequestV1,
        receipt: GitHubPublicationReceiptV1,
        *,
        lease_token: str | None = None,
    ) -> None:
        calls["count"] += 1
        if calls["count"] == 1:
            raise RuntimeError("receipt_persistence_loss")
        return original(request, receipt, lease_token=lease_token)

    with patch.object(store, "persist_receipt", side_effect=lose_once), pytest.raises(
        RuntimeError
    ):
        service.publish(promotion.promotion_id)
    first_remote_calls = len(api.calls)
    receipt = service.publish(promotion.promotion_id)
    assert len(api.pull_requests) == 1
    assert len(api.calls) > first_remote_calls
    stored = store.get_by_promotion_id(promotion.promotion_id)
    assert stored is not None
    assert stored[1] == receipt
    close_fixture(service, resolution, store)


def test_remote_subtree_conflict_fails_closed_before_commit_and_ref(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    api.trees[api.base_tree_oid] = (
        GitHubTreeEntryV1(
            f"docs/flywheel-runs/{promotion.materialization_plan.run_id}/unexpected.txt",
            "100644",
            "blob",
            "e" * 64,
        ),
    )
    with pytest.raises(GitHubPublicationTamperError):
        service.publish(promotion.promotion_id)
    assert "create_commit" not in api.calls and "create_ref" not in api.calls
    close_fixture(service, resolution, store)


def test_non_tree_target_ancestor_fails_before_tree_creation(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    ancestor = f"docs/flywheel-runs/{promotion.materialization_plan.run_id}"
    api.trees[api.base_tree_oid] = (GitHubTreeEntryV1(ancestor, "100644", "blob", "e" * 64),)
    with pytest.raises(GitHubPublicationTamperError):
        service.publish(promotion.promotion_id)
    assert "create_tree" not in api.calls
    close_fixture(service, resolution, store)


def test_final_tree_outside_materialization_tamper_fails_closed(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    original_create_tree = api.create_tree

    def tamper(
        owner: str,
        repository: str,
        base_tree_oid: str,
        entries: tuple[tuple[str, str, str], ...],
    ) -> str:
        oid = original_create_tree(owner, repository, base_tree_oid, entries)
        api.trees[oid] = tuple(
            GitHubTreeEntryV1("README.md", "100644", "blob", "f" * len(api.base_oid), 7)
            if entry.path == "README.md"
            else entry
            for entry in api.trees[oid]
        )
        return oid

    with patch.object(api, "create_tree", side_effect=tamper), pytest.raises(
        GitHubPublicationTamperError
    ):
        service.publish(promotion.promotion_id)
    close_fixture(service, resolution, store)


def test_final_tree_empty_outside_directory_tamper_fails_closed(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    api.trees[api.base_tree_oid] = (
        GitHubTreeEntryV1("README.md", "100644", "blob", "a" * len(api.base_oid), 7),
        GitHubTreeEntryV1("docs/other", "040000", "tree", "d" * len(api.base_oid)),
    )
    original_create_tree = api.create_tree

    def empty_directory(
        owner: str, repository: str, base_tree_oid: str, entries: tuple[tuple[str, str, str], ...]
    ) -> str:
        oid = original_create_tree(owner, repository, base_tree_oid, entries)
        api.trees[oid] = tuple(entry for entry in api.trees[oid] if entry.path != "docs/other")
        return oid

    with patch.object(api, "create_tree", side_effect=empty_directory), pytest.raises(
        GitHubPublicationTamperError
    ):
        service.publish(promotion.promotion_id)
    close_fixture(service, resolution, store)


@pytest.mark.parametrize("mode,entry_type", [("100755", "blob"), ("100644", "tree")])
def test_existing_tree_mode_and_type_tamper_fails_closed(
    tmp_path: Path, mode: str, entry_type: str
) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    path = (
        f"docs/flywheel-runs/{promotion.materialization_plan.run_id}/"
        f"{promotion.materialization_plan.files[0].relative_path}"
    )
    blob = api._oid(promotion.materialization_plan.files[0].content)
    api.trees[api.base_tree_oid] = (GitHubTreeEntryV1(path, mode, entry_type, blob),)
    with pytest.raises(GitHubPublicationTamperError):
        service.publish(promotion.promotion_id)
    close_fixture(service, resolution, store)


def test_moving_base_after_claim_keeps_pinned_base(tmp_path: Path) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    api.fail_after = "get_commit"
    with pytest.raises(RuntimeError):
        service.publish(promotion.promotion_id)
    claimed = store.get_by_promotion_id(promotion.promotion_id)
    assert claimed is not None
    api.refs["refs/heads/main"] = "f" * 64
    api.fail_after = None
    second = service.publish(promotion.promotion_id)
    assert second.base_oid == claimed[0].base_oid
    close_fixture(service, resolution, store)


@pytest.mark.parametrize(
    "tamper", ["parent", "tree", "message", "author", "committer", "time", "advanced"]
)
def test_existing_branch_commit_metadata_or_advance_fails_closed(
    tmp_path: Path, tamper: str
) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    row = store.get_by_promotion_id(promotion.promotion_id)
    assert row is not None
    request = row[0]
    store.connection.execute(
        "UPDATE github_publications SET receipt_bytes=NULL WHERE promotion_id=?",
        (promotion.promotion_id,),
    )
    branch_ref = f"refs/heads/{request.branch_name}"
    good_oid = api.refs[branch_ref]
    good = api.commits[good_oid]
    if tamper == "advanced":
        api.refs[branch_ref] = "f" * 64
        api.commits["f" * 64] = replace(good, oid="f" * 64)
    else:
        altered = {
            "parent": replace(good, parent_oids=(request.base_oid, "e" * 64)),
            "tree": replace(good, tree_oid="e" * 64),
            "message": replace(good, message="tampered"),
            "author": replace(good, author_name="attacker"),
            "committer": replace(good, committer_email="attacker@example.invalid"),
            "time": replace(good, committer_timestamp="2020-01-01T00:00:00Z"),
        }[tamper]
        api.commits[good_oid] = altered
    with pytest.raises(GitHubPublicationTamperError):
        service.publish(promotion.promotion_id)
    close_fixture(service, resolution, store)


@pytest.mark.parametrize(
    "variant",
    [
        "duplicate",
        "non_draft",
        "wrong_head",
        "wrong_base",
        "wrong_title",
        "wrong_body",
        "wrong_marker",
    ],
)
def test_existing_pull_request_collision_fails_closed(tmp_path: Path, variant: str) -> None:
    service, promotion, resolution, _source, api, _authority, _source2, store = fixture(tmp_path)
    service.publish(promotion.promotion_id)
    row = store.get_by_promotion_id(promotion.promotion_id)
    assert row is not None
    store.connection.execute(
        "UPDATE github_publications SET receipt_bytes=NULL WHERE promotion_id=?",
        (promotion.promotion_id,),
    )
    original = api.pull_requests[0]
    if variant == "duplicate":
        api.pull_requests.append(original)
    else:
        api.pull_requests[0] = replace(
            original,
            draft=False if variant == "non_draft" else original.draft,
            head_ref="wrong" if variant == "wrong_head" else original.head_ref,
            base_ref="develop" if variant == "wrong_base" else original.base_ref,
            title="wrong" if variant == "wrong_title" else original.title,
            body="wrong" if variant in {"wrong_body", "wrong_marker"} else original.body,
        )
    with pytest.raises(GitHubPublicationTamperError):
        service.publish(promotion.promotion_id)
    close_fixture(service, resolution, store)


def test_40_and_64_character_remote_oids_are_supported_but_fingerprints_remain_64(
    tmp_path: Path,
) -> None:
    service, promotion, resolution, _source, _api, _authority, _source2, store = fixture(
        tmp_path, oid_length=40
    )
    # GitHub currently returns SHA-1 OIDs (40 hex); SHA-256 OIDs are 64 hex.
    receipt = service.publish(promotion.promotion_id)
    assert len(receipt.base_oid) == 40
    assert len(receipt.commit_oid) == 40
    assert len(receipt.request_fingerprint) == 64
    assert len(promotion.promotion_id) == 64
    close_fixture(service, resolution, store)
