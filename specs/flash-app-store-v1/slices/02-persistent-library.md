# Slice 02 — Persistent library and production composition

## Contract unlocked

Every existing `LibraryRepository` behavior persists across relaunch using Core Data, and
the production app has no in-memory fallback.

## API seam and ownership

One `CoreDataLibraryRepository` implements the existing domain-facing repository contract.
`AppEnvironment` composes it exactly once. In-memory stores remain test/preview oracles and
must not become a second production owner.

This slice adds an idempotent, versioned `installDemoDeck` repository operation using a
stable seed identifier and `isDemo = true`. It also removes dormant `Deck.groupID` and
`BackupDeck.sharedSnapshot` from the 1.0 Domain contract and updates fixtures/codecs.

## Runnable artifact

The app creates/imports/studies/trashes content, terminates, relaunches and shows identical
content, progress, settings and trash state from `Private.sqlite`, plus the same resumable
session from its specified device-local atomic JSON file.

## Verification

- Contract tests run the same behavior scenarios against in-memory and on-disk adapters.
- UUID/timestamp, card reconciliation, schedule flags, logs and `CDStudySettings`
  round-trip exactly; session state round-trips through `session-state.json` and is not
  CloudKit mirrored.
- Imports commit atomically; trash restore retains scheduling; delete-all follows the
  non-destructive contract for the store itself.
- Production composition contains no `InMemoryLibrary()` or `InMemoryMediaStore()` fallback.
- Repeated demo installation produces exactly one persistent demo deck; finish/skip UI can
  call the same domain operation without importing Data types.

## Must stay green

Existing UI behavior and all `LibraryRepository` oracle tests; do not weaken them to fit
the adapter.

## Feedback that changes this slice

If the existing wide repository protocol causes a concrete correctness/testability failure,
reslice a narrow contract refactor first; do not speculatively split it.
