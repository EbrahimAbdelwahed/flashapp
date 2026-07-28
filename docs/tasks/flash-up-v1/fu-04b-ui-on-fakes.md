# Task Bead: fu-04b-ui-on-fakes Build the interface against an in-memory library

Status: Done (2026-07-28) — report: `docs/worker-reports/flash-up-v1/fu-04b-ui-on-fakes.md`
Priority: P0
Type: task
Depends On: fu-04a-pure-domain
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Why this bead exists

Created on 2026-07-28 at the owner's direction: the interface does not need CloudKit, it
needs data. Building the repository boundary first lets every screen be designed, run and
demonstrated now, and lets `fu-04-data-core` slot the Core Data implementation in behind the
same protocol without touching a single view.

This is a **preview-stage** bead, not a replacement for its parent batches. `fu-08`, `fu-09`
and `fu-06` keep all their source-bead coverage: search, trash, editor, import flow, session
persistence, statistics, the real `QueueBuilder` and `MetricsService` are all still theirs.

## Spec Coverage

- B2.2 (domain half only: `CardGenerator` per §A3.1). The `CardReconciler` half stays in
  `fu-05-note-domain`.
- Partial, preview-stage: §A11.1 shell wiring, §A11.2 Today, §A11.3 study interaction.

## What To Do

- Domain content model, card generation, and the `LibraryRepository` boundary.
- An in-memory repository with realistic seeded content.
- The design system that owns the Liquid Glass / iOS 17 split, plus Today and the study
  session built on it.

## Acceptance Criteria

- [x] No view knows which repository implementation is in use.
- [x] Exactly one file branches on the OS version for appearance.
- [x] Today opens on the primary action; the study loop reveals, grades and undoes.
- [x] Every new string ships in English and Italian.
- [x] Verified on both an iOS 17 and an iOS 26 simulator.

## Verification

- `ci/test.sh`: passed — SwiftLint 0 violations in 41 files, 75 domain tests, UI tests
  `** TEST SUCCEEDED **` on iPhone 15 / iOS 17.4.
- Manual: study loop driven end to end on iPhone 17 / iOS 26.4 (prompt, reveal, four graded
  intervals from the pinned FSRS engine).

## Out Of Scope

- Persistence, sync, groups, Library and Settings screens, session resume, statistics,
  onboarding, import UI. All remain with their original batches.
