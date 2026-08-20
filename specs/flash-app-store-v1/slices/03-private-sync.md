# Slice 03 — Rejected initial private CloudKit sync pass

Status: superseded by ADR-007; retained as review evidence, never dispatch directly.

The first implementation pass proved useful fixtures but failed correctness and
security/data-loss review. Its accepted requirements are resliced into
`03a-account-routing.md` and `03b-sync-convergence.md`; account-neutral archive transfer
continues in `04-complete-backup.md` and `04b-scoped-transfer-erasure.md`.

## Contract unlocked

The private store mirrors automatically when iCloud is available, remains locally usable
when it is not, and exposes truthful status/retry without card text in diagnostics.

## API seam and ownership

`SyncMonitor` owns availability/events/status. `RemoteChangeProcessor` owns persistent
history tokens, deterministic deduplication and schedule replay hooks. The release store is
configured for private CloudKit before load even when the account is absent; account
changes never replace the store. `LibraryRepository.retrySync()` is the domain-facing retry
seam consumed by UI and composed by `AppEnvironment`.

## Runnable artifact

Before account activation: deterministic local history/remote-change fixtures and forced
availability states, including data created in `.noAccount` then made export-eligible after
`.available`. After activation: same-account two-device checklist covering offline edits,
reconnect, convergence, media, relaunch, soft-delete/restore, and permanent erasure.

## Verification

- Token persistence/resume, event debounce, retry and account-state mapping are tested.
- Shuffled review logs converge to the same schedule; metadata logs contain no card text.
- Local authoring/study remains green for no-account, restricted and offline states.
- Retry requests a save/event refresh without changing the store URL or fabricating success.
- Delete, restore, and permanent-erasure propagation remain explicit human checklist cells.
- Container/schema/device cells remain `HUMAN_REQUIRED` until real evidence is attached.
- Submission remains blocked while any CloudKit end-to-end cell is unverified.

## Feedback that changes this slice

Unexpected CloudKit behavior affecting model/topology is an ADR/decision request, not a
local workaround.
