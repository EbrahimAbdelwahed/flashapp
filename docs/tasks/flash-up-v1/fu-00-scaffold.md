# Task Bead: fu-00-scaffold Scaffold Flash Up and its CI contract

Status: Done (2026-07-28) — report: `docs/worker-reports/flash-up-v1/fu-00-scaffold.md`
Priority: P0
Type: task
Depends On: none
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

A booting iOS/iPadOS project with the required targets, dependencies, localization shell, and CI wrappers.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B0.1

## Grilling Evidence

- Approved implementation specification; bundle identifier and CloudKit container naming remain a configuration placeholder.

## Worker Profile

create ios-foundation-engineer

Rationale:

The scaffold and later Apple-platform integration work reuse the same Xcode, package, and CI knowledge.

## Context

Creates the only supported project shape before production behavior exists.

## What To Do

- Create the app, package, test targets, SPM dependencies, capabilities, String Catalog, lint config, CI wrappers, and four-tab placeholder.

## Likely Files / Packages

- FlashUp.xcodeproj
- App/
- Packages/FlashUpKit/
- FlashUpUITests/
- ci/
- .swiftlint.yml

## Acceptance Criteria

- [x] B0.1 stop conditions hold on iPhone and iPad simulators.
- [x] Architecture brief and worklog are copied into docs.

## Verification

- `ci/test.sh`: passed — SwiftLint 0 violations, `swift test` 2/2, `xcodebuild test` on
  iPhone 15 / iOS 17.4 `** TEST SUCCEEDED **`; the same UI tests also pass on
  iPad Pro 11-inch (M4) / iOS 17.4.
- `ci/build.sh`: passed — Release `** BUILD SUCCEEDED **` on both simulators.
  `ci/build.sh archive` is written but unverified (no Apple Developer team yet).
- `SwiftLint`: passed — `STRICT_LINT=1 ci/lint.sh`, SwiftLint 0.65.0, 0 violations in
  9 files.

## Out Of Scope

- Core Data model or feature implementation.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
