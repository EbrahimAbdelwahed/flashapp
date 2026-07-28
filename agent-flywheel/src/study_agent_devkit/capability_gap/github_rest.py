"""Small stdlib-only GitHub REST client for the publication API port."""

from __future__ import annotations

import base64
import json
from collections.abc import Callable, Mapping
from http.client import HTTPMessage
from typing import IO, Any, cast
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

from .github_contracts import (
    CredentialProvider,
    GitHubApi,
    GitHubCommitV1,
    GitHubPublicationAuthenticationError,
    GitHubPublicationCollisionError,
    GitHubPublicationCorruptionError,
    GitHubPublicationPermissionError,
    GitHubPublicationRetryableError,
    GitHubPullRequestV1,
    GitHubTreeEntryV1,
)

_ACCEPT = "application/vnd.github+json"
_API_VERSION = "2026-03-10"
_MAX_REQUEST = 8 * 1024 * 1024
_MAX_RESPONSE = 16 * 1024 * 1024
_MAX_RETRY_AFTER = 60
_MAX_CREDENTIAL_BYTES = 4096


class _SameOriginRedirectHandler(HTTPRedirectHandler):
    """Reject a cross-origin redirect before urllib sends the next request."""

    def __init__(self, origin: str) -> None:
        super().__init__()
        self._origin = origin

    def redirect_request(
        self,
        req: Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: HTTPMessage,
        newurl: str,
    ) -> Request | None:
        parsed = urlparse(newurl)
        origin = f"{parsed.scheme}://{parsed.netloc}"
        if origin != self._origin:
            raise GitHubPublicationPermissionError("github_redirect_denied")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class GitHubRestClient(GitHubApi):
    """GitHub Git-database and draft-PR API with injected credentials/opener."""

    def __init__(
        self,
        credential_provider: CredentialProvider,
        *,
        opener: Callable[..., Any] | None = None,
        api_origin: str = "https://api.github.com",
        max_response_bytes: int = _MAX_RESPONSE,
        transport_timeout: float = 20.0,
        lease_ttl: float = 300.0,
    ) -> None:
        if not callable(credential_provider):
            raise GitHubPublicationAuthenticationError("invalid_credential_provider")
        parsed = urlparse(api_origin)
        if (
            parsed.scheme not in {"https", "http"}
            or not parsed.netloc
            or parsed.path not in {"", "/"}
        ):
            raise ValueError("invalid_github_api_origin")
        if max_response_bytes <= 0 or max_response_bytes > _MAX_RESPONSE:
            raise ValueError("invalid_response_limit")
        if (
            isinstance(transport_timeout, bool)
            or not isinstance(transport_timeout, (int, float))
            or transport_timeout <= 0
            or isinstance(lease_ttl, bool)
            or not isinstance(lease_ttl, (int, float))
            or lease_ttl <= 0
            or transport_timeout * 10 >= lease_ttl
        ):
            raise ValueError("invalid_transport_timeout")
        if opener is not None and getattr(opener, "follows_redirects", None) is not False:
            raise ValueError("injected_opener_must_not_follow_redirects")
        self._credential_provider = credential_provider
        self._origin = f"{parsed.scheme}://{parsed.netloc}"
        self._transport_timeout = float(transport_timeout)
        self._default_opener = opener is None
        self._opener: Callable[..., Any] = opener or cast(
            Callable[..., Any], build_opener(_SameOriginRedirectHandler(self._origin)).open
        )
        self._max_response = max_response_bytes

    def _request(
        self, method: str, path: str, payload: Mapping[str, object] | None = None
    ) -> object:
        url = self._origin + "/" + path.lstrip("/")
        body = None
        headers = {
            "Accept": _ACCEPT,
            "X-GitHub-Api-Version": _API_VERSION,
            "User-Agent": "study-agent-devkit-gap08",
        }
        try:
            credential = self._credential_provider()
        except Exception:
            raise GitHubPublicationAuthenticationError("credential_unavailable") from None
        if (
            not isinstance(credential, str)
            or not credential
            or len(credential.encode("utf-8")) > _MAX_CREDENTIAL_BYTES
            or any(char in credential for char in "\r\n")
        ):
            raise GitHubPublicationAuthenticationError("invalid_credential")
        headers["Authorization"] = f"Bearer {credential}"
        if payload is not None:
            body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            if len(body) > _MAX_REQUEST:
                raise GitHubPublicationCorruptionError("oversized_request")
            headers["Content-Type"] = "application/json"
        request = Request(url, data=body, headers=headers, method=method)
        try:
            if self._default_opener:
                response = self._opener(request, timeout=self._transport_timeout)
            else:
                response = self._opener(request)
        except (
            GitHubPublicationPermissionError,
            GitHubPublicationRetryableError,
            GitHubPublicationCorruptionError,
        ):
            raise
        except HTTPError as error:
            status = int(error.code)
            retry_after = self._retry_after(error.headers)
            if status == 403 and (
                retry_after is not None or self._rate_limit_exhausted(error.headers)
            ):
                raise GitHubPublicationRetryableError(
                    "github_retryable", status=status, retry_after=retry_after
                ) from None
            if status in {401, 403}:
                raise GitHubPublicationPermissionError("github_permission_rejected") from None
            if status == 429 or status >= 500:
                raise GitHubPublicationRetryableError(
                    "github_retryable", status=status, retry_after=retry_after
                ) from None
            if status in {409, 422}:
                raise GitHubPublicationCollisionError("github_conflict") from None
            if status == 404:
                return None
            raise GitHubPublicationCorruptionError("github_http_error") from None
        except URLError:
            raise GitHubPublicationRetryableError("github_transport_error") from None
        try:
            response_status = getattr(response, "status", None) or getattr(
                response, "code", None
            )
            if type(response_status) is int and 300 <= response_status < 400:
                location = (
                    response.headers.get("Location") if hasattr(response, "headers") else None
                )
                if not isinstance(location, str):
                    raise GitHubPublicationCorruptionError("github_redirect_missing_location")
                redirect = urlparse(location)
                redirect_origin = f"{redirect.scheme}://{redirect.netloc}"
                if redirect_origin != self._origin:
                    raise GitHubPublicationPermissionError("github_redirect_denied")
                raise GitHubPublicationRetryableError(
                    "github_redirect_not_followed", status=response_status
                )
            final_url = response.geturl()
            parsed_final = urlparse(str(final_url))
            if f"{parsed_final.scheme}://{parsed_final.netloc}" != self._origin:
                raise GitHubPublicationPermissionError("github_redirect_denied")
            raw = response.read(self._max_response + 1)
        except (
            GitHubPublicationPermissionError,
            GitHubPublicationRetryableError,
            GitHubPublicationCorruptionError,
        ):
            raise
        except Exception:
            raise GitHubPublicationRetryableError("github_response_error") from None
        if not isinstance(raw, bytes) or len(raw) > self._max_response:
            raise GitHubPublicationCorruptionError("github_response_too_large")
        if not raw:
            return {}
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            raise GitHubPublicationCorruptionError("github_invalid_json") from None

    @staticmethod
    def _retry_after(headers: Any) -> int | None:
        try:
            value = headers.get("Retry-After")
            parsed = int(value)
        except (AttributeError, TypeError, ValueError):
            return None
        return max(0, min(_MAX_RETRY_AFTER, parsed))

    @staticmethod
    def _rate_limit_exhausted(headers: Any) -> bool:
        try:
            return str(headers.get("X-RateLimit-Remaining")) == "0"
        except AttributeError:
            return False

    @staticmethod
    def _mapping(value: object, field: str) -> Mapping[str, object]:
        if not isinstance(value, Mapping):
            raise GitHubPublicationCorruptionError(f"invalid_{field}")
        return value

    @staticmethod
    def _closed_mapping(
        value: object,
        field: str,
        *,
        required: tuple[str, ...],
        optional: tuple[str, ...] = (),
    ) -> Mapping[str, object]:
        data = GitHubRestClient._mapping(value, field)
        allowed = set(required) | set(optional)
        if set(data) - allowed or any(key not in data for key in required):
            raise GitHubPublicationCorruptionError(f"invalid_{field}")
        return data

    @staticmethod
    def _string(value: object, field: str) -> str:
        if not isinstance(value, str) or not value:
            raise GitHubPublicationCorruptionError(f"invalid_{field}")
        return value

    def get_ref(self, owner: str, repository: str, ref: str) -> str | None:
        ref_path = ref[len("refs/") :] if ref.startswith("refs/") else ref
        value = self._request(
            "GET", f"repos/{quote(owner)}/{quote(repository)}/git/ref/{quote(ref_path, safe='/')}"
        )
        if value is None:
            return None
        outer = self._closed_mapping(
            value,
            "ref",
            required=("object",),
            optional=("ref", "node_id", "url"),
        )
        obj = self._closed_mapping(
            outer.get("object"),
            "ref_object",
            required=("sha",),
            optional=("type", "url"),
        )
        return self._string(obj.get("sha"), "ref_sha")

    def get_commit(self, owner: str, repository: str, oid: str) -> GitHubCommitV1:
        value = self._request(
            "GET", f"repos/{quote(owner)}/{quote(repository)}/git/commits/{quote(oid)}"
        )
        return self._parse_commit(value)

    @classmethod
    def _parse_commit(cls, value: object) -> GitHubCommitV1:
        data = cls._closed_mapping(
            value,
            "commit",
            required=("sha", "tree", "message", "author", "committer", "parents"),
            optional=("node_id", "url", "html_url", "verification"),
        )
        tree = cls._closed_mapping(
            data.get("tree"), "commit_tree", required=("sha",), optional=("url",)
        )
        author = cls._closed_mapping(
            value=data.get("author"),
            field="commit_author",
            required=("name", "email", "date"),
            optional=("avatar_url",),
        )
        committer = cls._closed_mapping(
            value=data.get("committer"),
            field="commit_committer",
            required=("name", "email", "date"),
            optional=("avatar_url",),
        )
        parents_raw = data.get("parents")
        if not isinstance(parents_raw, list):
            raise GitHubPublicationCorruptionError("invalid_commit_parents")
        return GitHubCommitV1(
            cls._string(data.get("sha"), "commit_sha"),
            cls._string(tree.get("sha"), "tree_sha"),
            tuple(
                cls._string(
                    cls._closed_mapping(
                        item,
                        "parent",
                        required=("sha",),
                        optional=("url", "html_url"),
                    ).get("sha"),
                    "parent_sha",
                )
                for item in parents_raw
            ),
            cls._string(data.get("message"), "commit_message"),
            cls._string(author.get("name"), "author_name"),
            cls._string(author.get("email"), "author_email"),
            cls._string(author.get("date"), "author_date"),
            cls._string(committer.get("name"), "committer_name"),
            cls._string(committer.get("email"), "committer_email"),
            cls._string(committer.get("date"), "committer_date"),
        )

    def get_tree(self, owner: str, repository: str, tree_oid: str) -> tuple[GitHubTreeEntryV1, ...]:
        value = self._closed_mapping(
            self._request(
                "GET",
                f"repos/{quote(owner)}/{quote(repository)}/git/trees/{quote(tree_oid)}?recursive=1",
            ),
            "tree",
            required=("tree",),
            optional=("sha", "url", "truncated"),
        )
        if value.get("truncated") is True:
            raise GitHubPublicationCorruptionError("truncated_tree")
        if value.get("truncated") not in (None, False):
            raise GitHubPublicationCorruptionError("invalid_tree_truncated")
        raw = value.get("tree")
        if not isinstance(raw, list):
            raise GitHubPublicationCorruptionError("invalid_tree_entries")
        entries: list[GitHubTreeEntryV1] = []
        for item in raw:
            data = self._closed_mapping(
                item,
                "tree_entry",
                required=("path", "mode", "type", "sha"),
                optional=("size", "url"),
            )
            entry_type = self._string(data.get("type"), "tree_entry_type")
            size = data.get("size")
            if size is not None and (type(size) is not int or size < 0):
                raise GitHubPublicationCorruptionError("invalid_tree_entry_size")
            entries.append(
                GitHubTreeEntryV1(
                    self._string(data.get("path"), "tree_entry_path"),
                    self._string(data.get("mode"), "tree_entry_mode"),
                    entry_type,
                    self._string(data.get("sha"), "tree_entry_sha"),
                    size,
                )
            )
        return tuple(entries)

    def get_blob(self, owner: str, repository: str, oid: str) -> bytes:
        value = self._closed_mapping(
            self._request(
                "GET", f"repos/{quote(owner)}/{quote(repository)}/git/blobs/{quote(oid)}"
            ),
            "blob",
            required=("content", "encoding"),
            optional=("sha", "size", "url", "node_id"),
        )
        if value.get("encoding") != "base64":
            raise GitHubPublicationCorruptionError("invalid_blob_encoding")
        raw_content = value.get("content")
        if not isinstance(raw_content, str):
            raise GitHubPublicationCorruptionError("invalid_blob_content")
        content = raw_content.replace("\n", "")
        try:
            decoded = base64.b64decode(content.encode("ascii"), validate=True)
        except (UnicodeEncodeError, ValueError):
            raise GitHubPublicationCorruptionError("invalid_blob_content") from None
        if base64.b64encode(decoded).decode("ascii") != content:
            raise GitHubPublicationCorruptionError("noncanonical_blob_content")
        return decoded

    def create_blob(self, owner: str, repository: str, content: bytes) -> str:
        encoded = base64.b64encode(content).decode("ascii")
        value = self._closed_mapping(
            self._request(
                "POST",
                f"repos/{quote(owner)}/{quote(repository)}/git/blobs",
                {"content": encoded, "encoding": "base64"},
            ),
            "blob",
            required=("sha",),
            optional=("url",),
        )
        return self._string(value.get("sha"), "blob_sha")

    def create_tree(
        self,
        owner: str,
        repository: str,
        base_tree_oid: str,
        entries: tuple[tuple[str, str, str], ...],
    ) -> str:
        tree = tuple(
            {"path": path, "mode": mode, "type": entry_type, "sha": oid}
            for path, mode, entry_type, oid in (
                (path, mode, "blob", oid) for path, mode, oid in entries
            )
        )
        value = self._closed_mapping(
            self._request(
                "POST",
                f"repos/{quote(owner)}/{quote(repository)}/git/trees",
                {"base_tree": base_tree_oid, "tree": tree},
            ),
            "tree",
            required=("sha",),
            optional=("url", "tree", "truncated"),
        )
        return self._string(value.get("sha"), "tree_sha")

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
        payload = {
            "message": message,
            "tree": tree_oid,
            "parents": parent_oids,
            "author": {"name": author_name, "email": author_email, "date": author_timestamp},
            "committer": {
                "name": committer_name,
                "email": committer_email,
                "date": committer_timestamp,
            },
        }
        value = self._closed_mapping(
            self._request("POST", f"repos/{quote(owner)}/{quote(repository)}/git/commits", payload),
            "commit",
            required=("sha", "tree", "message", "author", "committer", "parents"),
            optional=("node_id", "url", "html_url", "verification"),
        )
        return self._parse_commit(value)

    def create_ref(self, owner: str, repository: str, ref: str, oid: str) -> None:
        self._closed_mapping(
            self._request(
                "POST",
                f"repos/{quote(owner)}/{quote(repository)}/git/refs",
                {"ref": ref, "sha": oid},
            ),
            "ref",
            required=("ref", "object"),
            optional=("node_id", "url"),
        )

    def list_pull_requests(
        self, owner: str, repository: str, head_ref: str, base_ref: str
    ) -> tuple[GitHubPullRequestV1, ...]:
        del head_ref, base_ref
        results: list[GitHubPullRequestV1] = []
        for page in range(1, 11):
            query = urlencode({"state": "all", "per_page": 100, "page": page})
            value = self._request("GET", f"repos/{quote(owner)}/{quote(repository)}/pulls?{query}")
            if not isinstance(value, list):
                raise GitHubPublicationCorruptionError("invalid_pull_requests")
            results.extend(self._pull_request(item) for item in value)
            if len(value) < 100:
                return tuple(results)
        raise GitHubPublicationCorruptionError("pull_request_pagination_saturated")

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
        value = self._closed_mapping(
            self._request(
                "POST",
                f"repos/{quote(owner)}/{quote(repository)}/pulls",
                {"head": head_ref, "base": base_ref, "title": title, "body": body, "draft": draft},
            ),
            "pull_request",
            required=(
                "number",
                "html_url",
                "head",
                "base",
                "title",
                "body",
                "draft",
                "state",
                "comments_url",
                "maintainer_can_modify",
            ),
            optional=(
                "id",
                "node_id",
                "url",
                "user",
                "assignee",
                "assignees",
                "locked",
                "created_at",
                "updated_at",
                "closed_at",
                "merged_at",
                "merge_commit_sha",
                "labels",
                "milestone",
                "requested_reviewers",
                "requested_teams",
                "_links",
                "author_association",
                "auto_merge",
                "active_lock_reason",
                "rebaseable",
                "mergeable",
                "mergeable_state",
                "comments",
                "review_comments",
                "commits",
                "additions",
                "deletions",
                "changed_files",
                "review_comments_url",
                "review_comment_url",
                "commits_url",
                "statuses_url",
                "issue_url",
                "diff_url",
                "patch_url",
            ),
        )
        return self._pull_request(value)

    def _pull_request(self, value: object) -> GitHubPullRequestV1:
        data = self._closed_mapping(
            value,
            "pull_request",
            required=(
                "number",
                "html_url",
                "head",
                "base",
                "title",
                "body",
                "draft",
                "state",
                "comments_url",
                "maintainer_can_modify",
            ),
            optional=(
                "id",
                "node_id",
                "url",
                "user",
                "assignee",
                "assignees",
                "locked",
                "created_at",
                "updated_at",
                "closed_at",
                "merged_at",
                "merge_commit_sha",
                "labels",
                "milestone",
                "requested_reviewers",
                "requested_teams",
                "_links",
                "author_association",
                "auto_merge",
                "active_lock_reason",
                "rebaseable",
                "mergeable",
                "mergeable_state",
                "comments",
                "review_comments",
                "commits",
                "additions",
                "deletions",
                "changed_files",
                "review_comments_url",
                "review_comment_url",
                "commits_url",
                "statuses_url",
                "issue_url",
                "diff_url",
                "patch_url",
                "draft",
            ),
        )
        if "review_comment_url" not in data and "review_comments_url" not in data:
            raise GitHubPublicationCorruptionError("invalid_pull_request_review_url")
        head = self._closed_mapping(
            data.get("head"),
            "pull_request_head",
            required=("ref",),
            optional=("label", "sha", "user", "repo"),
        )
        base = self._closed_mapping(
            data.get("base"),
            "pull_request_base",
            required=("ref",),
            optional=("label", "sha", "user", "repo"),
        )
        number = data.get("number")
        if type(number) is not int or number <= 0:
            raise GitHubPublicationCorruptionError("invalid_pull_request_number")
        draft = data.get("draft")
        if type(draft) is not bool:
            raise GitHubPublicationCorruptionError("invalid_pull_request_draft")
        return GitHubPullRequestV1(
            number,
            self._string(data.get("html_url"), "pull_request_url"),
            self._string(head.get("ref"), "pull_request_head_ref"),
            self._string(base.get("ref"), "pull_request_base_ref"),
            self._string(data.get("title"), "pull_request_title"),
            self._string(data.get("body"), "pull_request_body"),
            draft,
            self._string(data.get("state"), "pull_request_state"),
        )


StdlibGitHubApi = GitHubRestClient

__all__ = ["GitHubRestClient", "StdlibGitHubApi"]
