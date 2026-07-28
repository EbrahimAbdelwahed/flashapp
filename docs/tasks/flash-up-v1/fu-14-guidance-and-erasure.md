# Task Bead: fu-14-guidance-and-erasure Finish contextual guidance and user-data erasure

Status: Open
Priority: P1
Type: task
Depends On: fu-10-settings-onboarding, fu-13-group-history
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

Users can replay contextual help and can erase only their own data through an explicit, backup-first flow.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B8.3
- B8.5

## Grilling Evidence

- Deletion is ordered, confirmation-gated, and must not harm joined groups owned by others.

## Worker Profile

reuse ios-product-engineer

Rationale:

The work is product guidance plus irreversible-flow UI built on established settings and group surfaces.

## Context

Both beads are trust-building final product behavior that depends on finished groups/settings.

## What To Do

- Build tutorial replay/Help FAQs and the typed-confirmation, backup-offer, ordered deletion flow with onboarding return.

## Likely Files / Packages

- App/Features/Settings/
- App/Features/Groups/
- Packages/FlashUpKit/Sources/FlashUpData/
- FlashUpUITests/

## Acceptance Criteria

- [ ] B8.3 and B8.5 stop conditions hold.
- [ ] Wrong erase confirmation cannot execute; joined groups remain intact for their owners.

## Verification

- `Delete-order data test`: expected to pass or produce documented output
- `Confirmation-gate UI test`: expected to pass or produce documented output
- `Two-account erasure check`: expected to pass or produce documented output

## Out Of Scope

- Localization/a11y release audit or App Store submission.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
