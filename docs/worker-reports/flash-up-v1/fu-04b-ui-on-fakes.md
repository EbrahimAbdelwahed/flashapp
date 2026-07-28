# Worker Report: fu-04b-ui-on-fakes

Status: complete
Run ID: `flash-up-v1`
Task: `docs/tasks/flash-up-v1/fu-04b-ui-on-fakes.md`
Brief: `docs/worker-briefs/flash-up-v1/fu-04b-ui-on-fakes.md`
Agent: ios-product-engineer
Reported: 2026-07-28 16:21

## Files Changed

- FlashUpDomain/Content/{Deck,Note,Card,CardGenerator}.swift, Repositories/LibraryRepository.swift
- FlashUpData/Preview/{DemoContent,InMemoryLibrary}.swift
- App/Design/{GlassSurface,Spacing}.swift
- App/Features/Today/{TodayModel,TodayView}.swift, Study/{StudySessionModel,StudySessionView,GradeButton}.swift, Shared/{CountTile,PrimaryActionButton,DeckRow,RootTabView}.swift
- App/Resources/Localizable.xcstrings (26 new strings, en + it), App/AppEnvironment.swift

## Behavior Implemented

- LibraryRepository boundary in domain value types; InMemoryLibrary implements it fully, including undo
- CardGenerator per A3.1 with stable template keys
- GlassSurface: the single OS branch, real Liquid Glass on iOS 26 and a material fallback below
- Today opens on the primary action; study loop reveals, grades with real FSRS interval captions, and undoes

## Verification

- ci/test.sh: SwiftLint 0 violations in 41 files, swift test 75/75, xcodebuild test iPhone 15 iOS 17.4 TEST SUCCEEDED
- Manual: full study loop driven on iPhone 17 / iOS 26.4 and Today verified on iPhone 15 / iOS 17.4

## Open Questions Or Blockers

- None.

## Follow-up Beads Needed

- UI test for the study loop (reveal, grade, undo) — B6.1 requires one; only the shell is covered today
- fu-04-data-core: implement LibraryRepository over Core Data and swap it in AppEnvironment; no view should change
- fu-06-study-engine: replace the preview queue and metrics in InMemoryLibrary with QueueBuilder and MetricsService
