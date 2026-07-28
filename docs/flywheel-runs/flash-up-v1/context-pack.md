# Context Pack: Flash Up v1 implementation

Date: 2026-07-28
Run ID: `flash-up-v1`
Project: `/Users/ebrahimabdelwahed/Desktop/Dev/flashapp`

## Purpose

This pack gives the orchestrator and future workers enough repository context to create a precise spec and scoped task graph.

## Files Read

- `flash-up-implementation-spec.md`

## `flash-up-implementation-spec.md`

```text
# Flash Up — Implementation Specification v1.0

Status: implementation-ready specification derived from the approved architecture brief
(`flash-up-architecture-brief.md`). The brief is the product source of truth; this document
is the engineering source of truth. Where the two conflict, the brief wins and the spec
must be amended — never silently diverged from.

Audience: coding agents implementing the project as discrete work items ("beads").
Every bead in Part B has explicit inputs, tasks, deliverables, stop conditions, and
out-of-scope declarations. **Agents must stop at the stop conditions.** Anything not
listed in a bead's tasks is out of scope for that bead, even if it looks adjacent.

---

## 0. Global rules for all beads

These apply to every bead. A bead is not DONE if any global rule is violated.

### 0.1 Non-negotiable product constraints (from the brief)

1. Paid app, €1.99, no IAP/subscription/trial/ads. Nothing in the codebase may
   reference StoreKit purchases, entitlement gating, or paywalls.
2. No third-party analytics, tracking, crash, or advertising SDK. Apple-native
   diagnostics only (MetricKit/Xcode Organizer — no code integration required at launch).
3. Card content never leaves the device except via the user's own iCloud (CloudKit)
   and user-initiated exports. No search server, no telemetry containing content.
4. No proprietary accounts or authentication. iCloud/Apple Account state only.
5. iOS/iPadOS 17 minimum, SwiftUI, iPhone + iPad + "iPad app on Apple Silicon Mac".
   No macOS/Catalyst target.
6. Italian + English localization from the first release.
7. Local-first: the app is fully usable without a network; iCloud unavailability is a
   visible but non-blocking state.
8. Never delete the user's store to recover from a migration or sync failure.

### 0.2 Technical conventions

- **Language/tooling:** Swift 5.10+, Xcode 16.x, SwiftUI + Observation framework
  (`@Observable`), `NavigationStack`/`NavigationSplitView`, Swift Concurrency
  (`async/await`, actors). No Combine except where Core Data/CloudKit notifications
  require it internally.
- **Persistence:** Core Data with `NSPersistentCloudKitContainer`. SwiftData is
  forbidden (brief §Persistence).
- **Allowed third-party dependencies (SPM), exhaustive list:**
  - `open-spaced-repetition/swift-fsrs` (FSRS engine — required by the brief)
  - `apple/swift-markdown` (Markdown AST parsing for the editor/renderer)
  - Nothing else. CSV parsing, backup encoding, cloze parsing are implemented in-repo.
- **Localization:** String Catalogs (`Localizable.xcstrings`), `it` + `en`. Every
  user-facing string added in any bead must be added to the catalog with both
  localizations in the same bead. English is the development language.
- **Accessibility:** every new screen ships with accessibility labels/traits, Dynamic
  Type support (no fixed font sizes; use text styles), and respects
  `accessibilityReduceMotion`. This is per-bead, not a final pass only (a final audit
  bead exists in addition).
- **Errors:** typed errors per subsystem (`ImportError`, `SyncError`, `BackupError`,
  `MigrationError`). User-facing messages are localized, actionable, and never expose
  raw CloudKit/Core Data errors.
- **Logging:** `os.Logger` with subsystem `com.<team>.flashup`, categories per
  subsystem. Log content metadata only (counts, UUIDs, durations) — **never card text**.
- **Dates:** all persisted timestamps are UTC `Date`; all calendar computations
  (streak, "today" limits, daily rollover) use `Calendar.current` at read time.
- **IDs:** all domain identity is app-level `UUID` (attribute `uuid`), never
  `NSManagedObjectID` and never CloudKit record names directly.
- **Testing:** Swift Testing (`import Testing`) for new unit tests; XCTest for UI
  tests. Domain logic must be testable without a simulator (pure package targets).
- **Code style:** SwiftLint with a checked-in `.swiftlint.yml` (default rules +
  `force_unwrapping: error` in non-test code). CI fails on lint errors.

### 0.3 Repository and project structure

```
FlashUp/
├── FlashUp.xcodeproj
├── App/                          # App target (SwiftUI, features, DI)
│   ├── FlashUpApp.swift          # @main, scene setup, deep-link/share handling
│   ├── AppEnvironment.swift      # Composition root: builds services, injects via Environment
│   ├── Features/
│   │   ├── Today/
│   │   ├── Library/
│   │   ├── Study/
│   │   ├── Groups/
│   │   ├── Settings/
│   │   ├── Onboarding/
│   │   ├── Import/
│   │   └── Shared/               # Reusable views (MarkdownView, SyncBadge, EmptyState…)
│   └── Resources/
│       ├── Localizable.xcstrings
│       ├── DemoDeck/demo_deck_en.csv, demo_deck_it.csv
│       └── Assets.xcassets
├── Packages/
│   └── FlashUpKit/               # Local SPM package
│       ├── Sources/
│       │   ├── FlashUpDomain/    # Pure logic: cloze, CSV, FSRS wrapper, queue,
│       │   │                     #   metrics, dedup, backup codec. NO UIKit/SwiftUI,
│       │   │                     #   NO Core Data imports.
│       │   └── FlashUpData/      # Core Data stack, model, repositories, sync,
│       │                         #   sharing, purge, migration. Depends on Domain.
│       └── Tests/
│           ├── FlashUpDomainTests/
│           └── FlashUpDataTests/ # In-memory + on-disk store tests
├── FlashUpUITests/               # XCUITest target
├── .swiftlint.yml
├── ci/                           # CI scripts (xcodebuild wrappers)
└── docs/
    ├── flash-up-architecture-brief.md   # copied verbatim, read-only
    └── decisions/                       # ADRs written by spike beads
```

Dependency direction (enforced by package structure):
`App → FlashUpData → FlashUpDomain → (swift-fsrs, Foundation)`.
`FlashUpDomain` must compile for macOS too, so its tests run without a simulator.

### 0.4 Definition of Done (applies to every bead)

A bead is DONE only when all of the following hold:

1. All tasks listed in the bead are complete; nothing outside them was changed except
   trivially necessary wiring.
2. New/changed logic has tests as specified in the bead; the full test suite passes
   (`ci/test.sh`).
3. SwiftLint passes with zero errors.
4. All new user-facing strings exist in `en` and `it`.
5. The app builds and boots on iPhone and iPad simulators (iOS 17) with no runtime
   warnings introduced by the bead (Core Data model warnings, constraint warnings).
6. The bead's stop conditions are met and its "Out of scope" list was respected.
7. A short completion note is appended to `docs/decisions/worklog.md`: bead ID, what
   was built, deviations (if any, with justification), follow-ups discovered.

---

# PART A — Architecture definition

Part A defines the target architecture. Beads in Part B reference these sections; do
not re-litigate decisions made here inside a bead. If an implementation discovery
genuinely invalidates a decision (e.g., a CloudKit behavior differs), STOP the bead and
record the finding in `docs/decisions/` for human review — do not improvise a new
architecture mid-bead.

## A1. Persistence topology

### A1.1 Stores and databases

One `NSManagedObjectModel`, one `NSPersistentCloudKitContainer`, **two SQLite stores**:

| Store file        | CloudKit database scope | Contents |
|-------------------|------------------------|----------|
| `Private.sqlite`  | `.private`             | Personal content (decks/notes/cards/tags), content the user owns and shares (groups they created live in a shared **zone** of the private DB), and **all private study data** (Schedule, ReviewLog, ImportBatch, Revision-pruning bookkeeping). |
| `Shared.sqlite`   | `.shared`              | Content shared **with** the user by other owners (groups they joined): mirrored CDGroup/CDDeck/CDNote/CDCard/CDTag/CDRevision records. |

Configuration:

- Both store descriptions enable:
  - `NSPersistentHistoryTrackingKey = true`
  - `NSPersistentStoreRemoteChangeNotificationPostOptionKey = true`
- `cloudKitContainerOptions.databaseScope = .private` / `.shared` respectively, same
  CloudKit container identifier `iCloud.<bundle-id>`.
- `viewContext.automaticallyMergesChangesFromParent = true`,
  `mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy`.
- Background work uses `container.newBackgroundContext()` per operation; never write on
  the view context except trivial UI-driven single-object edits.
- If iCloud is unavailable (no account, iCloud Drive off, restricted), the container is
  built **without** `cloudKitContainerOptions` (pure local mode) and a
  `SyncAvailability` state is exposed (see A4.4). Store files are identical in both
  modes so toggling iCloud later re-uses the same data.

### A1.2 CloudKit-compatible modeling rules (mandatory)

Because both stores are CloudKit-mirrored, the Core Data model MUST follow:

1. No uniqueness constraints (CloudKit forbids them). App-level uniqueness on `uuid`
   is enforced by repositories + a dedup pass (A4.3).
2. Every attribute is optional **or** has a default value.
3. Every relationship is optional and has an inverse.
4. No ordered relationships. Ordering uses explicit sortable attributes.
5. No `Deny` delete rules.
6. Entities never rely on `NSManagedObjectID` for identity across devices.

### A1.3 Cross-store reference rule (critical)

Core Data relationships cannot cross stores, and `NSPersistentCloudKitContainer` moves
an object's *entire relationship graph* into a shared zone when its root is shared.
Therefore:

- **Content entities** (CDGroup, CDDeck, CDNote, CDCard, CDTag, CDRevision) form a
  connected relationship graph and always live together in the same store/zone.
- **Private study entities** (CDSchedule, CDReviewLog, CDImportBatch) have **no Core
  Data relationships at all** — not to content, not to each other. They reference
  content via plain UUID attributes (`cardUUID`, `noteUUID`, `deckUUID`). This
  guarantees they can never be dragged into a shared zone and never sync to other
  participants.
- Study entities are always created with `context.assign(object, to: privateStore)`.
  A repository-level assertion enforces this in DEBUG.

Consequence embraced by design: joins between study data and content are done in
memory by UUID (dictionary lookups). Expected scale (≤ tens of thousands of cards)
makes this trivially fast; fetches use `IN %@` predicates on UUID arrays when needed.

### A1.4 Zone/sharing layout

- Personal content: default zone of the private database (managed by the container).
- A collaborative group: the container places the `CDGroup` object graph (group → decks
  → notes → cards/tags/revisions) into a dedicated shared zone in the **owner's private
  database** when the group is shared via
  `NSPersistentCloudKitContainer.share(_:to:)`. One `CKShare` per group, rooted at the
  `CDGroup` record.
- Participants receive the zone in their **shared database**, mirrored into
  `Shared.sqlite`.
- Tags used by shared notes are group-scoped copies (see A3.6) so the tag graph never
  links a shared note to a personal tag object.

## A2. Core Data model v1 (`FlashUp.xcdatamodeld`, model version `V1`)

All entities include this base attribute set unless noted:

| Attribute   | Type   | Notes |
|-------------|--------|-------|
| `uuid`      | UUID   | default = new UUID at insert (set in `awakeFromInsert`) |
| `createdAt` | Date   | set in `awakeFromInsert` |
| `updatedAt` | Date   | set in `willSave` when changed (guard against loops) |
| `deletedAt` | Date?  | soft-delete marker; content entities only |

### CDDeck
- `name: String` (default `""`)
- `isDemo: Bool` (default `false`) — demo deck flag (excluded from backups)
- Relationships: `notes: [CDNote]` (cascade), `group: CDGroup?` (nullify),
  inverse on both.

### CDNote
- `type: String` — `"basic" | "reversed" | "cloze"` (enum `NoteType` in Domain)
- `front: String` (default `""`) — authored source (Markdown/plain). For cloze notes,
  contains the cloze source.
- `back: String` (default `""`)
- `contentHash: String` (default `""`) — dedup fingerprint, see A3.5
- Relationships: `deck: CDDeck?` (nullify), `cards: [CDCard]` (cascade),
  `tags: [CDTag]` (many-to-many, nullify), `revisions: [CDRevision]` (cascade).

### CDCard
- `templateKey: String` — stable generation identity: `"forward"`, `"reverse"`, or
  `"cloze:<n>"` where `<n>` is the cloze group number. **Card identity = note.uuid +
  templateKey**, and `uuid` is deterministic-stable: created once, never regenerated
  for the same (note, templateKey) pair (A3.2).
- `deletedAt` here marks *orphaned* cards (cloze group removed) pending trash rules.
- Relationship: `note: CDNote?` (nullify).

### CDTag
- `name: String` — user-authored display form
- `normalizedName: String` — see A3.6
- Relationship: `notes: [CDNote]` many-to-many.

### CDGroup
- `name: String`
- Relationship: `decks: [CDDeck]` (nullify).
- Participant/role data is NOT modeled in Core Data; it is read live from the group's
  `CKShare` participants (A5.3). This keeps the permission model extensible without
  schema changes (brief: "design the permission model so granular roles can be added
  later").

### CDRevision  (shared content version history, A5.5)
- `entityKind: String` — `"note"` (v1 only writes note revisions; deck rename revisions
  use `entityKind = "deck"` with `front` = old name)
- `targetUUID: UUID` — uuid of the revised note/deck (attribute, plus relationship
  below for zone co-location)
- `authorDisplayName: String` — captured client-side at save time
- `timestamp: Date`
- `type/front/back: String` — full snapshot of the note before the edit
- Relationship: `note: CDNote?` (cascade from note) — required so revisions live in the
  same shared zone as their note.

### CDSchedule  (private store only, relationship-free)
- `cardUUID: UUID` (indexed)
- `deckUUID: UUID` (indexed, denormalized for queue building)
- `stateRaw: Int16` — FSRS state (new/learning/review/relearning) as defined by
  swift-fsrs
- `stability: Double`, `difficulty: Double`
- `dueAt: Date`, `lastReviewedAt: Date?`
- `reps: Int32`, `lapses: Int32`
- `suspendedAt: Date?` — suspension flag (brief: suspend a card)
- Uniqueness (app-level): one CDSchedule per `cardUUID`; the dedup pass (A4.3) merges
  duplicates by replaying logs (A6.4).

### CDReviewLog  (private store only, relationship-free, append-only)
- `uuid: UUID` — merge identity across devices
- `cardUUID: UUID` (indexed), `deckUUID: UUID` (indexed)
- `reviewedAt: Date`, `durationMs: Int32`
- `gradeRaw: Int16` — Again/Hard/Good/Easy
- Pre-transition snapshot (audit + deterministic replay): `prevStateRaw: Int16`,
  `prevStability: Double`, `prevDifficulty: Double`, `prevDueAt: Date?`,
  `scheduledDays: Int32`, `elapsedDays: Int32`
- `revokedAt: Date?` — set by "undo last response" instead of deleting (append-only +
  multi-device safe; replay skips revoked logs).

### CDImportBatch  (private store only, relationship-free)
- `sourceName: String` — file name / "Share Sheet"
- `importedAt: Date`
- `destinationDeckUUID: UUID`
- `destinationWasNewDeck: Bool`
- `createdNoteUUIDsJSON: String` — JSON `[UUID]`
- `rejectedRowsJSON: String` — JSON `[{row:Int, reason:String, raw:String}]` (raw
  stays on-device; never exported in diagnostics)
- `duplicateRowsJSON: String` — JSON `[{row:Int, matchedNoteUUID:UUID, imported:Bool}]`
- `undoneAt: Date?`

### Model hygiene
- Model is versioned from day one: `V1` is the current version; the `.xcdatamodeld`
  is committed with an explicit current-version marker. All future changes create
  `V2`, additive-only where possible (A7).

## A3. Domain rules (pure logic, `FlashUpDomain`)

### A3.1 Note types and card generation

`CardGenerator.generate(note) -> [CardTemplate]` where `CardTemplate = (templateKey,
frontRendered-source, backRendered-source)`:

| Note type  | Cards produced (templateKey) | Front shown | Back shown |
|------------|------------------------------|-------------|------------|
| `basic`    | `forward`                    | `front`     | `back` |
| `reversed` | `forward`, `reverse`         | `front` / `back` | `back` / `front` |
| `cloze`    | `cloze:<n>` for each distinct group `n` found in `front` | `front` with group `n` masked as `[…]` (hint shown if present), other groups revealed | full `front` with all deletions revealed + `back` as extra explanation if non-empty |

Card reconciliation on note edit (`CardReconciler.sync(note)`):
1. Compute desired templateKeys from the current note content/type.
2. Keep existing CDCards whose templateKey is still desired (uuid unchanged → private
   progress preserved, including for collaborators; brief §Card).
3. Create CDCards for new templateKeys.
4. For no-longer-desired templateKeys: if a schedule/logs exist anywhere is unknowable
   locally for collaborators, so uniformly **soft-delete** the card (`deletedAt = now`);
   the 30-day purge (A8) removes it and each participant's purge removes their own
   orphaned Schedule/ReviewLogs (matched by cardUUID) after the same window.
5. Reconciliation runs on every note save and after remote note changes (A4.2).

### A3.2 Stable card identity

- `CDCard.uuid` is generated once per (noteUUID, templateKey) and persisted. Editing
  note text never changes card uuids for surviving templateKeys. Renumbering cloze
  groups DOES change templateKeys and therefore produces new cards — the editor warns
  when an edit removes existing groups (Bead B5.4).
- This is the contract that lets collaborators keep private FSRS progress across
  shared-content edits.

### A3.3 Note type conversion

`NoteTypeConverter.convert(note, to: newType, hasStudyHistory: Bool)`:
- `hasStudyHistory` = any non-revoked local ReviewLog exists for any of the note's card
  uuids **or** the note lives in a group (collaborators may have history we cannot see).
- If `false`: convert in place (change `type`, reconcile cards; unscheduled cards may
  be freely deleted, not soft-deleted).
- If `true`: create a duplicate note of the new type in the same deck (new uuid, copied
  front/back/tags, `" (convertita)"`/`" (converted)"` suffix on nothing — no name field;
  duplicate is distinguishable by type badge), leave the original untouched. UI offers
  to trash the original explicitly (brief §Note types).

### A3.4 Cloze syntax (Anki-compatible)

Grammar parsed by `ClozeParser` (hand-written scanner, no regex backtracking pitfalls):

```
deletion := "{{c" INT "::" text ( "::" hint )? "}}"
```
- `INT` ≥ 1; groups may repeat (`c1` twice → both masked on card `cloze:1`).
- Nested braces inside `text` are taken literally up to the first `}}` (Anki behavior).
- Malformed deletions are left as literal text and reported as warnings
  (`ClozeParseIssue`) surfaced in the editor and import preview.
- `ClozeParser.render(source, maskGroup:Int?) -> String` produces study-ready text
  (masked group → `[...]` or `[hint]`).

### A3.5 Duplicate detection

`ContentFingerprint.hash(type, front, back) -> String`:
- Normalize each field: Unicode NFC, trim, collapse internal whitespace runs to a
  single space, casefold (locale-independent lowercase).
- `contentHash = SHA256(type + "\u{1F}" + normFront + "\u{1F}" + normBack)` hex string.
- Stored on CDNote at every save. Import dedup compares candidate hashes against
  non-trashed notes **of the destination deck only** (brief §Import).

### A3.6 Tags

- `TagNormalizer.normalize(name)`: NFC, trim, collapse whitespace, casefold →
  `normalizedName`. Display `name` keeps the first-seen authored casing.
- Repository `findOrCreateTag(name, scope)` where scope = personal store or a specific
  group: tags are looked up by `normalizedName` **within the scope's object graph**.
  A shared note only ever links to CDTag objects living in its own group's zone;
  personal notes link to personal tags. Moving a deck between scopes re-maps tags via
  findOrCreate in the destination scope (A5.6).
- CloudKit duplicate tags (two devices create `anatomia` offline) are merged by the
  dedup pass (A4.3): keep lowest-uu

[truncated]
```

## Search Results

### `^(### B|## Phase|# PART)`

exit_code: `0`

```text
cs/flywheel-runs/flash-up-v1/intake.md:1090:### B3.5 — MetricsService
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1099:## Phase 4 — Import/export/backup
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1101:### B4.1 — CSVParser
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1108:### B4.2 — ImportPlanner + ImportCommitter + undo
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1118:### B4.3 — Import UI + entry points + ChatGPT prompt
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1129:### B4.4 — Deck CSV export
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1135:### B4.5 — Backup export/restore
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1149:## Phase 5 — UI shell, Library, editor
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1151:### B5.1 — App shell, theming, navigation, sync badge
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1163:### B5.2 — Today
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1171:### B5.3 — Library: decks and notes
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1182:### B5.4 — Note editor
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1200:### B5.5 — Search & filters
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1207:### B5.6 — Trash UI
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1214:### B5.7 — Statistics polish
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1222:## Phase 6 — Study UI
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1224:### B6.1 — StudySessionView
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1234:### B6.2 — Completion + resume
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1244:## Phase 7 — Groups and sharing
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1246:### B7.1 — ShareManager + create group + invite
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1257:### B7.2 — Invitation acceptance
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1266:### B7.3 — Group detail: participants, leave, remove
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1275:### B7.4 — DeckMover + move/copy UI
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1285:### B7.5 — Revision history
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1294:### B7.6 — Group deletion + ownership UX copy
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1304:## Phase 8 — Settings, onboarding, system surfaces
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1306:### B8.1 — Settings
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1317:### B8.2 — Onboarding + demo deck
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1327:### B8.3 — Contextual tutorials + Help
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1335:### B8.4 — Reminders
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1344:### B8.5 — Delete all my data
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1353:### B8.6 — Support + review prompt
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1363:## Phase 9 — Localization, accessibility, release QA
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1365:### B9.1 — Localization completeness
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1373:### B9.2 — Accessibility & appearance audit
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/docs/flywheel-runs/flash-up-v1/intake.md:1381:### B9.3 — Release QA, TestFlight, App Store package
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/agent-flywheel/docs/flywheel-runner.md:278:## Phase Semantics
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:130:# PART A — Architecture definition
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:825:# PART B — Bead plan
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:850:## Phase 0 — Foundations and verification spikes
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:852:### B0.1 — Project scaffold
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:872:### B0.2 — Spike: CloudKit store topology proof (ADR)
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:888:### B0.3 — Spike: sharing + deck move proof (ADR)
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:905:### B0.4 — Spike: swift-fsrs API pinning (ADR)
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:919:### B0.5 — Manual checklist: App Store Connect setup (human task)
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:928:## Phase 1 — Data layer
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:930:### B1.1 — Core Data model V1 + PersistenceController
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:946:### B1.2 — Repositories and store affinity
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:962:### B1.3 — TrashService + PurgeService
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:971:### B1.4 — SyncMonitor + RemoteChangeProcessor skeleton
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:989:## Phase 2 — Domain logic (pure, no UI)
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:991:### B2.1 — ClozeParser
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1000:### B2.2 — CardGenerator + CardReconciler
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1014:### B2.3 — NoteTypeConverter
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1023:### B2.4 — TagNormalizer + tag dedup completion
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1030:### B2.5 — ContentFingerprint
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1039:## Phase 3 — FSRS and study engine
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1041:### B3.1 — Schedule persistence + StudyEngine.answer
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1050:### B3.2 — ScheduleReplayer + multi-device merge + schedule dedup
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1062:### B3.3 — QueueBuilder + limits
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1071:### B3.4 — Session engine (resume, undo, suspend, reset)
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1081:### B3.5 — MetricsService
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1090:## Phase 4 — Import/export/backup
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1092:### B4.1 — CSVParser
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1099:### B4.2 — ImportPlanner + ImportCommitter + undo
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1109:### B4.3 — Import UI + entry points + ChatGPT prompt
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1120:### B4.4 — Deck CSV export
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1126:### B4.5 — Backup export/restore
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1140:## Phase 5 — UI shell, Library, editor
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1142:### B5.1 — App shell, theming, navigation, sync badge
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1154:### B5.2 — Today
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1162:### B5.3 — Library: decks and notes
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1173:### B5.4 — Note editor
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1191:### B5.5 — Search & filters
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1198:### B5.6 — Trash UI
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1205:### B5.7 — Statistics polish
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1213:## Phase 6 — Study UI
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1215:### B6.1 — StudySessionView
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1225:### B6.2 — Completion + resume
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1235:## Phase 7 — Groups and sharing
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1237:### B7.1 — ShareManager + create group + invite
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1248:### B7.2 — Invitation acceptance
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1257:### B7.3 — Group detail: participants, leave, remove
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1266:### B7.4 — DeckMover + move/copy UI
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1276:### B7.5 — Revision history
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1285:### B7.6 — Group deletion + ownership UX copy
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1295:## Phase 8 — Settings, onboarding, system surfaces
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1297:### B8.1 — Settings
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1308:### B8.2 — Onboarding + demo deck
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1318:### B8.3 — Contextual tutorials + Help
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1326:### B8.4 — Reminders
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1335:### B8.5 — Delete all my data
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1344:### B8.6 — Support + review prompt
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1354:## Phase 9 — Localization, accessibility, release QA
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1356:### B9.1 — Localization completeness
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1364:### B9.2 — Accessibility & appearance audit
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/flash-up-implementation-spec.md:1372:### B9.3 — Release QA, TestFlight, App Store package
/Users/ebrahimabdelwahed/Desktop/Dev/flashapp/agent-flywheel/docs/internal-flywheel-architecture.md:638:### Bead
```


## Orchestrator Notes

- Convert rough requirements into explicit acceptance criteria before implementation.
- Keep generated worker scopes narrow and file-bounded.
- Use `br`/`bv` as durable task graph once beads are approved.
