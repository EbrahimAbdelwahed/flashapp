# Task Bead: fu-10-settings-onboarding Complete settings, onboarding, reminders, and support

Status: Open
Priority: P1
Type: task
Depends On: fu-07-portability, fu-08-library-edit-import, fu-09-today-study-ui
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

A new user onboards into a studyable demo deck and can control settings, backup, reminders, support, and review prompting.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B8.1
- B8.2
- B8.4
- B8.6

## Grilling Evidence

- Notifications require opt-in; support diagnostics never contain user content.

## Worker Profile

reuse ios-product-engineer

Rationale:

All work is system-facing SwiftUI presentation and application-state wiring.

## Context

Settings hosts the four source features and allows one coherent preference/state pass.

## What To Do

- Build Settings root/data/sync sections, mandatory onboarding and demo deck, reminder state machine/UI, SupportComposer, and review milestone.

## Likely Files / Packages

- App/Features/Settings/
- App/Features/Onboarding/
- App/Resources/
- FlashUpUITests/

## Acceptance Criteria

- [ ] Every B8.1, B8.2, B8.4, and B8.6 stop condition holds.
- [ ] Backup restore works from UI and onboarding creates a studyable demo deck.

## Verification

- `UI backup round trip`: expected to pass or produce documented output
- `Reminder state tests`: expected to pass or produce documented output
- `Diagnostics no-content test`: expected to pass or produce documented output

## Out Of Scope

- Group tutorial, delete-all-data flow, release audit.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
