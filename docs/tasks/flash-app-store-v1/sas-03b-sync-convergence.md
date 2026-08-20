# Task Bead: sas-03b-sync-convergence Finish truthful sync and deterministic convergence

Status: Open
Priority: P0
Type: task
Depends On: sas-03a-account-routing
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

The routed identified profile has truthful event state, recoverable history and reviewed convergence behavior.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-03
- AC-04
- AC-10
- Slice 03B

## Grilling Evidence

- Every rejected SAS-03 correctness/security finding is explicit acceptance scope.

## Worker Profile

reuse app-store-data-engineer

Rationale:

History, repository and account lifecycle share the same Data owner.

## Context

The rejected pass is reusable only after it conforms to ADR-007 routing and review findings.

## What To Do

- Implement initial refresh, overlapping event tracking, observable failure/retry and nondestructive cursor rebuild.
- Reconcile changed notes/cards, revoked schedules, duplicate logs and malformed identities safely; wire minimal Settings retry.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/Sync/
- Packages/FlashUpKit/Sources/FlashUpData/Persistence/
- Packages/FlashUpKit/Sources/FlashUpData/Repositories/
- Packages/FlashUpKit/Sources/FlashUpDomain/Repositories/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- App/AppEnvironment.swift
- App/Features/Settings/SettingsView.swift
- App/Resources/Localizable.xcstrings
- docs/testing/cloudkit-personal-checklist.md

## Acceptance Criteria

- [ ] Availability never fabricates up-to-date and overlapping events remain truthful.
- [ ] Corrupt/stale cursor recovers without store mutation.
- [ ] Changed-note/revoked-log/duplicate-log/malformed-row fixtures converge safely.
- [ ] Processing failure is visible/retryable while local use stays green.
- [ ] Correctness and security reviews approve.
- [ ] Real account cells remain HUMAN_REQUIRED.

## Verification

- `Focused sync/convergence/failure tests`: expected to pass or produce documented output
- `swift test`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `ci/lint.sh`: expected to pass or produce documented output

## Out Of Scope

- Profile transfer, backup format, visual redesign, Apple operations, assets/emma-avatar/.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
