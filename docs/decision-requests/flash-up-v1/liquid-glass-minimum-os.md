# Decision Request: liquid-glass-minimum-os

Status: Resolved
Run ID: `flash-up-v1`
Bead: fu-08-library-edit-import
Agent: ios-foundation-engineer
Created: 2026-07-28 15:18

## Severity

blocking

## Decision Type

product

## Question

Flash Up now targets a Liquid Glass interface. Native Liquid Glass runs on iOS 26 and later, while the approved brief pins the minimum to iOS/iPadOS 17. Which minimum deployment target does v1 ship with?

## Context

Every UI batch inherits this: fu-08-library-edit-import, fu-09-today-study-ui, fu-10-settings-onboarding, fu-11 through fu-14. Deciding after those batches start would mean reworking them.

## Options

1. `ios26`: Raise the minimum to iOS/iPadOS 26
   - Consequence: One visual path, real Liquid Glass everywhere, no fallback code or double testing. Excludes devices that stop at iOS 18 (iPhone XS/XR and older).

2. `ios17-progressive`: Keep iOS 17 minimum and enhance progressively
   - Consequence: Widest reach. Liquid Glass on iOS 26+, a material-based approximation below it. Every UI bead ships and tests two appearances, adding roughly 20-30 percent UI effort and a permanent second visual path.

3. `ios18`: Raise the minimum to iOS 18
   - Consequence: Does not deliver Liquid Glass; only drops the oldest devices. Rejected unless the goal changes.

## Recommendation

Recommended option: `ios26`

Reason:

iOS 26 shipped in September 2025 and iOS 27 is due within months, so adoption among students is already high. The product goal just became design-led with a near-zero learning curve; carrying a second, visually different path contradicts that goal and taxes every remaining UI batch. If reach is the priority instead, ios17-progressive is the correct answer and the cost is accepted up front.

## Default If Unanswered

Block all UI batches (fu-08 onward). Non-UI batches (fu-01 through fu-07) proceed unaffected.

## Links

- `docs/tasks/flash-up-v1/fu-08-library-edit-import.md`

## Resolution

Answered by: product owner
Answered at: 2026-07-28 15:45
Decision: ios17-progressive
Follow-up beads:
