# Flash Up — Worklog

One entry per completed batch bead (spec §0.4.7): bead ID, what was built, deviations
with justification, follow-ups discovered.

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
