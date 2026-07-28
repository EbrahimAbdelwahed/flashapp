# Task Bead: fu-11-group-connect Connect group owners and members

Status: Open
Priority: P0
Type: task
Depends On: fu-02-sharing-spike, fu-08-library-edit-import
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

An owner can create/invite and a second Apple account can accept and see a shared group safely.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B7.1
- B7.2

## Grilling Evidence

- ADR-002 defines the acceptance hook and no-iCloud behavior.

## Worker Profile

reuse cloudkit-systems-engineer

Rationale:

Production sharing must preserve the architecture learned in both CloudKit spikes.

## Context

Owner/member connection is a single end-to-end contract and the prerequisite for all group work.

## What To Do

- Implement ShareManager, group creation/invite UI, sharing controller wrapper, application acceptance wiring, local-only states, and checklist.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/
- App/Features/Groups/
- App/FlashUpApp.swift
- docs/testing/

## Acceptance Criteria

- [ ] B7.1 and B7.2 stop conditions hold across two accounts.
- [ ] Revoked/already-member/no-iCloud states are safe and localized.

## Verification

- `Two-account invitation checklist`: expected to pass or produce documented output
- `Manual local-only mode check`: expected to pass or produce documented output

## Out Of Scope

- Deck movement, group leave/removal, revision history.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
