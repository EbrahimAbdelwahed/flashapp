# FlashApp 1.0 App Store hardening

Status: active — sas-03a account routing ready
Last updated: 2026-08-20
Flywheel run: `flash-app-store-v1`
Decision: `docs/decisions/ADR-006-app-store-v1-contract.md`

## Next Agent Prompt

You are continuing `flash-app-store-v1`. Read ADR-006, ADR-007, the approved feature spec at
`docs/specs/flashapp-1-0-app-store-hardening.md`, this README, and the next open slice.
The next pickup is `03a-account-routing`. Implement only account identity preflight,
profile-scoped storage and safe single-owner transitions. The rejected `03-private-sync`
pass is evidence, not accepted architecture; convergence remediation belongs to 03b.
Do not touch `assets/emma-avatar/`. Never mark an Apple-account gate PASS without supplied
evidence. Before ending your pass, update this section, the evidence ledger, the owning task
bead, the worker report, and `docs/decisions/worklog.md`.

Global TODO:

- [x] `00-contract`: owner decisions, source amendments, graph, worker report and semantic review accepted.
- [x] `01-data-foundation`: versioned one-store Core Data foundation and recovery seam.
- [x] `02-persistent-library`: persistent `LibraryRepository` and production composition.
- [x] `03-private-sync`: rejected pass recorded as superseded evidence.
- [ ] `03a-account-routing`: isolated Anonymous/Legacy/account store ownership.
- [ ] `03b-sync-convergence`: truthful private CloudKit processing and convergence.
- [ ] `04-complete-backup`: media-complete archive and safe merge restore.
- [ ] `04b-scoped-transfer-erasure`: explicit profile transfer and scoped deletion.
- [ ] `05-release-surface`: three-tab/onboarding/reminder/privacy release UI.
- [ ] `06-quality-evidence`: CI, privacy, security, localization, accessibility evidence.
- [ ] `07-human-release`: CloudKit/schema/signing/archive/TestFlight/ASC human gates.

Active warnings:

- Apple Developer membership and final identifiers are not yet available.
- CloudKit real-device/schema/signing/TestFlight claims remain `HUMAN_REQUIRED`.
- `account-switch-data-boundary` is resolved by ADR-007. The first SAS-03 implementation
  pass has green tests but failed correctness and security review and is not accepted.
- Production now uses the persistent repository; CloudKit truthfulness, complete archives
  and the final release surface still block release until slices 03–05 are accepted.

## Goal and end state

Ship one coherent personal-data architecture: `AppEnvironment` composes exactly one active
profile repository. Anonymous and quarantined Legacy profiles are local-only; each proven
Apple Account fingerprint has an isolated versioned `Private.sqlite` mirrored to that
account's private CloudKit database. The release has no Groups or fake sync surface, and
complete backup/restore includes media bytes.

The end state must read as designed today:

- `FlashUpDomain` owns portable contracts and scheduling logic.
- `FlashUpData` is the sole owner of Core Data, CloudKit, archive/media filesystem work,
  migration/recovery, and the persistent repository.
- `AppEnvironment` is the sole production composition root.
- In-memory implementations are test/preview fixtures, never a production fallback.
- Every profile contains one `Private.sqlite`; no shared/group store exists in 1.0.

## Slice graph

```text
00 contract
  -> 01 data foundation
      -> 02 persistent library
          -> 03a account routing
              -> 03b sync convergence
                  -> 04 complete backup
                      -> 04b scoped transfer/erasure
                          -> 05 release surface
                  -> 06 quality evidence
                      -> 07 human release
```

Slices 03a through 04b share `FlashUpData` and `AppEnvironment` and therefore run serially
under one active owner. Slice 07 never runs in parallel with feature work.

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
| 01 | done | 15 focused tests; correctness + security reviews approved |
| 02 | done | 264 package tests; 20 UI tests; correctness + security reviews approved |
| 03 rejected | superseded | 277 package + 21 UI tests pass; correctness/security reviews blocked |
| 03a | ready | ADR-007 accepted; implementation/review pending |
| 03b–06 | open | — |
| 07 | HUMAN_REQUIRED | Apple account, identifiers, schema, signing, archive, TestFlight, ASC |

## Review map

- Data loss/migration: slices 01–02, reviewed by a data correctness reviewer.
- Sync/convergence/privacy: slice 03, reviewed by CloudKit and security reviewers.
- Backup/media integrity: slice 04, reviewed by a portability/security reviewer.
- Visible release truth: slice 05, production-route screenshots plus unprimed critique.
- App Store readiness: slices 06–07, tri-state matrix with no inferred PASS.
