# GAP-08 accepted-only GitHub draft pull-request synchronization

Status: Done
Date: 2026-07-26

## Goal

Publish the exact files of one persisted, maintainer-accepted
`FlywheelPromotionBundleV1` to a deterministic GitHub branch and draft pull
request. GitHub is an optional technical sink and never becomes engineering
authority or canonical state.

## Scope

### In scope

- Closed GitHub-publication request, authorization, remote-state, and receipt
  contracts.
- A read-only accepted-promotion source protocol.
- A separately authenticated publication-authority protocol.
- A narrow GitHub API protocol plus a stdlib REST implementation.
- Separate SQLite claim and receipt persistence.
- Exact Git database tree creation from the promotion materialization plan.
- Deterministic branch, commit, marker, title, and draft pull-request body.
- Restart, duplicate, permission, rate-limit, malformed-response, and tamper
  behavior.
- Offline scripted tests and architecture firewalls.

### Out of scope

- GitHub issues or automatic public reporting.
- Merge, release, deployment, pull-request closure, review submission, labels,
  milestones, assignees, comments, or base-branch mutation.
- Hosted capability-gap intake, learner/product state, model calls, `git`,
  `gh`, shells, worker dispatch, or Codex goal APIs.
- Treating pull-request state as verified capability release evidence.

## Contract

### Trusted composition

Callers supply only a 64-character promotion ID. The service loads the exact
persisted promotion through `AcceptedPromotionSource`. Target owner, repository,
base branch, stable adapter identity, and credential provider are constructor
configuration owned by the host.

Before any remote write, `GitHubPublicationAuthority.authorize(view)` must return
one canonical authorization bound to:

- promotion, resolution, proposal, and decision IDs;
- promotion fingerprint and exact materialization-plan fingerprint;
- target owner/repository and base branch;
- the allowed operation `create_branch_and_draft_pr`;
- an opaque authorization receipt fingerprint.

Missing, mismatched, or malformed authorization mutates neither SQLite nor
GitHub.

### Canonical publication request

The request contains no credential, learner material, outbox contribution,
delivery identity, source path, or model text. It contains:

- schema version and accepted promotion identities;
- target owner, repository, base branch, deterministic branch name;
- canonical commit message, draft PR title/body, and full promotion marker;
- sorted repository paths
  `docs/flywheel-runs/<run_id>/<plan-relative-path>` with exact bytes from
  `MaterializationPlanV1`;
- plan, tree-manifest, request, and authorization fingerprints.

Branch names use `codex/capability-gap-<first 24 promotion hex>` while the full
promotion ID and request fingerprint appear in commit and PR markers.

### Persistence and remote effects

The standalone SQLite v1 store has one job/claim table with:

- unique publication and promotion IDs;
- sink ID, repository, base ref, and pinned base object ID;
- canonical request bytes as the source of truth;
- a nullable canonical receipt.

Projection columns are verified against the request on every read. The service
first checks for an existing claim, then loads and canonicalizes the accepted
promotion, obtains exact authorization, reads the current base object ID, and
uses `BEGIN IMMEDIATE` to insert the first winning claim. Two concurrent callers
that observed different base heads reuse the winning claim when promotion,
target, sink, and authority are otherwise identical. Different request, target,
authority, or sink data is a collision. Exact retries always use the pinned base
commit.

No database transaction is held during GitHub calls. The adapter:

1. creates or reuses content-addressed blobs for every exact file;
2. creates the expected tree over the pinned base tree, changing only
   `docs/flywheel-runs/<run_id>/`;
3. creates or reconciles the deterministic commit, including canonical author,
   committer, message, timestamp, parent, and marker;
4. creates the branch only when absent;
5. verifies an existing branch points to a commit with the exact parent, tree,
   message, and marker;
6. finds or creates one draft pull request for the exact head/base pair;
7. verifies title, body, marker, head, base, and draft status;
8. persists one canonical success receipt.

It never force-updates, deletes, closes, merges, releases, or deploys. A remote
collision or tamper fails closed and leaves the claim pending for inspection.
Process loss after any remote step converges by recomputing content-addressed
objects and reconciling exact branch/PR state.

### REST boundary

The reference client accepts an injected credential callback and HTTP opener.
It sends the credential only in the authorization header, caps response sizes,
validates closed JSON shapes, and never includes response bodies or credentials
in exceptions. Authentication/permission failures fail without retry. Rate
limits and transient server responses surface a typed retryable error with a
bounded server delay; retry scheduling remains host policy.

Default tests use a scripted in-memory API implementation. CI performs no real
GitHub mutation and requires no write token.

The reference HTTP client permits redirects only when scheme and configured
GitHub API origin remain identical. Request/response bodies and headers are
bounded. Errors expose typed status/retry metadata but never response bodies or
credentials.

## Acceptance

- Rejected, deferred, duplicate, unknown, corrupt, or forged promotions cannot
  reach the publication authority or GitHub client.
- Accepted promotion plus exact authorization creates one exact branch and one
  draft PR.
- Exact retry after restart returns the persisted canonical receipt without
  GitHub calls.
- Loss after commit, branch, PR, or before receipt persistence converges to the
  same receipt without duplicate branches or PRs.
- Moving base branches do not alter an already claimed publication.
- Existing remote state with any differing byte, parent, tree, marker, title,
  body, head/base, draft flag, author, committer, or timestamp fails closed.
- The commit differs from the pinned base only beneath the exact run subtree;
  a pre-existing conflicting subtree fails closed.
- Credentials never enter request/claim/receipt bytes or exception messages.
- Architecture tests prove the core GAP-05B through GAP-07 modules still import
  no GitHub, HTTP, subprocess, shell, Git, model, or provider code.
- Focused tests, full suite, Ruff, strict mypy, wheel build, clean-wheel import,
  and Python 3.12/3.13 GitHub Actions pass.

## Implementation order

1. Closed contracts and pure request planner.
2. SQLite claim/receipt service with a scripted GitHub boundary.
3. Stdlib REST adapter.
4. Adversarial recovery and architecture tests.
5. Independent security and semantic review, documentation, and closure.

## Completion evidence

The approved contract is implemented and closed at commit
`ac884212eb05b5ca916bd6b2345ec4d77b5dbf3a`. GitHub Actions run
[30205827258](https://github.com/EbrahimAbdelwahed/study-agent-devkit/actions/runs/30205827258)
is green on Python 3.12 and 3.13 with 317 tests, Ruff, strict mypy, wheel
build, clean-wheel import, and Flywheel scaffold/runner smoke checks. The
workflow performs no real GitHub mutation and requires no write token.
