from __future__ import annotations

import json
from email.message import Message
from urllib.error import HTTPError
from urllib.request import Request

import pytest

from study_agent_devkit.capability_gap import (
    GitHubPublicationAuthenticationError,
    GitHubPublicationCollisionError,
    GitHubPublicationCorruptionError,
    GitHubPublicationPermissionError,
    GitHubPublicationRetryableError,
    GitHubRestClient,
)


class Response:
    def __init__(
        self, value: object, *, url: str = "https://api.github.com/repos/octo/study"
    ) -> None:
        self.value = value
        self.url = url

    def geturl(self) -> str:
        return self.url

    def read(self, limit: int = -1) -> bytes:
        raw = json.dumps(self.value, separators=(",", ":")).encode()
        return raw if limit < 0 else raw[:limit]


class Opener:
    follows_redirects = False

    def __init__(self, response: object) -> None:
        self.response = response
        self.requests: list[Request] = []

    def __call__(self, request: Request) -> object:
        self.requests.append(request)
        if isinstance(self.response, BaseException):
            raise self.response
        return self.response


def _headers(values: dict[str, str] | None = None) -> Message[str, str]:
    result: Message[str, str] = Message()
    for key, value in (values or {}).items():
        result[key] = value
    return result


def client(
    response: object, *, credential: str = "secret-token", max_response_bytes: int = 1024 * 1024
) -> tuple[GitHubRestClient, Opener]:
    opener = Opener(response)
    return GitHubRestClient(
        lambda: credential, opener=opener, max_response_bytes=max_response_bytes
    ), opener


def test_rest_sends_only_bounded_header_credential_and_current_api_version() -> None:
    api, opener = client(Response({"object": {"sha": "a" * 40}}))
    assert api.get_ref("octo", "study", "refs/heads/main") == "a" * 40
    request = opener.requests[0]
    assert request.full_url.endswith("/git/ref/heads/main")
    assert request.get_header("Authorization") == "Bearer secret-token"
    assert request.get_header("X-github-api-version") == "2026-03-10"
    request_data = request.data
    if request_data is not None:
        assert isinstance(request_data, bytes)
        assert b"secret-token" not in request_data


def test_rest_closed_shapes_reject_unexpected_keys() -> None:
    api, _opener = client(Response({"object": {"sha": "a" * 40}, "unexpected": 1}))
    with pytest.raises(GitHubPublicationCorruptionError):
        api.get_ref("octo", "study", "refs/heads/main")


def test_rest_parses_git_database_commit_top_level_shape() -> None:
    payload = {
        "sha": "a" * 40,
        "tree": {"sha": "b" * 40, "url": "https://api.github.com/tree"},
        "message": "subject",
        "author": {"name": "author", "email": "a@example.invalid", "date": "1970-01-01T00:00:00Z"},
        "committer": {
            "name": "committer",
            "email": "c@example.invalid",
            "date": "1970-01-01T00:00:00Z",
        },
        "parents": [{"sha": "c" * 40}],
    }
    api, _opener = client(Response(payload))
    commit = api.get_commit("octo", "study", "a" * 40)
    assert commit.oid == "a" * 40
    assert commit.tree_oid == "b" * 40
    assert commit.parent_oids == ("c" * 40,)


def test_rest_rejects_truncated_tree() -> None:
    api, _opener = client(Response({"tree": [], "truncated": True}))
    with pytest.raises(GitHubPublicationCorruptionError):
        api.get_tree("octo", "study", "a" * 40)


def test_rest_accepts_realistic_closed_pull_request_shape() -> None:
    payload = {
        "number": 7,
        "html_url": "https://github.com/octo/study/pull/7",
        "head": {"ref": "codex/test"},
        "base": {"ref": "main"},
        "title": "title",
        "body": "body",
        "draft": True,
        "state": "open",
        "comments_url": "https://api.github.com/comments",
        "review_comment_url": "https://api.github.com/review-comments",
        "maintainer_can_modify": True,
    }
    api, _opener = client(Response(payload))
    pr = api._pull_request(payload)
    assert pr.number == 7 and pr.draft


def test_rest_bounds_credential_provider_output() -> None:
    api, _opener = client(Response({}), credential="x" * 5000)
    with pytest.raises(GitHubPublicationAuthenticationError):
        api.get_ref("octo", "study", "refs/heads/main")


@pytest.mark.parametrize("status", [401, 403])
def test_authentication_and_permission_failures_are_typed_and_secret_free(status: int) -> None:
    error = HTTPError("https://api.github.com", status, "denied", _headers(), None)
    api, _opener = client(error)
    with pytest.raises(GitHubPublicationPermissionError) as raised:
        api.get_ref("octo", "study", "refs/heads/main")
    assert "secret-token" not in str(raised.value)
    assert "denied" not in str(raised.value)


@pytest.mark.parametrize("status", [409, 422])
def test_remote_conflicts_are_typed(status: int) -> None:
    api, _opener = client(
        HTTPError("https://api.github.com", status, "conflict", _headers(), None)
    )
    with pytest.raises(GitHubPublicationCollisionError):
        api.get_ref("octo", "study", "refs/heads/main")


@pytest.mark.parametrize("status", [429, 500, 502])
def test_rate_limit_and_transient_failures_are_retryable_with_bounded_delay(status: int) -> None:
    headers = _headers({"Retry-After": "999"})
    error = HTTPError("https://api.github.com", status, "server-body", headers, None)
    api, _opener = client(error)
    with pytest.raises(GitHubPublicationRetryableError) as raised:
        api.get_ref("octo", "study", "refs/heads/main")
    assert raised.value.status == status
    assert raised.value.retry_after == 60
    assert "server-body" not in str(raised.value)


def test_403_rate_limit_marker_is_retryable() -> None:
    error = HTTPError(
        "https://api.github.com",
        403,
        "rate limited",
        _headers({"Retry-After": "2", "X-RateLimit-Remaining": "0"}),
        None,
    )
    api, _opener = client(error)
    with pytest.raises(GitHubPublicationRetryableError):
        api.get_ref("octo", "study", "refs/heads/main")


def test_malformed_json_and_oversized_response_are_typed() -> None:
    class Invalid:
        def geturl(self) -> str:
            return "https://api.github.com"

        def read(self, limit: int = -1) -> bytes:
            return b"{not-json"

    api, _opener = client(Invalid())
    with pytest.raises(GitHubPublicationCorruptionError):
        api.get_ref("octo", "study", "refs/heads/main")
    api2, _opener2 = client(Response({"x": "y" * 200}), max_response_bytes=16)
    with pytest.raises(GitHubPublicationCorruptionError):
        api2.get_ref("octo", "study", "refs/heads/main")


def test_cross_origin_redirect_is_denied_without_leaking_credential() -> None:
    api, opener = client(Response({}, url="https://evil.example/redirect"))
    with pytest.raises(GitHubPublicationPermissionError):
        api.get_ref("octo", "study", "refs/heads/main")
    assert opener.requests[0].get_header("Authorization") == "Bearer secret-token"


def test_injected_non_following_transport_rejects_cross_origin_redirect() -> None:
    class Redirect:
        status = 302
        code = 302

        def __init__(self) -> None:
            self.headers = {"Location": "https://evil.example/redirect"}

        def geturl(self) -> str:
            return "https://api.github.com/repos/octo/study"

        def read(self, limit: int = -1) -> bytes:
            return b"{}"

    api, _opener = client(Redirect())
    with pytest.raises(GitHubPublicationPermissionError):
        api.get_ref("octo", "study", "refs/heads/main")


def test_blob_request_uses_standard_base64() -> None:
    api, opener = client(Response({"sha": "a" * 40}))
    assert api.create_blob("octo", "study", b"\x00\xff") == "a" * 40
    request_data = opener.requests[0].data
    assert isinstance(request_data, bytes)
    payload = json.loads(request_data)
    assert payload == {"content": "AP8=", "encoding": "base64"}


def test_forbidden_imports_are_not_used_by_rest_module() -> None:
    from pathlib import Path

    source = (
        Path(__file__).parents[3]
        / "src"
        / "study_agent_devkit"
        / "capability_gap"
        / "github_rest.py"
    ).read_text()
    for token in ("subprocess", "shell=True", "import git", "import gh", "model"):
        assert token not in source
