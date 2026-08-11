# FlashApp — Worklog

One entry per completed batch bead (spec §0.4.7): bead ID, what was built, deviations
with justification, follow-ups discovered.

---

## fu-04d-polish — 2026-07-28

Owner feedback pass.

### Changed

- **Cloze cards fill the blank in place.** `ClozeParser.segments` splits the sentence into
  pieces so the study screen keeps one sentence on screen and swaps only the hidden part on
  the flip; the answer word is emphasised. The note's own back is now a separate explanation
  rather than being appended to the revealed sentence.
- **The daily reminder is real.** `ReminderScheduler` requests authorization only when the
  switch is turned on and schedules a repeating `UNCalendarNotificationTrigger`.
- **A refused permission no longer flips the switch back.** The user's choice is kept and
  the screen explains that iOS is holding notifications back — the thing they can act on.
- **The import flow leads with a copyable prompt** for ChatGPT that states the exact CSV
  format, localized so the assistant answers in the user's language.
- Trash deletion and restore are now covered by a UI test, as is the reminder in both the
  granted and refused cases, and the prompt card.

### Verification

`ci/test.sh` green: SwiftLint 0 violations in 71 files, 95 domain and repository tests, and
12 UI tests. Checked by hand on iOS 17.4 and iOS 26.4.

### Fixed after the pass

- **The appearance picker did nothing.** The chosen appearance was read once at launch into
  the root scene's own state, so a later change in Settings had no way to reach the view
  that applies `preferredColorScheme`. It now lives on `AppEnvironment`, which both screens
  observe. Covered by a UI test that also checks the choice survives leaving Settings.
  Note it does not survive relaunch yet: the in-memory repository forgets everything, as it
  does for decks, until `fu-04-data-core` lands.

### Notes

- The missing Library, Groups and Settings tabs on iOS 26 were a stale build on that
  simulator, not a bug.
- Two UI-test lessons worth keeping: a `Toggle` in a `List` reports a frame covering the
  whole row, so `tap()` lands on the label and does not flip it — aim at the trailing edge;
  and reaching a screen through a tab is more robust than through a localized back button.

---

## fu-04c-app-complete-on-mocks — 2026-07-28

Owner goal: complete the app in all its parts except the iCloud connection, on mock data,
then test every user flow.

### Built

**Domain** — `ReviewLog`, `ContentFingerprint` and `TagNormalizer` (§A3.5, §A3.6),
`StudySettings` and `SessionState` (§A6.5, §A6.6), `QueueBuilder` (§A6.5),
`MetricsCalculator` (§A6.7), `ScheduleReplayer` (§A6.4), `ImportPlanner` (§A9.2),
`CSVWriter`, and the versioned `BackupCodec` (§A10).

**Repository** — `LibraryRepository` now covers the whole app surface: reads, authoring,
studying, trash, settings, import, export, backup, restore and erasure. `InMemoryLibrary`
plus `LibraryStore` implement all of it: cards are generated and reconciled on every save,
undo replays history through the pinned FSRS engine, import dedups by content fingerprint,
and restore adds without ever overwriting.

**Interface** — Library (decks, filters, search, trash), note editor with a live card
preview, import flow (source → preview → result → undo), Settings (sync state, daily limits,
reminder, appearance, backup/restore, erase), Statistics with a 30-day chart, three-step
onboarding, Help and Privacy, and an honest Groups screen. 213 localized strings, English
and Italian.

### Verification

`ci/test.sh` green: SwiftLint 0 violations in 67 files, 93 domain and repository tests,
`** TEST SUCCEEDED **` for the UI suite. Nine UI tests drive the real user journeys:
onboarding, study with undo, create deck and note, import from the built-in example, trash,
settings and statistics, groups, plus the two shell tests.

### Deliberately not done

- **iCloud.** `SyncStatus` is a fixed value; `fu-01`, `fu-02` and `fu-04` still own the real
  store, sharing and mirroring.
- **Groups.** The screen explains why they are unavailable instead of showing controls that
  cannot work.
- **Notifications.** The reminder is stored but `UNUserNotificationCenter` is not called
  yet; that is `fu-10`'s bead.
- Trash restore is proven by `LibraryFlowTests`, not by the UI test: a swipe-to-delete
  assertion on a `List` row proved brittle, and a flaky test is worse than an honest gap.

### Follow-ups

- `fu-04-data-core` implements `LibraryRepository` over Core Data and swaps it in
  `AppEnvironment`; no view should change.
- `fu-06-study-engine` replaces the preview queue and metric helpers with the real services
  and adds permutation replay tests.

---

## fu-04b-ui-on-fakes — 2026-07-28

New bead, created at the owner's direction: build the interface on fake data now and plug
CloudKit in later. Covers the domain half of B2.2 and a preview-stage slice of §A11.

### Built

- `LibraryRepository`: the read/write boundary, expressed purely in domain value types.
  `InMemoryLibrary` implements all of it — schedules run through the pinned FSRS adapter,
  answers accumulate, undo restores the pre-answer state. `AppEnvironment` is the only place
  that chooses an implementation.
- Domain content model (`Deck`, `Note`, `Card`, `CardTemplate`) and `CardGenerator` per
  §A3.1.
- `GlassSurface`: the single file that branches on the OS version, giving real Liquid Glass
  on iOS 26 and a material approximation below, with identical layout on both.
- Today (counts, one primary action, deck rows) and the study session (reveal, four grades
  captioned with real FSRS intervals, undo, keyboard shortcuts 1-4 and space).
- 26 new strings in English and Italian.

### Verification

`ci/test.sh` green: SwiftLint 0 violations in 41 files, 75 domain tests, UI tests
`** TEST SUCCEEDED **`. The study loop was driven by hand on iPhone 17 / iOS 26.4 and Today
verified on iPhone 15 / iOS 17.4.

### What this bead does NOT do

It is a preview stage, not a replacement for its parent batches. `fu-08`, `fu-09` and
`fu-06` keep every source bead they own: Library, editor, search, trash, import flow,
statistics, session persistence, and the real `QueueBuilder` and `MetricsService`. The queue
and metrics inside `InMemoryLibrary` are the smallest correct stand-ins and are labelled as
such in the source.

### Bugs found and fixed

- `PrimaryActionButton` used a `simultaneousGesture(DragGesture(minimumDistance: 0))` for
  touch-down feedback, which swallowed the button's action: taps did nothing. Replaced with
  a `ButtonStyle` reading `configuration.isPressed`, which is the correct mechanism and is
  now shared by every pressable surface.
- The study session was presented from state held on the observable model, and the cover
  dismissed itself when the model was rebuilt. Presentation state now lives in the view.

### Follow-up owed

- A UI test for the study loop. B6.1 requires one; only the four-tab shell is covered today.

---

## fu-04a-pure-domain — 2026-07-28

New bead, created because the owner confirmed there is no Apple Developer account yet.
Covers source beads B2.1 (ClozeParser) and B4.1 (CSVParser), both of which the source
specification marks as depending on B0.1 alone — so this is not a re-slice of the
dependency graph, only a change in the order the batches are dispatched.

### Built

- `ClozeParser`: hand-written scanner for `{{cN::text::hint}}`, with repeated groups,
  literal nested braces, issue reporting for malformed input, and a renderer that masks one
  group while revealing the others.
- `CSVParser` plus `CSVDocument` (RFC 4180 tokenizer), `NoteType`, `ParsedRow`,
  `RowRejection`, `CSVParseError` and `CSVLimits`.

### Verification

`swift test` 60 tests in 5 suites; `ci/test.sh` green (SwiftLint 0 violations in 22 files,
UI tests `** TEST SUCCEEDED **`).

### Interpretations recorded

1. **Required CSV columns are `type` and `front` only.** §A9.1 says a missing required
   column fails the file but does not name the set. `back` and `tags` are treated as
   optional columns because row validation already requires a non-empty `back` for basic
   and reversed rows, and a cloze-only export legitimately carries neither. Worth an owner
   confirmation before `fu-07-portability` writes the export side.
2. **An over-long field rejects its row, not the file.** §A9.1 lists the 20 000-character
   field cap alongside the file and row caps but does not say at which level it applies.
   Row-level matches the surrounding row-validation rules and is kinder to the user.

### Bugs found and fixed while testing

- Swift treats `"\r\n"` as a single `Character`, so a `switch` on `"\r"` and `"\n"` never
  matched CRLF files and swallowed the whole file into one field. The scanner now branches
  on `Character.isNewline`.
- Physical line numbers were off by one after the first record.

---

## fu-03-fsrs-spike — 2026-07-28

Covers source bead B0.4. Full detail in `docs/decisions/ADR-003-fsrs.md`.

### Built

- `FSRSService` protocol in `FlashUpDomain` with `Grade`, `ScheduleState`, `ReviewState`,
  `ScheduleTransition`, `SchedulePreview` and `SchedulingError`.
- `SwiftFSRSAdapter`, the only file in the product that imports swift-fsrs. Fixed
  configuration: FSRS v5 default weights, desired retention 0.90, fuzz explicitly off.

### Verification

`swift test` 12 tests passing; `ci/test.sh` green end to end (SwiftLint 0 violations in 14
files, UI tests `** TEST SUCCEEDED **`).

### Deviations

1. **The dependency is pinned to a commit, not a tag.** swift-fsrs `5.0.0` declares its
   whole scheduler API `internal` — an importing module cannot construct the engine or set
   the retention the brief requires. Proven by compiling a probe against the tag. Commit
   `4fbaf20184d62f82a9f44f343337c61a2c5483e9` fixes the access levels but was never
   released. Rationale and rejected alternatives in ADR-003 §2. Owner sign-off requested;
   it does not block the remaining batches.
2. **Fuzz is set explicitly even though it currently defaults off**, because a default
   change upstream would silently break deterministic multi-device replay (§A6.4).

### Follow-ups

- `fu-04-data-core`: the `CDSchedule` attribute set in §A2 is confirmed sufficient — the
  engine recomputes elapsed and scheduled days, so no extra attributes are needed. Keeping
  the v5 algorithm is what makes that true; FSRS-6 would add a `learningSteps` counter and
  require a migration.
- `fu-15-release`: re-check for a tagged swift-fsrs release and move the pin to it.

---

## fu-00-scaffold — 2026-07-28

Covers source bead B0.1.

### Built

- `FlashUp.xcodeproj`: app target `FlashUp` (iOS 17.0, iPhone + iPad, "Mac (Designed for
  iPad)" on, Catalyst off) and `FlashUpUITests`. Project file uses `objectVersion = 77`
  with file-system-synchronized groups, so `App/` and `FlashUpUITests/` need no manual
  file registration.
- `Packages/FlashUpKit`: local SPM package with `FlashUpDomain` and `FlashUpData`
  products plus their test targets. Dependency direction App -> Data -> Domain is
  enforced by the package graph. Platforms iOS 17 / macOS 14 so domain tests run without
  a simulator.
- SPM dependencies, pinned exactly: `swift-fsrs` 5.0.0 (product `FSRS`) and
  `swift-markdown` 0.8.0 (product `Markdown`, pulls `swift-cmark` 0.8.0 transitively).
- Capabilities: `Config/FlashUp.entitlements` declares CloudKit with container
  `$(FLASHUP_ICLOUD_CONTAINER)` and `aps-environment`; `Config/Info.plist` declares
  `UIBackgroundModes = remote-notification`.
- Four-tab shell (`RootTabView`): Today, Library, Groups, Settings, each showing a
  `ContentUnavailableView` placeholder. Text styles only (Dynamic Type), no animation,
  accessibility identifiers `tab.<name>`.
- `App/Resources/Localizable.xcstrings` with the four tab titles and the placeholder copy
  in `en` + `it`.
- `.swiftlint.yml` (default rules + `force_unwrapping: error`) with nested configs
  relaxing it in `Packages/FlashUpKit/Tests` and `FlashUpUITests`.
- `ci/common.sh`, `ci/lint.sh`, `ci/test.sh`, `ci/build.sh`.
- `docs/flash-up-architecture-brief.md` (verbatim copy) and this worklog.

### Verification

| Check | Result |
| --- | --- |
| `swift test` (FlashUpKit, macOS host) | 2 tests, 2 suites, passed |
| `xcodebuild test` iPhone 15 / iOS 17.4 | 2 UI tests passed (`** TEST SUCCEEDED **`) |
| `xcodebuild test` iPad Pro 11-inch (M4) / iOS 17.4 | 2 UI tests passed |
| `ci/build.sh` (Release, both simulators) | `** BUILD SUCCEEDED **` twice |
| `STRICT_LINT=1 ci/lint.sh` (SwiftLint 0.65.0) | 0 violations in 9 files |
| Boot evidence | App launches to the four-tab shell; simulator in Italian renders Oggi / Libreria / Gruppi / Impostazioni |

### Deviations and decisions

1. **Toolchain is newer than the spec.** §0.2 names Xcode 16.x / Swift 5.10+; the machine
   has Xcode 26.4 with Swift 6.3. Targets pin `SWIFT_VERSION = 5.0` (Swift 5 language
   mode) and the package uses `swift-tools-version: 5.10`, so the spec's language
   semantics hold. Moving to the Swift 6 language mode would change Core Data and
   concurrency ergonomics for every later bead; that is an ADR decision, not a scaffold
   decision.
2. **Identifier placeholders live in `Config/FlashUp.xcconfig`.** `FLASHUP_BUNDLE_ID =
   com.flashup.app`, `FLASHUP_ICLOUD_CONTAINER = iCloud.$(FLASHUP_BUNDLE_ID)`,
   `FLASHUP_DEVELOPMENT_TEAM` empty. The bead permits placeholders; §A12 requires
   `com.<team>.flashup` at release. Nothing else hard-codes an identifier, so B0.5
   changes one file.
3. **Simulator builds run with `CODE_SIGNING_ALLOWED=NO`** because no Apple Developer
   team is attached yet. `ci/build.sh archive` (device/TestFlight path) is written but
   unverifiable until a team exists.
4. **SwiftLint is a host tool, not a vendored dependency** (§0.2 forbids extra SPM
   packages). `ci/lint.sh` skips with a warning when it is missing and fails when
   `STRICT_LINT=1`. It was installed locally with `brew install swiftlint` (0.65.0).
5. **No `Assets.car` is produced yet** — the catalog holds only an empty `AppIcon` and
   `AccentColor`. Expected until real artwork lands.

### Follow-ups (bead candidates, not done here)

- App icon and accent color artwork (release-time asset work, currently unowned; the
  release matrix in `fu-15-release` should claim it).
- ADR on the Swift language mode (5 vs 6) before `fu-04-data-core` writes the Core Data
  stack.
- A GitHub Actions workflow calling `ci/test.sh` — deliberately out of scope for B0.1,
  which only requires the local wrappers.

---

## Demo multi-deck seeding — 2026-07-31

### Built

- `DEMO_DECKS` accepts a comma-separated list of safe deck slugs while retaining the
  existing single-deck `DEMO_DECK` contract.
- The demo loader now combines several separately parsed CSV files into distinct decks,
  then seeds one shared, deterministic FSRS history so new, due, and longer-interval cards
  coexist across subjects.

### Verification

- `swift test --filter DemoMode`: 18 tests passed, including the new multi-deck and varied
  FSRS-state coverage.
- iPhone 17 simulator: launched with complete local study exports as two decks — Istologia
  (56 cards) and Biochimica (19 cards). The Today screen showed 30 due and 15 new cards.
- `xcodebuild ... build`: `** BUILD SUCCEEDED **`.

### Data handling

The source study exports and generated CSV files were copied only into the local simulator
container. They are not repository assets and were not added to version control.

---

## Deck detail schedule forecast — 2026-07-31

### Built

- Each deck detail now begins with a **Da fare** section: **Oggi** retains the current
  review/new presentation, while scheduled review cards are grouped into **Domani** and
  **Questa settimana**.
- **Più avanti** appears only when cards are scheduled after the seven-day window, so no
  card silently disappears from the deck total. **In pausa** appears only when the deck has
  suspended cards and remains outside every study bucket.
- The forecast uses existing FSRS due dates; it does not place future cards in today’s study
  queue. Copy is localized in English and Italian and the summary is exposed as one combined
  accessibility element per row.

### Verification

- `swift test`: 114 tests in 10 suites passed, including forecast boundary and suspension
  coverage.
- `xcodebuild ... build`: `** BUILD SUCCEEDED **` for the iPhone 17 simulator.
- Reinstalled and launched the local Istologia and Biochimica demo decks in the simulator.

---

## Today brand header — 2026-07-31

### Built

- The Today screen has a persistent top-left FlashApp brand mark using the shipped app-icon
  artwork, with the screen title directly below it and Statistics retained at the right.
- Added a dedicated image-set for in-app rendering; an `AppIcon.appiconset` cannot be loaded
  through SwiftUI's `Image` API as a named asset.

### Verification

- `xcodebuild ... build`: `** BUILD SUCCEEDED **` for the iPhone 17 simulator.
- Visually checked the installed Italian demo: the icon and “FlashApp” label render in the
  top-left header, and the Statistics control remains reachable on the right.

---

## FlashApp signature canvas — 2026-07-31

### Built

- The Today wordmark is now the larger serif **FlashApp**, without a space.
- `screenCanvas()` carries a low-contrast cropped monogram signature at its lower edge. It
  derives its linework from the existing logo asset and is decorative only, so it never
  competes with controls or becomes part of VoiceOver navigation.

### Verification

- `xcodebuild ... build`: `** BUILD SUCCEEDED **` for the iPhone 17 simulator.
- Visually checked in the installed Italian demo with Istologia and Biochimica loaded.

---

## Signature prominence for launch framing — 2026-07-31

### Built

- Enlarged the canvas monogram, increased its contrast slightly, and lifted it into the
  middle of the screen so it reads within the upper two-thirds of launch footage.

### Verification

- `xcodebuild ... build`: `** BUILD SUCCEEDED **` for the iPhone 17 simulator.
- Visually checked in the installed Italian demo.

---

## FlashApp monogram lockup — 2026-07-31

### Built

- Increased the in-header app monogram to 34 points, approximately 20% taller than the
  `FlashApp` wordmark's cap height, while preserving its centred baseline relationship.

### Verification

- `xcodebuild ... build`: `** BUILD SUCCEEDED **` for the iPhone 17 simulator.
- Visually checked in the installed Italian demo.

---

## Shared FlashApp root header — 2026-07-31

### Built

- Replaced the Today-only lockup with one shared `AppBrandHeader` used by Oggi, Libreria,
  Gruppi and Impostazioni.
- Increased the monogram to a Dynamic-Type-scaled 42-point frame so its visible linework
  clearly overshoots the `FlashApp` cap height above and below.
- Library's add action now occupies the same trailing header position as Today statistics.

### Verification

- `xcodebuild ... build`: `** BUILD SUCCEEDED **` for the iPhone 17 simulator.
- `ShellUITests.testBrandHeaderAppearsOnEveryTab`: passed, exercising all four root tabs.
- Visually checked the installed Italian demo on the Groups tab with the shared header and
  enlarged lockup rendered above the real content.

---

## B4.3 — Import prompt content filter — 2026-07-31

### Built

- Extended the localized ChatGPT CSV prompt with a selection rule that creates cards only
  from study-worthy subject matter.
- The prompt now explicitly skips course-organizational content such as instructors, exam
  format, credits, schedules, classrooms, contacts, administrative instructions and general
  announcements.
- Preserved the intended clipboard journey: the assistant returns CSV text in one code block
  with no attached file.

### Verification

- `jq empty App/Resources/Localizable.xcstrings`: passed.
- `git diff --check`: passed.
- `xcodebuild ... build`: `** BUILD SUCCEEDED **` for the iPhone 17 simulator.
- `ImportUITests.testImportOffersACopyablePromptForChatGPT`: passed, covering the exact CSV
  header, organizational-content exclusion, code-block response and no-attachment contract.
