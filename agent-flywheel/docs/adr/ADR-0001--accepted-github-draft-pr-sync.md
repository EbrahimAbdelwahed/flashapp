# ADR-0001: Accepted capability gaps may open draft pull requests

Date: 2026-07-26
Status: Accepted

## Context

The local capability-gap chain ends with an immutable, maintainer-accepted
`FlywheelPromotionBundleV1` and an exact materialization plan. The user approved
an optional GitHub continuation that creates a branch and draft pull request,
but never merges, releases, or deploys. Reusing the runner's `git`/`gh`
subprocess lane would mix orchestration with the capability-gap authority and
would make exact recovery depend on a mutable checkout.

## Decision

1. GAP-08 is a separate opt-in outbound adapter. It receives only a promotion
   ID, loads the persisted accepted promotion through a read-only source, and
   requires a host-issued publication authorization bound to that exact
   promotion and target.
2. The adapter creates the exact `MaterializationPlanV1` files beneath
   `docs/flywheel-runs/<run-id>/` on a deterministic branch and opens a draft
   pull request through an injected GitHub API port.
   The reference REST client uses GitHub's Git database and pull-request APIs;
   it does not invoke `git`, `gh`, a shell, a model, or a provider SDK.
3. Credentials are supplied by trusted composition through a credential
   provider. They are never accepted in the sync request, persisted, logged, or
   included in receipts. Repository owner, repository name, base branch, and
   authorization identity are trusted host configuration, not model arguments.
4. A separate SQLite store claims `(promotion_id, sink_id)` before the first
   remote write and pins the canonical request plus the resolved base commit.
   Branch, commit, and pull-request markers contain the full promotion identity.
   Retries reconcile exact remote state; differing branch trees, commit
   metadata, markers, pull-request bodies, bases, heads, or draft status fail
   closed. The adapter never force-updates or deletes remote state.
5. The adapter may create blobs, one tree, one commit, one branch reference, and
   one draft pull request. It cannot create issues, merge or close pull requests,
   modify the base branch, publish a release, deploy, start workers, or mutate
   local Flywheel decisions.
6. Verified release-to-gap feedback remains deferred. Pull-request state or
   issue text is never accepted as release evidence.
7. Commit author, committer, message, and timestamp are canonical request
   fields so restart reconciliation produces one deterministic commit identity.

## Consequences

- GitHub remains a publication surface; the accepted Flywheel promotion remains
  canonical.
- Recovery after process loss is deterministic without a local checkout.
- The production host may use a GitHub App, while local demonstrations may
  inject a narrowly scoped token. Both use the same technical port.
- GAP-08 adds a separate persistence schema and public adapter contracts, so it
  requires independent security, correctness, and clean-install review.

## Alternatives Considered

- Reuse `flywheel-runner.py` with `git` and `gh`: rejected because it is a broad
  interactive orchestration lane, not an idempotent capability-gap adapter.
- Create a public issue: rejected for this slice; the approved behavior is a
  branch and draft pull request.
- Automatically merge an accepted change: rejected because acceptance does not
  grant merge, release, or deployment authority.
