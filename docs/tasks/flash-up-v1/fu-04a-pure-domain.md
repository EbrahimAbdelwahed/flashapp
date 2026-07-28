# Task Bead: fu-04a-pure-domain Build the storage-free domain codecs

Status: Done (2026-07-28) — report: `docs/worker-reports/flash-up-v1/fu-04a-pure-domain.md`
Priority: P0
Type: task
Depends On: fu-00-scaffold
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Why this bead exists

Created on 2026-07-28, after the owner confirmed there is no Apple Developer account yet.
`fu-01-store-spike` needs a real iCloud container, `fu-02-sharing-spike` needs two Apple
accounts, and `fu-04-data-core` depends on `fu-01` — so the entire persistence lane is
blocked on an account, not on engineering.

This bead carves out the work that the **source specification itself** marks as depending
only on B0.1, so it is not a re-slice of the dependency graph:

- **B2.1 — ClozeParser** ("Deps: B0.1"), normally inside `fu-05-note-domain`.
- **B4.1 — CSVParser** ("Deps: B0.1"), normally inside `fu-07-portability`.

Both are pure `FlashUpDomain` logic with no Core Data, no CloudKit and no UI. Their parent
batches keep every other original bead and their own acceptance criteria; each parent's
coverage list is amended to record that these two are already delivered here.

## Spec Coverage

- B2.1 (moved out of `fu-05-note-domain`)
- B4.1 (moved out of `fu-07-portability`)

## What To Do

- Implement the A3.4 cloze scanner and renderer with issue reporting.
- Implement the A9.1 RFC 4180 CSV parser with row validation and hard caps.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpDomain/Cloze/
- Packages/FlashUpKit/Sources/FlashUpDomain/CSV/
- Packages/FlashUpKit/Tests/FlashUpDomainTests/

## Acceptance Criteria

- [x] B2.1: single, multiple and repeated groups; hints; malformed input (unclosed,
      `{{c0::}}`, empty text, nested braces); unicode; `groups(in:)`; render masking with
      and without hint; issue reporting.
- [x] B4.1: quoting, escapes, newlines inside quotes, CRLF and LF, BOM strip, non-UTF-8
      rejection, case-insensitive headers, extra and missing columns, row validation,
      hard caps.

## Verification

- `swift test`: passed — 60 tests in 5 suites, no simulator required.
- `ci/test.sh`: passed — SwiftLint 0 violations, domain tests green, UI tests
  `** TEST SUCCEEDED **`.

## Out Of Scope

- Core Data, CloudKit, card generation, the import planner and committer, and all UI.
  Those stay with `fu-05-note-domain` and `fu-07-portability`.
