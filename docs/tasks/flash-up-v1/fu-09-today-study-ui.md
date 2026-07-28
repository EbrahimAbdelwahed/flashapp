# Task Bead: fu-09-today-study-ui Ship the study experience

Status: Open
Priority: P1
Type: task
Depends On: fu-06-study-engine, fu-08-library-edit-import
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

Today, statistics, study session, resume, undo, and completion are usable and accessible on iPhone and iPad.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B5.2
- B5.7
- B6.1
- B6.2

## Grilling Evidence

- FSRS grade captions and session persistence are already frozen by fu-06.

## Worker Profile

reuse ios-product-engineer

Rationale:

Uses the same SwiftUI navigation, Markdown, localization, and UI-test ownership as the Library batch.

## Context

Metrics presentation and study interaction share session state and accessibility work.

## What To Do

- Build Today/Statistics, StudySession, completion/resume UI, charts accessibility, keyboard shortcuts, reduced motion, and reminder event hook.

## Likely Files / Packages

- App/Features/Today/
- App/Features/Study/
- FlashUpUITests/

## Acceptance Criteria

- [ ] Every B5.2, B5.7, B6.1, and B6.2 stop condition holds.
- [ ] Seeded session supports different grades, undo, relaunch/resume, and completion.

## Verification

- `XCUITest session lifecycle`: expected to pass or produce documented output
- `VoiceOver and iPad layout audit`: expected to pass or produce documented output

## Out Of Scope

- Reminder permission UI, onboarding, groups.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
