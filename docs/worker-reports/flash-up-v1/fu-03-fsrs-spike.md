# Worker Report: fu-03-fsrs-spike

Status: complete
Run ID: `flash-up-v1`
Task: `docs/tasks/flash-up-v1/fu-03-fsrs-spike.md`
Brief: `docs/worker-briefs/flash-up-v1/fu-03-fsrs-spike.md`
Agent: study-domain-engineer
Reported: 2026-07-28 15:30

## Files Changed

- Packages/FlashUpKit/Package.swift (swift-fsrs pinned to revision 4fbaf20 instead of tag 5.0.0)
- Packages/FlashUpKit/Sources/FlashUpDomain/Scheduling/{Grade,ReviewState,FSRSService,SwiftFSRSAdapter}.swift
- Packages/FlashUpKit/Tests/FlashUpDomainTests/SwiftFSRSAdapterTests.swift
- docs/decisions/ADR-003-fsrs.md

## Behavior Implemented

- FSRSService protocol in FlashUpDomain; SwiftFSRSAdapter is the only file importing swift-fsrs
- Deterministic scheduling: fuzz explicitly disabled, desired retention 0.90, FSRS v5 weights
- Four-grade interval preview that provably matches the committed answer

## Verification

- swift test: 12 tests in 3 suites passed
- ci/test.sh: SwiftLint 0 violations in 14 files, swift test 12/12, xcodebuild test iPhone 15 iOS 17.4 TEST SUCCEEDED

## Open Questions Or Blockers

- swift-fsrs tag 5.0.0 declares its scheduler API internal and is unusable; the pin is an unreleased commit (ADR-003 section 2). Owner sign-off wanted, work continues meanwhile.

## Follow-up Beads Needed

- fu-15-release: re-check for a tagged swift-fsrs release with the public API and move the pin from revision to tag
- fu-04-data-core: CDSchedule attribute set confirmed sufficient; do not add fields for elapsed/scheduled days
