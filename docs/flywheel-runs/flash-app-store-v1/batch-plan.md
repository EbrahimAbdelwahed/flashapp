# FlashApp App Store 1.0 — batch graph

Status: approved; sas-01 ready for dispatch
Date: 2026-08-19
Decision: `docs/decisions/ADR-006-app-store-v1-contract.md`

## Graph

```mermaid
flowchart LR
  A[sas-00 Contract] --> B[sas-01 Data foundation]
  B --> C[sas-02 Persistent library]
  C --> D[sas-03 Private sync]
  D --> E[sas-04 Complete backup]
  E --> F[sas-05 Release surface]
  F --> G[sas-06 Quality evidence]
  G --> H[sas-07 Human release]
```

## Dispatch policy

- One owner at a time for `FlashUpData`, the Core Data model and `AppEnvironment`.
- Slices 03 and 04 are logically separable but are serialized because both integrate with
  the persistent repository and user data.
- The UI batch starts only after sync and backup contracts are stable.
- Release audit never runs in parallel with feature work.
- Every worker uses a scoped branch/worktree, reports completion, receives semantic review,
  and appends one worklog entry only when its acceptance criteria are honestly met.
- No task may touch `assets/emma-avatar/`.

## Human gate policy

`sas-07-human-release` is intentionally not ready for completion. Team/App ID/bundle/
container/schema/legal URLs/signing/archive/TestFlight/price/submission stay
`HUMAN_REQUIRED` until primary evidence is recorded. CloudKit E2E remains a submission
blocker even if every repository-only test passes.

## State

| Batch | State | Evidence |
| --- | --- | --- |
| sas-00-contract | Done | worker report + approved semantic review + validation |
| sas-01-data-foundation | Ready | sas-00 accepted |
| sas-02-persistent-library | Pending | waits for sas-01 |
| sas-03-private-sync | Pending | waits for sas-02; real-account cells human-gated |
| sas-04-complete-backup | Pending | waits for sas-03 |
| sas-05-release-surface | Pending | waits for sas-04 |
| sas-06-quality-evidence | Pending | waits for sas-05 |
| sas-07-human-release | HUMAN_REQUIRED | waits for sas-06 and Apple account evidence |
