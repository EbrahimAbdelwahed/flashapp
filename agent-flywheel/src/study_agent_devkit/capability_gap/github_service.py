"""Accepted-only GitHub branch and draft pull-request service."""

from __future__ import annotations

import base64
import re
from collections.abc import Callable, Sequence
from contextlib import suppress
from hashlib import sha256
from typing import Any, cast

from study_agent.state import canonical_json_bytes

from .github_contracts import (
    AcceptedPromotionSource,
    AcceptedPromotionViewV1,
    GitHubApi,
    GitHubCommitV1,
    GitHubPublicationAuthorizationV1,
    GitHubPublicationCollisionError,
    GitHubPublicationCorruptionError,
    GitHubPublicationFileV1,
    GitHubPublicationReceiptV1,
    GitHubPublicationRequestV1,
    GitHubPublicationTamperError,
    GitHubPublicationUnavailableError,
    GitHubPublicationValidationError,
    GitHubPullRequestV1,
    _oid,
)
from .github_store import SQLiteGitHubPublicationStore
from .resolution_contracts import FlywheelPromotionBundleV1

_DOMAIN_TREE = b"study-agent-devkit-gap08-tree-v1\0"


def _digest(value: object, field: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise GitHubPublicationValidationError(f"invalid_{field}")
    return value


def _base_ref(ref: str) -> str:
    if ref.startswith("refs/heads/"):
        return ref[len("refs/heads/") :]
    return ref


def _source_promotion(
    source: AcceptedPromotionSource, promotion_id: str
) -> FlywheelPromotionBundleV1:
    try:
        result = source.get_by_promotion_id(promotion_id)
    except AttributeError as error:
        loader = (
            getattr(source, "load_accepted", None)
            or getattr(source, "load", None)
            or getattr(source, "get_accepted_promotion", None)
        )
        if not callable(loader):
            raise GitHubPublicationUnavailableError("promotion_source_unavailable") from error
        result = loader(promotion_id)
    if result is None:
        raise GitHubPublicationUnavailableError("unknown_promotion")
    resolution: object | None = None
    promotion: object = result
    if isinstance(result, tuple) and len(result) == 2:
        pair = cast(tuple[object, object], result)
        resolution, promotion = pair
        outcome = getattr(cast(Any, resolution), "outcome", None)
        if outcome is not None and getattr(outcome, "value", outcome) != "accepted":
            raise GitHubPublicationUnavailableError("nonaccepted_promotion")
    if (
        not isinstance(promotion, FlywheelPromotionBundleV1)
        or promotion.promotion_id != promotion_id
    ):
        raise GitHubPublicationUnavailableError("unknown_promotion")
    try:
        exact = FlywheelPromotionBundleV1.from_bytes(promotion.to_bytes())
    except Exception as error:
        raise GitHubPublicationCorruptionError("invalid_promotion") from error
    if exact != promotion:
        raise GitHubPublicationCorruptionError("noncanonical_promotion")
    if resolution is not None:
        for field in ("resolution_id", "proposal_id", "decision_id"):
            if getattr(resolution, field, None) != getattr(exact, field):
                raise GitHubPublicationCorruptionError("promotion_resolution_mismatch")
    return exact


class GitHubPublicationService:
    """Publish one persisted accepted promotion, never accepting caller bytes."""

    def __init__(
        self,
        source: AcceptedPromotionSource,
        authority: object,
        api: GitHubApi,
        store: SQLiteGitHubPublicationStore,
        *,
        owner: str,
        repository: str,
        base_ref: str,
        sink_id: str,
    ) -> None:
        if not isinstance(store, SQLiteGitHubPublicationStore):
            raise GitHubPublicationValidationError("invalid_publication_store")
        self._source = source
        self._authority = authority
        self._api = api
        self._store = store
        self._owner = owner
        self._repository = repository
        self._base_ref = _base_ref(base_ref)
        self._sink_id = _digest(sink_id, "sink_id")
        self._view_config = AcceptedPromotionViewV1  # retained for type/documentation
        if not owner or not repository or not self._base_ref:
            raise GitHubPublicationValidationError("invalid_github_target")

    @property
    def sink_id(self) -> str:
        return self._sink_id

    def publish_bytes(self, promotion_id: str) -> bytes:
        return self.publish(promotion_id).to_bytes()

    def publish(self, promotion_id: str) -> GitHubPublicationReceiptV1:
        _digest(promotion_id, "promotion_id")
        existing = self._store.get_by_promotion_id(promotion_id)
        if existing is not None and existing[1] is not None:
            self._validate_receipt_target(existing[0], existing[1])
            return existing[1]

        promotion = _source_promotion(self._source, promotion_id)
        view = AcceptedPromotionViewV1(
            promotion, self._owner, self._repository, self._base_ref, self._sink_id
        )
        authorization = self._authorize(view)
        base_oid = self._read_base_oid()
        request = self._plan_request(view, authorization, base_oid)
        claimed, receipt, _winner = self._store.claim(request)
        if receipt is not None:
            self._validate_receipt_target(claimed, receipt)
            return receipt
        # The winner's pinned request is canonical.  A concurrent caller that
        # saw another base head converges here and must never use its own base.
        request = claimed
        lease_token = self._store.acquire_execution_lease(request)
        try:
            receipt = self._apply_remote(request, lease_token)
            self._store.persist_receipt(request, receipt, lease_token=lease_token)
        except BaseException:
            with suppress(Exception):
                self._store.release_execution_lease(request, lease_token)
            raise
        return receipt

    def _validate_receipt_target(
        self, request: GitHubPublicationRequestV1, receipt: GitHubPublicationReceiptV1
    ) -> None:
        if (
            request.owner != self._owner
            or request.repository != self._repository
            or request.base_ref != self._base_ref
            or request.sink_id != self._sink_id
            or receipt.owner != self._owner
            or receipt.repository != self._repository
            or receipt.base_ref != self._base_ref
            or receipt.sink_id != self._sink_id
        ):
            raise GitHubPublicationCollisionError("publication_target_mismatch")

    def _authorize(self, view: AcceptedPromotionViewV1) -> GitHubPublicationAuthorizationV1:
        try:
            authorization = cast(Any, self._authority).authorize(view)
        except AttributeError:
            authorization = cast(Callable[[AcceptedPromotionViewV1], object], self._authority)(
                view
            )
        if not isinstance(authorization, GitHubPublicationAuthorizationV1):
            raise GitHubPublicationUnavailableError("publication_authorization_missing")
        try:
            exact = GitHubPublicationAuthorizationV1.from_bytes(authorization.to_bytes())
        except Exception as error:
            raise GitHubPublicationCorruptionError("invalid_publication_authorization") from error
        if exact != authorization:
            raise GitHubPublicationCorruptionError("noncanonical_publication_authorization")
        if (
            authorization.promotion_id != view.promotion_id
            or authorization.resolution_id != view.promotion.resolution_id
            or authorization.proposal_id != view.promotion.proposal_id
            or authorization.decision_id != view.promotion.decision_id
            or authorization.promotion_bundle_fingerprint != view.promotion_bundle_fingerprint
            or authorization.materialization_plan_fingerprint
            != view.materialization_plan_fingerprint
            or authorization.owner != view.owner
            or authorization.repository != view.repository
            or authorization.base_ref != view.base_ref
            or authorization.operation != "create_branch_and_draft_pr"
        ):
            raise GitHubPublicationCollisionError("publication_authorization_mismatch")
        return authorization

    def _read_base_oid(self) -> str:
        value = self._api.get_ref(self._owner, self._repository, f"refs/heads/{self._base_ref}")
        if value is None:
            raise GitHubPublicationUnavailableError("base_ref_missing")
        try:
            return _oid(value, "base_oid")
        except GitHubPublicationValidationError as error:
            raise GitHubPublicationCorruptionError("invalid_base_oid") from error

    def _plan_request(
        self,
        view: AcceptedPromotionViewV1,
        authorization: GitHubPublicationAuthorizationV1,
        base_oid: str,
    ) -> GitHubPublicationRequestV1:
        plan = view.promotion.materialization_plan
        prefix = f"docs/flywheel-runs/{plan.run_id}/"
        files = tuple(
            # MaterializationPlanV1 already enforces sorted, safe paths and
            # exact bytes; this adapter only adds the repository subtree.
            GitHubPublicationFileV1(
                prefix + item.relative_path, base64.b64encode(item.content).decode("ascii")
            )
            for item in plan.files
        )
        tree_manifest = tuple(
            (item.repository_path, sha256(item.content).hexdigest()) for item in files
        )
        tree_manifest_fingerprint = sha256(
            _DOMAIN_TREE + canonical_json_bytes(cast(Any, tree_manifest))
        ).hexdigest()
        branch = f"codex/capability-gap-{view.promotion_id[:24]}"
        # The request preimage excludes marker; marker then carries the exact
        # fingerprint for commit/PR reconciliation.
        body = {
            "authorization_fingerprint": authorization.authorization_fingerprint,
            "base_oid": base_oid,
            "base_ref": view.base_ref,
            "branch_name": branch,
            "commit_author_email": "study-agent-devkit@noreply.invalid",
            "commit_author_name": "study-agent-devkit",
            "commit_committer_email": "study-agent-devkit@noreply.invalid",
            "commit_committer_name": "study-agent-devkit",
            "commit_message": f"Capability gap {view.promotion_id[:24]} materialization",
            "commit_timestamp": "1970-01-01T00:00:00Z",
            "decision_id": view.promotion.decision_id,
            "files": tuple(item.to_json() for item in files),
            "materialization_plan_fingerprint": view.materialization_plan_fingerprint,
            "marker": "",
            "owner": view.owner,
            "pr_body": "Accepted capability-gap materialization.\n\n",
            "pr_title": f"Capability gap {view.promotion_id[:24]} (draft)",
            "promotion_bundle_fingerprint": view.promotion_bundle_fingerprint,
            "promotion_id": view.promotion_id,
            "proposal_id": view.promotion.proposal_id,
            "repository": view.repository,
            "resolution_id": view.promotion.resolution_id,
            "schema_version": 1,
            "sink_id": view.sink_id,
            "tree_manifest_fingerprint": tree_manifest_fingerprint,
        }
        request_fingerprint = GitHubPublicationRequestV1.derive_fingerprint(body)
        marker = (
            "<!-- study-agent-devkit:capability-gap:v1 "
            f"promotion_id={view.promotion_id} request_fingerprint={request_fingerprint} -->"
        )
        body["marker"] = marker
        body["pr_body"] = cast(str, body["pr_body"]) + marker
        # PR body is part of the canonical request, so recompute once with the
        # final body.  Marker remains excluded from the preimage.
        request_fingerprint = GitHubPublicationRequestV1.derive_fingerprint(body)
        marker = (
            "<!-- study-agent-devkit:capability-gap:v1 "
            f"promotion_id={view.promotion_id} request_fingerprint={request_fingerprint} -->"
        )
        body["marker"] = marker
        body["pr_body"] = "Accepted capability-gap materialization.\n\n" + marker
        publication_id = sha256(
            b"study-agent-devkit-gap08-publication-v1\0" + canonical_json_bytes(cast(Any, body))
        ).hexdigest()
        return GitHubPublicationRequestV1(
            cast(int, body["schema_version"]),
            publication_id,
            cast(str, body["promotion_id"]),
            cast(str, body["resolution_id"]),
            cast(str, body["proposal_id"]),
            cast(str, body["decision_id"]),
            cast(str, body["sink_id"]),
            cast(str, body["owner"]),
            cast(str, body["repository"]),
            cast(str, body["base_ref"]),
            cast(str, body["base_oid"]),
            cast(str, body["branch_name"]),
            cast(str, body["commit_message"]),
            cast(str, body["pr_title"]),
            cast(str, body["pr_body"]),
            cast(str, body["marker"]),
            files,
            cast(str, body["promotion_bundle_fingerprint"]),
            cast(str, body["materialization_plan_fingerprint"]),
            cast(str, body["tree_manifest_fingerprint"]),
            cast(str, body["authorization_fingerprint"]),
            request_fingerprint,
        )

    def _apply_remote(
        self, request: GitHubPublicationRequestV1, lease_token: str
    ) -> GitHubPublicationReceiptV1:
        def lease_check() -> None:
            self._store.renew_execution_lease(request, lease_token)

        lease_check()
        base = self._api.get_commit(request.owner, request.repository, request.base_oid)
        self._remote_oid(base.oid, "base_commit_oid", expected=request.base_oid)
        blobs: dict[str, str] = {}
        for item in request.files:
            lease_check()
            blobs[item.repository_path] = self._api.create_blob(
                request.owner, request.repository, item.content
            )
        for blob_oid in blobs.values():
            self._remote_oid(blob_oid, "blob_oid")
        for item in request.files:
            lease_check()
            if (
                self._api.get_blob(request.owner, request.repository, blobs[item.repository_path])
                != item.content
            ):
                raise GitHubPublicationTamperError("blob_mismatch")
        self._remote_oid(base.tree_oid, "base_tree_oid")
        lease_check()
        tree = self._api.get_tree(request.owner, request.repository, base.tree_oid)
        self._validate_tree_entries(tree)
        self._validate_target_ancestors(tree, request)
        existing = {
            item.path: item
            for item in tree
            if item.path.startswith(f"docs/flywheel-runs/{self._run_id(request)}/")
            and item.entry_type != "tree"
        }
        entries_by_path = {item.path: item for item in tree}
        if set(existing) - set(blobs):
            raise GitHubPublicationTamperError("conflicting_materialization_subtree")
        for path, blob_oid in blobs.items():
            prior = entries_by_path.get(path)
            if prior is not None and (
                prior.mode != "100644" or prior.entry_type != "blob" or prior.oid != blob_oid
            ):
                raise GitHubPublicationTamperError("conflicting_materialization_subtree")
        lease_check()
        tree_oid = self._api.create_tree(
            request.owner,
            request.repository,
            base.tree_oid,
            tuple((path, "100644", oid) for path, oid in sorted(blobs.items())),
        )
        self._remote_oid(tree_oid, "tree_oid")
        lease_check()
        final_tree = self._api.get_tree(request.owner, request.repository, tree_oid)
        self._validate_tree_entries(final_tree)
        self._verify_tree_manifest(final_tree, request, blobs, base_tree=tree)
        lease_check()
        expected_commit = self._api.create_commit(
            request.owner,
            request.repository,
            request.commit_message + "\n\n" + request.marker,
            tree_oid,
            (request.base_oid,),
            author_name=request.commit_author_name,
            author_email=request.commit_author_email,
            author_timestamp=request.commit_timestamp,
            committer_name=request.commit_committer_name,
            committer_email=request.commit_committer_email,
            committer_timestamp=request.commit_timestamp,
        )
        self._verify_commit(expected_commit, request, tree_oid)
        branch_ref = f"refs/heads/{request.branch_name}"
        lease_check()
        branch_oid = self._api.get_ref(request.owner, request.repository, branch_ref)
        if branch_oid is None:
            lease_check()
            self._api.create_ref(
                request.owner, request.repository, branch_ref, expected_commit.oid
            )
            lease_check()
            if (
                self._api.get_ref(request.owner, request.repository, branch_ref)
                != expected_commit.oid
            ):
                raise GitHubPublicationTamperError("ref_mismatch")
        else:
            self._remote_oid(branch_oid, "branch_oid")
            if branch_oid != expected_commit.oid:
                raise GitHubPublicationTamperError("branch_advanced")
        lease_check()
        commit = self._api.get_commit(
            request.owner, request.repository, expected_commit.oid
        )
        self._verify_commit(
            commit, request, tree_oid, expected_oid=expected_commit.oid
        )
        commit_oid = commit.oid
        lease_check()
        pull_requests = self._api.list_pull_requests(
            request.owner, request.repository, request.branch_name, request.base_ref
        )
        exact = self._matching_pull_requests(request, pull_requests)
        if exact:
            pr = exact[0]
        else:
            try:
                pr = self._create_pull_request(lease_check, request)
            except GitHubPublicationCollisionError:
                lease_check()
                exact = self._matching_pull_requests(
                    request,
                    self._api.list_pull_requests(
                        request.owner, request.repository, request.branch_name, request.base_ref
                    ),
                )
                if len(exact) != 1:
                    raise GitHubPublicationTamperError("pull_request_conflict") from None
                pr = exact[0]
        if not exact:
            lease_check()
            exact = self._matching_pull_requests(
                request,
                self._api.list_pull_requests(
                    request.owner, request.repository, request.branch_name, request.base_ref
                ),
            )
            if len(exact) != 1:
                raise GitHubPublicationTamperError("duplicate_pull_request")
            pr = exact[0]
        if (
            pr.head_ref != request.branch_name
            or pr.base_ref != request.base_ref
            or pr.title != request.pr_title
            or pr.body != request.pr_body
            or not pr.draft
            or pr.state != "open"
            or request.marker not in pr.body
        ):
            raise GitHubPublicationTamperError("pull_request_mismatch")
        body = {
            "base_oid": request.base_oid,
            "base_ref": request.base_ref,
            "branch_name": request.branch_name,
            "commit_oid": commit_oid,
            "owner": request.owner,
            "publication_id": request.publication_id,
            "promotion_id": request.promotion_id,
            "pull_request_number": pr.number,
            "pull_request_url": pr.url,
            "request_fingerprint": request.request_fingerprint,
            "repository": request.repository,
            "schema_version": 1,
            "sink_id": request.sink_id,
            "status": "published",
        }
        receipt_id = GitHubPublicationReceiptV1.derive_id(body)
        return GitHubPublicationReceiptV1(
            1,
            receipt_id,
            request.publication_id,
            request.promotion_id,
            request.sink_id,
            request.owner,
            request.repository,
            request.base_ref,
            request.base_oid,
            request.branch_name,
            commit_oid,
            pr.number,
            pr.url,
            request.request_fingerprint,
        )

    def _create_pull_request(
        self, lease_check: Any, request: GitHubPublicationRequestV1
    ) -> GitHubPullRequestV1:
        lease_check()
        return self._api.create_pull_request(
            request.owner,
            request.repository,
            request.branch_name,
            request.base_ref,
            request.pr_title,
            request.pr_body,
            draft=True,
        )

    @staticmethod
    def _run_id(request: GitHubPublicationRequestV1) -> str:
        prefix = "docs/flywheel-runs/"
        first = request.files[0].repository_path[len(prefix) :]
        return first.split("/", 1)[0]

    @staticmethod
    def _remote_oid(value: object, field: str, *, expected: str | None = None) -> str:
        try:
            oid = _oid(value, field)
        except GitHubPublicationValidationError as error:
            raise GitHubPublicationTamperError("invalid_remote_oid") from error
        if expected is not None and oid != expected:
            raise GitHubPublicationTamperError("invalid_base_commit")
        return oid

    @staticmethod
    def _validate_tree_entries(entries: Sequence[object]) -> None:
        by_path: dict[str, object] = {}
        for entry in entries:
            path = getattr(entry, "path", None)
            if not isinstance(path, str) or path in by_path:
                raise GitHubPublicationTamperError("invalid_tree_entries")
            by_path[path] = entry
        for path, _entry in by_path.items():
            parts = path.split("/")
            for index in range(1, len(parts)):
                ancestor = by_path.get("/".join(parts[:index]))
                if ancestor is not None and getattr(ancestor, "entry_type", None) != "tree":
                    raise GitHubPublicationTamperError("non_tree_ancestor")

    @staticmethod
    def _validate_target_ancestors(
        entries: Sequence[object], request: GitHubPublicationRequestV1
    ) -> None:
        entry_path = "path"
        by_path = {
            getattr(entry, entry_path): entry
            for entry in entries
            if isinstance(getattr(entry, entry_path, None), str)
        }
        for file in request.files:
            parts = file.repository_path.split("/")
            for index in range(1, len(parts)):
                ancestor = by_path.get("/".join(parts[:index]))
                if ancestor is not None and getattr(ancestor, "entry_type", None) != "tree":
                    raise GitHubPublicationTamperError("non_tree_ancestor")

    @classmethod
    def _verify_tree_manifest(
        cls,
        entries: Sequence[object],
        request: GitHubPublicationRequestV1,
        blobs: dict[str, str],
        *,
        base_tree: Sequence[object],
    ) -> None:
        run_prefix = f"docs/flywheel-runs/{cls._run_id(request)}/"
        target_ancestors: set[str] = set()
        for file in request.files:
            parts = file.repository_path.split("/")
            target_ancestors.update("/".join(parts[:index]) for index in range(1, len(parts)))

        entry_path = "path"

        def outside_manifest(items: Sequence[object]) -> set[tuple[object, ...]]:
            return {
                (
                    getattr(entry, entry_path, None),
                    getattr(entry, "mode", None),
                    getattr(entry, "entry_type", None),
                    getattr(entry, "oid", None),
                    getattr(entry, "size", None),
                )
                for entry in items
                if isinstance(getattr(entry, entry_path, None), str)
                and not getattr(entry, entry_path).startswith(run_prefix)
                and getattr(entry, entry_path) not in target_ancestors
            }

        if outside_manifest(entries) != outside_manifest(base_tree):
            raise GitHubPublicationTamperError("tree_outside_manifest_mismatch")
        files = {
            getattr(entry, entry_path, None): entry
            for entry in entries
            if isinstance(getattr(entry, entry_path, None), str)
            and getattr(entry, entry_path).startswith(run_prefix)
            and getattr(entry, "entry_type", None) != "tree"
        }
        if set(files) != set(blobs):
            raise GitHubPublicationTamperError("tree_manifest_mismatch")
        for path, blob_oid in blobs.items():
            entry = files[path]
            if (
                getattr(entry, "mode", None) != "100644"
                or getattr(entry, "entry_type", None) != "blob"
                or getattr(entry, "oid", None) != blob_oid
            ):
                raise GitHubPublicationTamperError("tree_manifest_mismatch")

    @staticmethod
    def _matching_pull_requests(
        request: GitHubPublicationRequestV1,
        pull_requests: tuple[GitHubPullRequestV1, ...],
    ) -> list[GitHubPullRequestV1]:
        exact: list[GitHubPullRequestV1] = []
        for pr in pull_requests:
            same_marker = request.marker in pr.body
            same_branch = pr.head_ref == request.branch_name
            if same_marker or same_branch:
                if (
                    pr.head_ref != request.branch_name
                    or pr.base_ref != request.base_ref
                    or pr.title != request.pr_title
                    or pr.body != request.pr_body
                    or not pr.draft
                    or pr.state != "open"
                    or not same_marker
                ):
                    raise GitHubPublicationTamperError("conflicting_pull_request")
                exact.append(pr)
        if len(exact) > 1:
            raise GitHubPublicationTamperError("duplicate_pull_request")
        return exact

    @staticmethod
    def _verify_commit(
        commit: GitHubCommitV1,
        request: GitHubPublicationRequestV1,
        tree_oid: str,
        *,
        expected_oid: str | None = None,
    ) -> None:
        expected_message = request.commit_message + "\n\n" + request.marker
        try:
            _oid(commit.oid, "commit_oid")
            _oid(commit.tree_oid, "commit_tree_oid")
            for parent_oid in commit.parent_oids:
                _oid(parent_oid, "commit_parent_oid")
        except GitHubPublicationValidationError as error:
            raise GitHubPublicationTamperError("commit_mismatch") from error
        if (
            (expected_oid is not None and commit.oid != expected_oid)
            or commit.tree_oid != tree_oid
            or commit.parent_oids != (request.base_oid,)
            or commit.message != expected_message
            or commit.author_name != request.commit_author_name
            or commit.author_email != request.commit_author_email
            or commit.author_timestamp != request.commit_timestamp
            or commit.committer_name != request.commit_committer_name
            or commit.committer_email != request.commit_committer_email
            or commit.committer_timestamp != request.commit_timestamp
        ):
            raise GitHubPublicationTamperError("commit_mismatch")


AcceptedGitHubPublicationService = GitHubPublicationService

__all__ = ["AcceptedGitHubPublicationService", "GitHubPublicationService"]
