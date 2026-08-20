# Task Bead: sas-05-release-surface Expose only the honest 1.0 product surface

Status: Open
Priority: P0
Type: task
Depends On: sas-04b-scoped-transfer-erasure
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

The release UI has Today, Library and Settings only, persistent generalist first-run content, real sync/backup states and contextual reminder denial guidance.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-06
- AC-07
- AC-08
- Slice 05

## Grilling Evidence

- Owner removed Groups, chose skippable onboarding, generalist demo, direct reminder permission and quiet iCloud positioning.

## Worker Profile

create app-store-product-engineer

Rationale:

One UI owner prevents shell, onboarding, Settings, localization and UI-test drift.

## Context

Existing UI is complete on fakes but exposes Groups, simulated sync and medical demo content.

## What To Do

- Remove Groups navigation/copy/tutorial and use three tabs.
- Install original generalist EN/IT demo content idempotently on finish or skip.
- Wire real sync and backup UI; add Settings guidance after notification denial; align privacy/help/reviewer copy.

## Likely Files / Packages

- App/Features/
- App/Resources/Localizable.xcstrings
- App/Resources/DemoDeck/
- FlashUpUITests/

## Acceptance Criteria

- [ ] Exactly three tabs and no unavailable feature/false sync claim.
- [ ] Finish and skip both produce persistent useful demo content.
- [ ] Reminder denial, backup UI and EN/IT reviewer journey are covered.
- [ ] Accessibility and reduced-motion behavior remain correct.

## Verification

- `Focused XCUITests on iPhone/iPad`: expected to pass or produce documented output
- `Production-route screenshot diff`: expected to pass or produce documented output
- `Unprimed screenshot critique`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output

## Out Of Scope

- Core Data/model changes, release account operations, assets/emma-avatar/.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
