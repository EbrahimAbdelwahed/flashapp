# Flash Up — Worklog

One entry per completed batch bead (spec §0.4.7): bead ID, what was built, deviations
with justification, follow-ups discovered.

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
