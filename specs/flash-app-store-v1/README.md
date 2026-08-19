# FlashApp 1.0 App Store hardening

Status: active — sas-01 data foundation
Last updated: 2026-08-19
Flywheel run: `flash-app-store-v1`
Decision: `docs/decisions/ADR-006-app-store-v1-contract.md`

## Next Agent Prompt

You are continuing `flash-app-store-v1`. Read ADR-006, the approved feature spec at
`docs/specs/flashapp-1-0-app-store-hardening.md`, this README, and the next open slice.
The next pickup is `01-data-foundation` after the contract/run artifacts pass validation.
Do not touch `assets/emma-avatar/`. Never mark an Apple-account gate PASS without supplied
evidence. Before ending your pass, update this section, the evidence ledger, the owning task
bead, the worker report, and `docs/decisions/worklog.md`.

Global TODO:

- [x] `00-contract`: owner decisions, source amendments, graph, worker report and semantic review accepted.
- [ ] `01-data-foundation`: versioned one-store Core Data foundation and recovery seam.
- [ ] `02-persistent-library`: persistent `LibraryRepository` and production composition.
- [ ] `03-private-sync`: private CloudKit processing and honest account-gated proof.
- [ ] `04-complete-backup`: media-complete archive and safe merge restore.
- [ ] `05-release-surface`: three-tab/onboarding/reminder/privacy release UI.
- [ ] `06-quality-evidence`: CI, privacy, security, localization, accessibility evidence.
- [ ] `07-human-release`: CloudKit/schema/signing/archive/TestFlight/ASC human gates.

Active warnings:

- Apple Developer membership and final identifiers are not yet available.
- CloudKit real-device/schema/signing/TestFlight claims remain `HUMAN_REQUIRED`.
- Production currently defaults to `InMemoryLibrary`; no release claim is valid until
  slices 01–05 replace the shipping path.

## Goal and end state

Ship one coherent personal-data architecture: `AppEnvironment` composes a persistent
repository backed by one versioned `Private.sqlite`; the same store works offline and
mirrors automatically to private CloudKit when available. The release has no Groups or
fake sync surface, and complete backup/restore includes media bytes.

The end state must read as designed today:

- `FlashUpDomain` owns portable contracts and scheduling logic.
- `FlashUpData` is the sole owner of Core Data, CloudKit, archive/media filesystem work,
  migration/recovery, and the persistent repository.
- `AppEnvironment` is the sole production composition root.
- In-memory implementations are test/preview fixtures, never a production fallback.
- `Private.sqlite` is the only 1.0 user store; there is no dormant group/shared path.

## Slice graph

```text
00 contract
  -> 01 data foundation
      -> 02 persistent library
          -> 03 private sync
          -> 04 complete backup
              -> 05 release surface
                  -> 06 quality evidence
                      -> 07 human release
```

Slices 03 and 04 are logically independent after 02, but both touch `FlashUpData`; keep one
active owner or isolate them in separate worktrees with a frozen API seam. Slice 07 never
runs in parallel with feature work.

## Scope firewalls

- No Groups, `CKShare`, shared store, group entity, group copy, or group release evidence.
- No StoreKit/IAP/paywall/account/tracking/third-party analytics.
- No destructive store repair and no implicit restore replacement.
- No weakening of the existing default regression gate.
- No push, publish, App Store submission, or remote repository mutation without explicit
  authorization.
- No changes under `assets/emma-avatar/`.

## Evidence ledger

| Slice | State | Evidence |
| --- | --- | --- |
| 00 | done | worker report; semantic review approved; spec/dispatch validation passed |
| 01 | ready | one-store Core Data foundation; no Apple-account PASS claims |
| 02–06 | open | — |
| 07 | HUMAN_REQUIRED | Apple account, identifiers, schema, signing, archive, TestFlight, ASC |

## Review map

- Data loss/migration: slices 01–02, reviewed by a data correctness reviewer.
- Sync/convergence/privacy: slice 03, reviewed by CloudKit and security reviewers.
- Backup/media integrity: slice 04, reviewed by a portability/security reviewer.
- Visible release truth: slice 05, production-route screenshots plus unprimed critique.
- App Store readiness: slices 06–07, tri-state matrix with no inferred PASS.
