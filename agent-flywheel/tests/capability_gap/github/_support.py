from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

from resolution.materialization._support import accepted_bundle
from study_agent.state import canonical_json_bytes

from study_agent_devkit.capability_gap import (
    AcceptedPromotionViewV1,
    FlywheelPromotionBundleV1,
    GitHubCommitV1,
    GitHubPublicationAuthorizationV1,
    GitHubPublicationService,
    GitHubPullRequestV1,
    GitHubTreeEntryV1,
    SQLiteGitHubPublicationStore,
)

OWNER = "octo"
REPOSITORY = "study"
BASE_REF = "main"
SINK_ID = "a" * 64
BASE_OID = "b" * 64
BASE_TREE = "c" * 64


class Source:
    def __init__(self, promotion: object | None) -> None:
        self.promotion = promotion
        self.calls = 0

    def get_by_promotion_id(self, promotion_id: str) -> object | None:
        self.calls += 1
        if (
            isinstance(self.promotion, FlywheelPromotionBundleV1)
            and self.promotion.promotion_id == promotion_id
        ):
            return self.promotion
        return self.promotion


class Authority:
    def __init__(self, *, result: object | None = None) -> None:
        self.result = result
        self.calls = 0

    def authorize(self, view: AcceptedPromotionViewV1) -> object:
        self.calls += 1
        if self.result is not None:
            return self.result
        return GitHubPublicationAuthorizationV1.create(view, authorization_id="d" * 64)


class ScriptedApi:
    """Deterministic in-memory GitHub Git-database/PR port."""

    def __init__(self, *, oid_length: int = 64) -> None:
        self.oid_length = oid_length
        self.base_oid = "b" * oid_length
        self.base_tree_oid = "c" * oid_length
        self.refs: dict[str, str] = {"refs/heads/main": self.base_oid}
        self.commits: dict[str, GitHubCommitV1] = {
            self.base_oid: GitHubCommitV1(
                self.base_oid,
                self.base_tree_oid,
                (),
                "base",
                "base",
                "base@example.invalid",
                "1970-01-01T00:00:00Z",
                "base",
                "base@example.invalid",
                "1970-01-01T00:00:00Z",
            )
        }
        self.trees: dict[str, tuple[GitHubTreeEntryV1, ...]] = {
            self.base_tree_oid: (
                GitHubTreeEntryV1(
                    "README.md", "100644", "blob", "a" * self.oid_length, 7
                ),
            )
        }
        self.blobs: dict[str, bytes] = {}
        self.pull_requests: list[GitHubPullRequestV1] = []
        self.calls: list[str] = []
        self.fail_after: str | None = None
        self._failure_used = False

    def _oid(self, payload: bytes) -> str:
        return hashlib.sha256(payload).hexdigest()[: self.oid_length]

    def _maybe_fail(self, operation: str) -> None:
        if self.fail_after == operation and not self._failure_used:
            self._failure_used = True
            raise RuntimeError(f"scripted_{operation}_loss")

    def get_ref(self, owner: str, repository: str, ref: str) -> str | None:
        self.calls.append("get_ref")
        return self.refs.get(ref)

    def get_commit(self, owner: str, repository: str, oid: str) -> GitHubCommitV1:
        self.calls.append("get_commit")
        commit = self.commits[oid]
        self._maybe_fail("get_commit")
        return commit

    def get_tree(
        self, owner: str, repository: str, tree_oid: str
    ) -> tuple[GitHubTreeEntryV1, ...]:
        self.calls.append("get_tree")
        return self.trees.get(tree_oid, ())

    def get_blob(self, owner: str, repository: str, oid: str) -> bytes:
        self.calls.append("get_blob")
        return self.blobs[oid]

    def create_blob(self, owner: str, repository: str, content: bytes) -> str:
        self.calls.append("create_blob")
        oid = self._oid(content)
        self.blobs[oid] = content
        self._maybe_fail("create_blob")
        return oid

    def create_tree(
        self,
        owner: str,
        repository: str,
        base_tree_oid: str,
        entries: tuple[tuple[str, str, str], ...],
    ) -> str:
        self.calls.append("create_tree")
        oid = self._oid(canonical_json_bytes({"base": base_tree_oid, "entries": entries}))
        prior = {entry.path: entry for entry in self.trees.get(base_tree_oid, ())}
        prior.update(
            {
                path: GitHubTreeEntryV1(
                    path, mode, "blob", blob_oid, len(self.blobs.get(blob_oid, b""))
                )
                for path, mode, blob_oid in entries
            }
        )
        self.trees[oid] = tuple(prior[path] for path in sorted(prior))
        self._maybe_fail("create_tree")
        return oid

    def create_commit(
        self,
        owner: str,
        repository: str,
        message: str,
        tree_oid: str,
        parent_oids: tuple[str, ...],
        *,
        author_name: str,
        author_email: str,
        author_timestamp: str,
        committer_name: str,
        committer_email: str,
        committer_timestamp: str,
    ) -> GitHubCommitV1:
        self.calls.append("create_commit")
        oid = self._oid(
            canonical_json_bytes(
                {
                    "message": message,
                    "tree": tree_oid,
                    "parents": parent_oids,
                    "author": (author_name, author_email, author_timestamp),
                    "committer": (
                        committer_name,
                        committer_email,
                        committer_timestamp,
                    ),
                }
            )
        )
        commit = GitHubCommitV1(
            oid,
            tree_oid,
            parent_oids,
            message,
            author_name,
            author_email,
            author_timestamp,
            committer_name,
            committer_email,
            committer_timestamp,
        )
        self.commits.setdefault(oid, commit)
        self._maybe_fail("create_commit")
        return commit

    def create_ref(self, owner: str, repository: str, ref: str, oid: str) -> None:
        self.calls.append("create_ref")
        self.refs[ref] = oid
        self._maybe_fail("create_ref")

    def list_pull_requests(
        self, owner: str, repository: str, head_ref: str, base_ref: str
    ) -> tuple[GitHubPullRequestV1, ...]:
        self.calls.append("list_pull_requests")
        return tuple(self.pull_requests)

    def create_pull_request(
        self,
        owner: str,
        repository: str,
        head_ref: str,
        base_ref: str,
        title: str,
        body: str,
        *,
        draft: bool,
    ) -> GitHubPullRequestV1:
        self.calls.append("create_pull_request")
        pr = GitHubPullRequestV1(
            len(self.pull_requests) + 1,
            f"https://github.com/{owner}/{repository}/pull/{len(self.pull_requests) + 1}",
            head_ref,
            base_ref,
            title,
            body,
            draft,
        )
        self.pull_requests.append(pr)
        self._maybe_fail("create_pull_request")
        return pr


def fixture(
    tmp_path: Path,
    *,
    oid_length: int = 64,
    api: ScriptedApi | None = None,
    authority: Authority | None = None,
    source: Source | None = None,
) -> tuple[
    GitHubPublicationService,
    FlywheelPromotionBundleV1,
    Any,
    Any,
    ScriptedApi,
    Authority,
    Source,
    SQLiteGitHubPublicationStore,
]:
    resolution_service, promotion, _ = accepted_bundle(tmp_path)
    scripted = api or ScriptedApi(oid_length=oid_length)
    auth = authority or Authority()
    src = source or Source(promotion)
    store = SQLiteGitHubPublicationStore(tmp_path / "github.sqlite3")
    service = GitHubPublicationService(
        src,
        auth,
        scripted,
        store,
        owner=OWNER,
        repository=REPOSITORY,
        base_ref=BASE_REF,
        sink_id=SINK_ID,
    )
    return service, promotion, resolution_service, src, scripted, auth, src, store


def close_fixture(
    service: GitHubPublicationService,
    resolution_service: Any,
    store: SQLiteGitHubPublicationStore,
) -> None:
    resolution_service.close()
    store.close()


def auth_for(
    promotion: FlywheelPromotionBundleV1,
    *,
    owner: str = OWNER,
    repository: str = REPOSITORY,
    base_ref: str = BASE_REF,
) -> GitHubPublicationAuthorizationV1:
    view = AcceptedPromotionViewV1(promotion, owner, repository, base_ref, SINK_ID)
    return GitHubPublicationAuthorizationV1.create(view, authorization_id="d" * 64)
