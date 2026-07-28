# Flash Up v1 — Batch implementation contract

Status: Approved

Source specification: `flash-up-implementation-spec.md`. Product decisions remain in
`flash-up-architecture-brief.md`. This adapter exists only to give the Flywheel runner a
machine-checkable contract; it does not amend either approved source.

## Grilling Evidence

- The architecture brief and implementation specification are approved inputs.
- The only architecture assumptions that need empirical proof are isolated in
  `fu-01-store-spike`, `fu-02-sharing-spike`, and `fu-03-fsrs-spike`.
- A finding that contradicts either source creates an ADR and blocks the affected batch.

## Goal

Ship Flash Up v1: a paid, local-first, bilingual iOS/iPadOS spaced-repetition app with
private FSRS progress, Core Data plus CloudKit sync, import/export/backup, and optional
collaborative groups.

## Problem

The approved plan has 48 deliberately small beads. Implementing them one by one would
reload the same model, domain contracts, and UI state repeatedly. We need fewer dispatches
without weakening the data-integrity, CloudKit, or release evidence required by the source.

## In Scope

- The 16 batch beads in `docs/flywheel-runs/flash-up-v1/batch-plan.md`.
- The original B-prefixed bead coverage recorded in each batch bead.
- Worker profiles, briefs, dependency ordering, and Flywheel run evidence.
- A local Git repository and a vendored `agent-flywheel/` workflow kit.

## Out of Scope

- Changing product requirements or the approved technical architecture.
- Creating a remote GitHub repository, pushing, publishing, or submitting an App Store build without explicit approval.
- Broadening a batch after an empirical CloudKit, FSRS, migration, privacy, or deletion finding.

## Acceptance Criteria

- Each original B0.1 through B9.3 requirement has exactly one batch owner or is recorded as a manual release prerequisite.
- The graph has no cycles and uses the smallest safe number of batches.
- The three architecture proofs remain separate before their production consumers.
- Every batch includes outcome, dependencies, acceptance criteria, verification, likely files, and out-of-scope boundaries.
- Future workers can begin at the ready batch using only the task bead, brief, context pack, and this contract.

## Verification

- `python3 agent-flywheel/scripts/flywheel-runner.py validate --project . --run-id flash-up-v1 --stage dispatch` reports no errors.
- Inspect `docs/flywheel-runs/flash-up-v1/batch-plan.md` against Part B of the source specification.
- Inspect `docs/tasks/flash-up-v1/` and `docs/worker-briefs/flash-up-v1/` for one artifact per batch.

## Open Questions

- none

## Task Beads

- `fu-00-scaffold`: Scaffold Flash Up and its CI contract
- `fu-01-store-spike`: Prove the two-store CloudKit topology
- `fu-02-sharing-spike`: Prove sharing, acceptance, and graph movement
- `fu-03-fsrs-spike`: Pin and prove the FSRS adapter contract
- `fu-04-data-core`: Build the CloudKit-safe data core
- `fu-05-note-domain`: Complete the note lifecycle domain contract
- `fu-06-study-engine`: Build deterministic private study scheduling
- `fu-07-portability`: Deliver portable import, export, and backup services
- `fu-08-library-edit-import`: Ship the content-management vertical slice
- `fu-09-today-study-ui`: Ship the study experience
- `fu-10-settings-onboarding`: Complete settings, onboarding, reminders, and support
- `fu-11-group-connect`: Connect group owners and members
- `fu-12-group-move`: Manage group membership and move deck graphs
- `fu-13-group-history`: Complete shared revision and ownership lifecycle
- `fu-14-guidance-and-erasure`: Finish contextual guidance and user-data erasure
- `fu-15-release`: Audit, validate, and submit Flash Up v1
