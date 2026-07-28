# Task Bead: fu-08-library-edit-import Ship the content-management vertical slice

Status: Open
Priority: P1
Type: task
Depends On: fu-04-data-core, fu-05-note-domain, fu-07-portability
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

Users can navigate the app, create/edit/search/import/export content, and recover it from trash with accessible localized UI.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B4.3
- B5.1
- B5.3
- B5.4
- B5.5
- B5.6

## Grilling Evidence

- Editor autosave, Markdown rendering, content privacy, and trash semantics follow the approved spec.

## Worker Profile

create ios-product-engineer

Rationale:

The navigation shell, Library, import flow, and editor repeatedly use SwiftUI state, accessibility, and localization seams.

## Context

One vertical content-management pass eliminates repeated navigation/view-model integration work.

## What To Do

- Build AppEnvironment and shell, Library/Deck/Trash/Search views, full note editor/Markdown preview, and file/share import flow with undo.

## Likely Files / Packages

- App/
- FlashUpUITests/
- Packages/FlashUpKit/Sources/FlashUpData/

## Acceptance Criteria

- [ ] Every covered source bead stop condition holds.
- [ ] Create, edit, import, search, trash, restore flow is covered by UI tests.

## Verification

- `XCUITest content lifecycle`: expected to pass or produce documented output
- `iPhone/iPad manual smoke`: expected to pass or produce documented output
- `SwiftLint`: expected to pass or produce documented output

## Out Of Scope

- Study session, sharing UI, settings/onboarding.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
