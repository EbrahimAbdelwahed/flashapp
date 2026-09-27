# FlashApp — Agent Instructions

## Source of truth

- Product decisions: `flash-up-architecture-brief.md`.
- Engineering contract: `flash-up-implementation-spec.md`.
- Design direction for every UI batch: `docs/ux-principles.md` (owner amendment, 2026-07-28).
- Delivery state, batch beads, worker briefs, and review evidence: `docs/flywheel-runs/flash-up-v1/`.

If the brief conflicts with the implementation specification, stop and record the conflict as an ADR; the brief wins.

## Flywheel workflow

`agent-flywheel/` is the local orchestration kit copied into this repository. Use its runner and templates rather than inventing another task protocol:

```text
approved spec -> batch bead -> worker brief -> scoped implementation -> review evidence -> worklog / ADR
```

Read the assigned batch bead before changing code. A batch may contain several original B-prefixed beads only where its acceptance criteria name the original coverage. Do not expand a batch across a CloudKit, FSRS, data-loss, or public-product decision: write an ADR and stop instead.

## FlashApp non-negotiables

- iOS/iPadOS 17+, SwiftUI, Core Data with `NSPersistentCloudKitContainer`; no SwiftData.
- `FlashUpDomain` remains pure and portable; dependency direction is App -> Data -> Domain.
- Card content stays on-device except the user's iCloud and explicit exports. Logs never contain card text.
- User-facing copy ships in English and Italian; every UI change includes accessibility and reduced-motion behavior.
- Never delete a user store to repair migration or sync failures.

## Coordination and verification

- Keep changes within the assigned batch's file boundary and report any follow-up as a new bead candidate.
- Prefer one active owner per batch; use the dependency graph in `docs/flywheel-runs/flash-up-v1/batch-plan.md` before parallel dispatch.
- Follow the Git delivery policy below for owner-requested work; other publication requires its own authorization.
- Each completed batch updates `docs/decisions/worklog.md` once that file exists and records the requested verification evidence.

## Git, worktrees, and delivery

- At task start, inspect the repository root, remotes, branch, status, upstream,
  and existing PR. Confirm which checkout owns the task before editing.
  Read-only research and review do not need a new branch or worktree.
- Give each independent implementation task one owner and one `codex/<topic>`
  branch. Do not develop on `main`, switch another active chat's branch, or
  mix unrelated tasks into a long-lived product branch.
- Prefer a suitable free Codex-managed worktree. Inspect attached worktrees
  first; use the app's worktree tools for creation, archival, and recovery when
  available. Reuse only after accounting for prior work and preparing the base.
  Use a durable checkout when app tools are unavailable; temporary directories
  must never hold the only copy of unpublished work.
- Start independent changes from the fetched GitHub default branch. A task
  continuing an existing branch must keep that branch and its PR. If a change
  depends on unmerged work, name that dependency and base explicitly in the PR;
  do not accidentally submit the whole product lineage as a small fix.
- Preserve other owners' dirty, staged, untracked, and ignored files. Stage
  only the assigned files or hunks; inspect the staged diff before committing.
  Never use blanket staging, destructive reset/clean, automatic stash, or
  force-push to make a checkout look clean. Preserve and verify recoverable
  backups before any authorized migration or cleanup.
- For owner-requested implementation, normal delivery includes scoped commits,
  pushing the task branch to the existing GitHub repository, and creating or
  updating its PR, unless the user requests local-only work or another limit.
  This does not authorize new repositories, releases, deployments, credential
  changes, direct pushes to `main`, or merging without an explicit user request
  or an already-approved merge policy.
- Keep one PR per independently verifiable outcome. Include its tests, necessary
  documentation, and review fixes in that PR. Do not open branches or PRs for
  individual reviewers, review passes, or each progress note. Read-only reviewers
  inspect the implementation branch; assigned fixes go back to its owner.
- Use draft PRs for unfinished or blocked work. Make a PR ready when its scoped
  implementation and prescribed verification are complete. Attach created PRs
  to the current Codex chat and keep title, description, base, and validation
  accurate as scope changes. Routine documentation-only changes need diff and
  link inspection, not invented runtime tests; applicable CI still runs.
- Use automatic Codex GitHub review as the ordinary semantic review after
  publication. Do not duplicate it with a mandatory local reviewer chain.
  Add specialist review only for a concrete risk or requested acceptance gate,
  especially authentication, untrusted input, persistence, migration, or data
  loss. Explain the added gate. Do not weaken existing product acceptance rules.
- Before an authorized merge, require applicable CI and review evidence for the
  current submitted commit, resolve actionable findings, and check dependencies.
  A missing review, absent check, failed run, or old green commit is not approval.
  After a fix, push to the same PR and reassess the updated commit.
- At handoff, report checkout, branch, commit, PR URL, verification, outstanding
  review/CI, and any remaining local work. Distinguish implemented, published,
  reviewed, and merged; do not call pending work complete.
- At task transitions, reuse free worktrees or archive retired managed worktrees
  with the app tool after checking that no chat or process needs them. Preserve
  needed ignored files separately. Keep backup refs and unpublished commits.
  Close a superseded PR only after verifying where its changes are retained.
  Prune missing Git worktree registrations only after inspecting paths and
  saving their metadata and referenced commits. Never close an active PR merely
  to clean up a checkout or attachment.

## Code Review Rules

- Prioritize reproducible correctness, security, data-loss, and public-contract
  regressions caused by the change. Give a concrete trigger and affected code;
  avoid speculative warnings, formatting preferences, and duplicate findings.
- Inspect the actual PR base and dependency context. Report unrelated backlog
  or missing integration separately rather than treating it as this patch's bug.
- Apply the repository's domain rules below and in its canonical specifications.
  Review findings are evidence, not authorization to merge or publish user data.
