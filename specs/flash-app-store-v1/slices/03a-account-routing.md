# Slice 03A — Account-scoped store routing

## Contract unlocked

FlashApp resolves CloudKit identity before load and opens exactly one isolated Anonymous,
Legacy or identified account profile without exposing one profile's Core Data, media,
session, cursor or recovery files to another.

## API seam and ownership

`CloudAccountIdentityResolver` returns availability plus current record identity.
`AccountStoreRegistry` owns device-keyed fingerprints and the recoverable profile catalog.
`AccountStoreCoordinator` is the only production owner allowed to select a profile URL,
open/close a repository bundle or react to account change. `AppEnvironment` consumes its
generation-checked state.

## Verification

- Identity resolution completes before any production store load.
- Anonymous/Legacy descriptions have no CloudKit options; identified descriptions are
  private and scoped to distinct paths.
- A→B hides every A sidecar; return-to-A chooses the exact A path; only one owner is open.
- Missing/corrupt catalog or HMAC key enters recovery without creating a replacement key.
- Global pre-ADR-007 data is cloned into Legacy local-only with verified original bytes.
- Failure injection during routing/adoption preserves at least one recoverable source.
- Raw record identity, fingerprint and path appear in no log, UI, default or export.
- Real account behavior remains `HUMAN_REQUIRED / UNVERIFIED`.

## Feedback that changes this slice

Any need to load two profiles at once, assign legacy data to an account, or rely on a live
CloudKit race is a new decision request.
