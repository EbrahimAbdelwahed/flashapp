# FlashApp — Implementation Specification v1.0

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
  dedup pass (A4.3): keep lowest-uuid tag, re-link notes, delete the other.

### A3.7 Markdown

- Storage: raw source string (brief: store source, not rendered output).
- Rendering: `swift-markdown` AST → `MarkdownView` (SwiftUI) supporting: paragraphs,
  bold, italic, inline code, code blocks, ordered/unordered lists, headings (h1–h3
  rendered as bold sizes), links (tappable). Anything else renders as plain text of its
  literal content. No HTML pass-through (render as text).
- The same renderer is used in editor preview and study cards. It must honor Dynamic
  Type and both appearances.

## A4. Sync engine (`FlashUpData`)

### A4.1 Components

- `PersistenceController` — builds the container per A1; exposes `viewContext`,
  `newBackgroundContext()`, store references (`privateStore`, `sharedStore`), and
  local-only mode.
- `SyncMonitor` (`@Observable`) — consumes
  `NSPersistentCloudKitContainer.eventChangedNotification` and `CKAccountChanged`;
  publishes `SyncAvailability` + `SyncActivity` (A4.4) and a `lastError`.
- `RemoteChangeProcessor` — consumes remote-change notifications, drains persistent
  history since the last processed token (stored in metadata), and triggers:
  card reconciliation for changed notes (A3.1), schedule replay for merged review logs
  (A6.4), dedup pass (A4.3), and revision pruning (A8).
- `ShareManager` — wraps `share(_:to:)`, `fetchShares(matching:)`,
  `persistUpdatedShare`, `purgeObjectsAndRecordsInZone`, participant listing, and
  `acceptShareInvitations` handling (A5).

### A4.2 Remote change pipeline

On remote change notification (debounced 2s):
1. Fetch persistent-history transactions after the stored token for that store.
2. Collect changed object UUIDs by entity.
3. For changed CDNotes → run `CardReconciler` in a background context.
4. For inserted CDReviewLogs (from the user's other devices) → group by `cardUUID`,
   run `ScheduleReplayer` (A6.4).
5. Run `Deduplicator` for CDTag and CDSchedule (A4.3).
6. Persist the new history token; delete history older than 7 days.

### A4.3 Deduplication (CloudKit has no unique constraints)

Deterministic rule "lowest uuid wins" so every device converges independently:
- CDTag: same `normalizedName` within the same graph scope → winner keeps links from
  losers' notes; losers hard-deleted.
- CDSchedule: same `cardUUID` → winner = lowest uuid; before deleting losers, run
  replay (A6.4) so the winner reflects the union of logs.
- CDGroup/CDDeck/CDNote/CDCard duplicates are not expected (single insertion point);
  if detected, log at fault level and do not auto-delete (human review path).

### A4.4 Sync status UX contract

`SyncAvailability`: `.available`, `.noAccount`, `.restricted`, `.temporarilyUnavailable`,
`.localOnly` (user disabled or capability missing).
`SyncActivity`: `.idle`, `.syncing`, `.error(SyncError)`.

- Presentation is *subtle*: a small status glyph in Settings row "iCloud Sync" and a
  passive banner on Library only for `.noAccount`/`.error` states, with a "Retry"
  action (re-initializes container event processing / calls a no-op save to nudge an
  export) and "Open Settings" guidance. Study and editing are never blocked (brief
  §Local-first).

## A5. Collaborative groups (CloudKit sharing)

### A5.1 Group lifecycle (owner)

1. Create `CDGroup` in the private store (personal graph).
2. Immediately call `ShareManager.createShare(group)` →
   `container.share([group], to: nil)` on a background context; set
   `share[CKShare.SystemFieldKey.title] = group.name`, `publicPermission = .none`.
3. Persist share, obtain `share.url` → present via `ShareLink`/`UICloudSharingController`
   equivalent flow (SwiftUI `CloudSharingView` wrapper) or copy-link.
4. Invited members default to read-write (`.readWrite`) = "editors" (brief).

### A5.2 Invitation acceptance (participant)

- `FlashUpApp` implements `onOpenURL` + `userDidAcceptCloudKitShareWith` via
  `UIApplicationDelegateAdaptor`: call
  `container.acceptShareInvitations(from: [metadata], into: sharedStore)`.
- After acceptance, the group's zone mirrors into `Shared.sqlite`; Groups tab shows it
  once the CDGroup arrives (show a "joining…" placeholder keyed by share metadata until
  then).

### A5.3 Participants, roles, leaving, removal

- Participant list = `share.participants` (name via `participant.userIdentity`),
  role = owner vs editor derived from `participant.role`.
- Remove participant (owner only): mutate share participants, save via
  `persistUpdatedShare`.
- Leave group (participant): `container.purgeObjectsAndRecordsInZone(zoneID, in: sharedStore)`
  after the pre-leave flow (A5.7). Purge removes mirrored content only; the user's
  CDSchedules/CDReviewLogs (private store) survive untouched → they ARE the "unlinked
  personal archive" required by the brief. No extra archival entity is needed; the
  backup export includes them regardless.
- Ownership transfer: NOT offered (brief permits refusing unless verified). UI copy
  must explain the creator remains technical owner.

### A5.4 Group deletion (owner)

Flow: warning sheet ("participants will lose access") → offer "Copy shared decks to
my personal library" (deep copy per A5.6 into personal space, owner-side) → delete
CDGroup (cascade decks/notes) → container tears down the zone/share. Participants'
mirrors disappear; their private study data survives locally as archive.

### A5.5 Version history (30 days)

- Before saving an edit to a shared note (deck rename included), `RevisionRecorder`
  snapshots the pre-edit state into CDRevision (author = current user's
  `CKCurrentUserDefaultName` resolved display name or device owner name fallback;
  timestamp = now). Throttle: at most one revision per note per 5 minutes of
  continuous editing by the same author.
- Personal (non-group) notes do NOT record revisions in v1 (brief scopes history to
  shared content).
- Restore: authorized member (any editor) picks a revision → current state is first
  snapshotted as a new revision, then note fields are overwritten from the chosen
  revision; card reconciliation runs.
- Pruning: purge job (A8) deletes revisions older than 30 days.

### A5.6 Moving a deck between personal space and a group

CloudKit cannot move records across zones/databases, so "move" = deep copy preserving
`uuid`s + delete source. `DeckMover.move(deck, to destination)`:

1. Validate: deck not trashed; destination ≠ source scope.
2. In one background-context transaction per store:
   a. Create CDDeck/CDNote/CDCard copies in the destination graph **with identical
      `uuid`, `templateKey`, `contentHash`, timestamps** (createdAt preserved,
      updatedAt = now).
   b. Re-map tags via `findOrCreateTag` in destination scope (A3.6).
   c. CDRevisions are NOT copied when moving personal → group (history starts at
      share time); copied (last 30 days) when group → personal? **No** — brief scopes
      history to shared content: on group → personal move, revisions are dropped.
3. Hard-delete the source graph (not soft-delete — this is a move, and uuid collision
   with the copy must not linger; ImportBatch undo of a moved deck resolves by uuid in
   the new location).
4. Private progress: untouched. CDSchedule/CDReviewLog reference `cardUUID`s that are
   preserved, so study history flows across the move automatically. This satisfies
   brief §Deck ("can move between personal space and a group after import") and
   verification task 4.
5. Failure handling: step order is copy-first, delete-after-successful-save. If the
   deletion save fails, a reconciliation on next launch detects duplicate deck uuids
   across stores and deletes the source copy (destination wins).

Participant restriction: participants can move a deck INTO a group (they can write to
the shared zone) and copy a shared deck to personal space ("copy", not move — only the
owner or an editor may remove the shared original; v1 policy: **only the owner** may
move a deck out of a group; editors get "Copy to personal library" instead. This keeps
destructive scope minimal without granular roles).

### A5.7 Pre-leave / pre-delete safeguards

Leaving a group or (owner) deleting it always presents: participant count, what is
lost, and a one-tap "Copy decks to personal library first" performing A5.6-style copies
(without source deletion).

## A6. Spaced repetition (FSRS)

### A6.1 Engine

- `swift-fsrs` package, pinned to an exact version by spike bead B0.4 (which also
  records the API surface in an ADR). Wrapped behind `FSRSService` (protocol in Domain)
  so the app never imports swift-fsrs outside one adapter file.
- Parameters: library default weights; `desiredRetention = 0.90`; no user-facing
  parameter UI (brief). Four grades mapped to swift-fsrs `Rating`.

### A6.2 Scheduling flow

`StudyEngine.answer(card, grade, duration)`:
1. Load or create CDSchedule for `cardUUID` (new card → FSRS "new" state).
2. Compute transition via `FSRSService.next(state, grade, now)`.
3. Append CDReviewLog with pre-transition snapshot (A2) — this is the audit record
   required by the brief.
4. Write new state into CDSchedule (`dueAt`, `stability`, …).
5. All in one background-context save; UI observes via fetch.

### A6.3 Undo, suspend, reset

- Undo (most recent response only, per brief): set `revokedAt` on the latest
  non-revoked log of the session, then replay (A6.4) that card's schedule. Session
  queue re-inserts the card at the front.
- Suspend: `suspendedAt = now` on CDSchedule (card excluded from queues); unsuspend
  clears it.
- Reset scheduling: append a synthetic CDReviewLog? **No** — reset must be auditable
  but is not a review. Policy: hard-delete is forbidden for logs (append-only), so
  reset sets `revokedAt` on ALL logs for the card and deletes/recreates the schedule
  as new. The logs remain for audit (revoked), satisfying append-only.

### A6.4 Deterministic multi-device replay

`ScheduleReplayer.replay(cardUUID)`:
1. Fetch all CDReviewLogs for the card, excluding `revokedAt != nil`.
2. Sort by (`reviewedAt`, `uuid`) — uuid tiebreak makes ordering total and identical
   on every device.
3. Fold from FSRS initial state using `FSRSService.next` at each log's `reviewedAt`.
4. Write the folded state to the (single, deduped) CDSchedule.
Run when: remote logs merge in (A4.2), schedule dedup occurs, undo/reset executes.
This satisfies the brief: logs merge rather than overwrite; state is recomputable from
ordered history.

### A6.5 Queue building and daily limits

`QueueBuilder.build(scope: .deck(uuid) | .allEligible, now, settings)`:
- Eligible cards: not trashed (card or ancestors), schedule not suspended.
- Due list: schedules with `dueAt <= endOfToday`, order `dueAt` ascending; count
  capped by `reviewsPerDay − reviewsDoneToday(deck)` (done = non-revoked logs today
  for review-state cards).
- New list (after due, brief §Study): cards with no schedule, order note `createdAt`
  then `templateKey`; capped by `newPerDay − newIntroducedToday(deck)` (logs today with
  `prevState == new`).
- Limits: global defaults 20 new / 200 reviews, user-adjustable in Settings
  (`StudySettings` in UserDefaults; per-deck overrides are deferred — do not build
  them). `.allEligible` applies limits per deck, then interleaves decks by dueAt.

### A6.6 Session persistence

`SessionState` (Codable JSON at `Application Support/session-state.json`, device-local,
never synced): scope, ordered remaining card uuids, answered count, start time,
accumulated duration. Saved after every answer; restored on app launch if < 24h old
and offered as "Resume session". Cleared on completion/abandon.

### A6.7 Metrics

`MetricsService` (computed from local CDReviewLogs + CDSchedules, cached per day):
- Studied today: count of non-revoked logs with `reviewedAt` in today.
- Cards due: schedules `dueAt <= now`, not suspended, not trashed.
- Retention (7/30 days): among non-revoked logs in window where `prevState ∈
  {review, relearning}` → share with `grade != .again`. Shown as % with "—" when
  denominator < 10 (avoid noisy numbers).
- Streak: consecutive calendar days (user's calendar/timezone at read time) ending
  today or yesterday with ≥ 1 non-revoked log.

## A7. Schema migration policy

- Model versions are additive whenever possible (new optional attributes/entities) —
  CloudKit-compatible by construction; `NSPersistentCloudKitContainer` requires
  additive evolution anyway.
- On store load: if `NSPersistentStoreCoordinator.metadata` model-compatibility check
  indicates migration, and migration is lightweight-inferable → before loading,
  `MigrationBackup.create()` copies `Private.sqlite`(+`-wal`,`-shm`) and
  `Shared.sqlite` files to `Application Support/backups/<date>-preV<N>/` (structural
  migrations only; keep last 2 backups).
- If load fails: NEVER delete the store. Enter `PersistenceFailure` mode: app boots
  into a recovery screen offering (1) Retry, (2) Export raw backup files via share
  sheet, (3) contact support. Study/content UI is not shown. This satisfies brief
  §Schema evolution.
- Heavyweight/custom migrations require a dedicated future bead + ADR; none exist in
  v1.

## A8. Trash, purge, and permanent deletion

### A8.1 Soft delete
- `TrashService.trash(note|deck)`: sets `deletedAt = now` on the object and cascades
  the flag to contained notes (deck) and their cards. Sync via normal Core Data
  mirroring (the flag is data → trash state syncs across devices/participants, per
  brief).
- All queries exclude `deletedAt != nil` unless explicitly the Trash screen.
- Restore: clear `deletedAt` on object + descendants; schedules/logs were never
  touched → progress returns intact.

### A8.2 Purge job
`PurgeService.run()` on app launch + daily while active:
1. Hard-delete content with `deletedAt < now − 30d` (deck→notes→cards cascade).
2. Delete CDSchedules/CDReviewLogs/whose `cardUUID` matches cards purged in step 1, and
   orphans whose card uuid no longer exists anywhere **and** the orphan's last touch is
   > 30d old (protects against transient sync gaps).
3. Delete CDRevisions older than 30d.
4. Delete CDImportBatches older than 90d (bookkeeping only).
Purge runs only on the user's own stores; each participant purges their mirror
independently (CloudKit propagates content deletions anyway).

### A8.3 Delete all my data
Separate, immediate, bypasses trash (brief):
- Screen explains scopes affected: local stores, private CloudKit database, and groups
  the user OWNS (deleted for everyone); groups the user joined are left (mirrors
  purged locally + membership removed).
- Two-step: destructive confirm → type `ELIMINA` (both locales use `ELIMINA`; show the
  word to type). Offer backup export first.
- Execution order: (1) optional backup, (2) delete owned CDGroups + shares, (3) leave
  joined groups (purge zones), (4) delete all objects in both stores via batch deletes
  + `NSPersistentCloudKitContainer` mirroring (deletes propagate to CloudKit), (5)
  reset UserDefaults/session/tutorial state, (6) return to onboarding.

## A9. CSV contract and import pipeline

### A9.1 Canonical CSV
- Encoding: UTF-8; accept and strip BOM. Reject other encodings with a clear error
  ("Il file non è in formato UTF-8…").
- Dialect: RFC 4180 — comma separator, `"` quoting, `""` escape, CRLF or LF, quoted
  fields may contain newlines.
- Header row required; column matching is case-insensitive on names
  `type,front,back,tags`; extra columns are ignored with a preview notice; missing
  required columns fail the whole file (actionable message listing what was found).
- Row validation:
  - `type` ∈ {basic, reversed, cloze} case-insensitive, else reject row.
  - `front` non-empty after trim, else reject row.
  - `back`: required non-empty for basic/reversed; optional for cloze.
  - cloze rows: `front` must contain ≥ 1 valid cloze deletion, else reject row with
    "nessuna cancellazione cloze valida (es. {{c1::testo}})".
  - `tags`: split on `;`, trim each, drop empties.
- Hard caps: 10 000 rows, 2 MB file, 20 000 chars per field → reject with explanation.

### A9.2 Importer pipeline (Domain: `CSVParser`, `ImportPlanner`; Data: `ImportCommitter`)
1. Parse → `[ParsedRow]` + `[RowError]`.
2. Plan against destination deck: compute fingerprints (A3.5), mark duplicates
   (default skipped, per-row override to import anyway), produce `ImportPlan`
   { valid, duplicates, rejected }.
3. Preview UI shows counts + first N rows per bucket with reasons; user picks
   destination (new deck / existing personal deck / group deck) and confirms.
4. Commit in one background transaction: create notes+cards (generation A3.1), tags
   via findOrCreate in the destination scope, write CDImportBatch.
5. Undo (from Library or the post-import toast): sets `deletedAt` on all
   `createdNoteUUIDs` notes (→ trash, fully recoverable) and `undoneAt` on the batch.

### A9.3 Entry points
- Files picker (`.fileImporter`, UTType `commaSeparatedText` + `.plainText` fallback).
- Share Sheet / app handoff: declare CSV document type support (`CFBundleDocumentTypes`
  + `LSSupportsOpeningDocumentsInPlace = NO`, copy-in), route via `onOpenURL`.
- "Copy ChatGPT prompt" button: localized prompt template instructing ChatGPT to emit
  the canonical CSV (exact template text lives in the String Catalog; includes the
  header line and one example row per type).

### A9.4 Deck CSV export
- Per-deck export producing canonical CSV (source fields, tags joined by `;`),
  filename `<deckname-slug>.csv`, via ShareLink/fileExporter. Trashed notes excluded.

### A9.5 Anki `.apkg` import (ADR-004)
Import only; FlashApp never writes `.apkg`.

- Container: ZIP. Both generations required — legacy (`collection.anki2` /
  `collection.anki21`, plain SQLite, deflate entries, JSON `media` index) and modern
  (`collection.anki21b`, zstd-compressed, stored entries, protobuf `media` index).
- Database: both schema 11 (note types and decks as JSON in `col.models` / `col.decks`)
  and schema 18 (`notetypes` / `fields` / `templates` / `decks` tables); discriminated
  on `col.ver`. Fields split on `0x1F`; tags split on whitespace; deck via `cards.did`.
- Field text is HTML → converted to FlashApp Markdown (`<br>`/`</div>`/`</p>` → newline,
  `<b>`/`<i>` → `**`/`*`, entities decoded, other tags dropped). Anki cloze syntax
  `{{cN::…}}` passes through unchanged — it is already what `ClozeParser` accepts.
- Mapping is **user-confirmed, never silent**: one mapping per Anki note type
  (target type, front field, back field, include/exclude), pre-filled with a proposed
  default (cloze if the note type is cloze or a field carries a valid deletion; reversed
  if it has ≥2 templates; otherwise basic). Unmapped fields are reported as ignored,
  reusing the A9.1 ignored-column notice.
- Output is a `CSVParseOutcome`, so A9.2 steps 2–5 (plan, preview, commit, undo) are
  shared verbatim with CSV. `ParsedRow.line` carries the 1-based note index.
- Media: `<img src>` and `[sound:…]` become `flashup-media://<uuid>` references in the
  note text; blobs are content-addressed under `Application Support/Media/`.
  Accepted `png/jpg/jpeg/gif/webp/heic` and `mp3/m4a/wav/ogg`; anything else rejects the
  row with a visible reason. A blob that fails to extract does not fail the import.
- Hard caps (`ApkgLimits`, injectable like `CSVLimits`): 10 000 notes, max file bytes,
  **max decompressed bytes**, max media count, max bytes per media. Every decompression
  path is capped and every ZIP offset bounds-checked: an `.apkg` is untrusted input and
  both deflate and zstd expand.
- Errors name the note index, never note content (§A2).
- Entry point: `.fileImporter` with an imported UTType `org.ankiweb.apkg`
  (conforms to `public.zip-archive`, extension `apkg`), declared in `Info.plist`.

## A10. FlashApp backup (versioned)

Single JSON file, extension `.flashupbackup`, UTType exported by the app.

```jsonc
{
  "format": "flashup-backup",
  "formatVersion": 1,
  "appVersion": "1.0 (build)",
  "exportedAt": "ISO8601",
  "settings": { "newPerDay": 20, "reviewsPerDay": 200, "appearance": "system",
                 "reminder": {"enabled": true, "hour": 20, "minute": 30} },
  "decks": [ { "uuid": "...", "name": "...", "origin": "personal|sharedSnapshot",
               "createdAt": "...", "notes": [ { "uuid": "...", "type": "basic",
                 "front": "...", "back": "...", "tags": ["..."],
                 "createdAt": "...", "updatedAt": "...",
                 "cards": [ {"uuid":"...","templateKey":"forward"} ] } ] } ],
  "schedules": [ { "cardUUID": "...", "state": 2, "stability": 0.0,
                   "difficulty": 0.0, "dueAt": "...", "reps": 1, "lapses": 0,
                   "suspendedAt": null, "lastReviewedAt": "..." } ],
  "reviewLogs": [ { "uuid": "...", "cardUUID": "...", "deckUUID": "...",
                    "reviewedAt": "...", "grade": 3, "durationMs": 1200,
                    "prevState": 0, "prevStability": 0, "prevDifficulty": 0,
                    "scheduledDays": 0, "elapsedDays": 0, "revokedAt": null } ]
}
```

- Export scope: all personal decks + snapshots of shared decks the user can see
  (marked `origin = sharedSnapshot`), all private study data, settings. Demo deck
  excluded. Trashed content excluded.
- Restore: `formatVersion` gate (unknown major → refuse with "backup created by a
  newer version" message). Merge policy: objects restore by uuid; existing uuid →
  skip (never overwrite live data); `sharedSnapshot` decks restore as personal decks
  (brief: backups do not recreate groups). Review logs merge append-only by uuid;
  schedules restore only if absent, then replay reconciles.
- `BackupCodec` lives in Domain (pure Codable structs), `BackupService` in Data.
- Future format changes bump `formatVersion` with a documented migration in
  `docs/decisions/backup-format.md` (verification task 7).

## A11. UI architecture

### A11.1 Structure
- Pattern: SwiftUI views + `@Observable` feature models (one per screen family),
  constructed by `AppEnvironment` (manual DI via initializers/Environment; no DI
  framework).
- Tabs (`TabView`): Today, Library, Groups, Settings. iPad: same TabView (brief has
  no sidebar requirement; keep one adaptive layout). Statistics detail pushes from
  Today (no fifth tab).
- Appearance: setting {system, light, dark} → `preferredColorScheme` at root.

### A11.2 Screen inventory (bead references in Part B)

| Area | Screens |
|---|---|
| Today | TodayView (due/new counts, streak, Study Now, summary metrics), StatisticsView (detail: retention 7/30, per-deck due table, history chart via Swift Charts) |
| Library | DeckListView, DeckDetailView (notes list, filters), NoteEditorView, NotePreview (generated cards), SearchView (global), TrashView, ImportFlow (picker → preview → result), ExportSheet |
| Study | StudySessionView (prompt → reveal → grades), SessionCompleteView, ResumePrompt |
| Groups | GroupListView, GroupDetailView (decks, participants), CreateGroupSheet, ShareInviteFlow, RevisionHistoryView, LeaveDeleteFlows, MoveDeckSheet |
| Settings | SettingsRoot, StudySettings, RemindersSettings, SyncStatusView, DataView (import/export/backup/trash link), DeleteAllDataFlow, PrivacyView, HelpView (FAQs + replayable tutorials), SupportComposer |
| Onboarding | 3-step tutorial (import journey, review interaction, grades) + demo deck install |

### A11.3 Study interaction contract
- Card front (Markdown-rendered) → "Mostra risposta" (tap anywhere / spacebar on
  iPad-with-keyboard) → back revealed → four grade buttons (localized: Ancora/Di
  nuovo? Use: "Di nuovo", "Difficile", "Buono", "Facile"; EN: Again/Hard/Good/Easy)
  with next-interval captions ("<10 min", "3 g", …) from FSRS preview.
- Keyboard: 1–4 grades, space reveal. VoiceOver: reveal is a button; grades are
  buttons with interval in the accessibility value.
- Undo button (toolbar) enabled only when a last non-revoked answer exists in this
  session. Card context menu: Suspend, Reset (confirm), Edit note.
- Reduced motion: replace flip animation with crossfade.

### A11.4 Onboarding & tutorials
- `TutorialState` in UserDefaults: `didFinishOnboarding`, `didSeeGroupsTutorial`,
  `didSeeSettingsTutorial`, `didPromptReminders`, `reviewPromptMilestoneDone`.
- Onboarding: mandatory, 3 short screens, ends installing the localized demo deck
  (bundled CSV imported through the real import pipeline, `isDemo = true`).
- Groups/Settings tutorials: one-off sheets on first tab entry; replayable from Help.
- Reminder ask: after first completed session → sheet to pick a time → only on enable
  request `UNUserNotificationCenter` authorization; schedule daily
  `UNCalendarNotificationTrigger`. Changeable in Settings.
- Review request: `SKStoreReviewController.requestReview` once, when (sessions ≥ 5 and
  streak ≥ 3) — never again if `reviewPromptMilestoneDone`.

### A11.5 Search & filters (Library)
- `LocalSearchService`: fetch over non-trashed decks/notes with
  `name/front/back CONTAINS[cd]` + tag name match; entirely local (brief).
- Filters: note type, state (new = any card without schedule; due; suspended),
  origin (personal/shared). Sorting: name, updatedAt, next review (min dueAt of the
  note's cards), card count. Sorting by schedule data joins by uuid in memory (A1.3).

### A11.6 Support
- "Contatta il supporto" → `mailto:` prefilled (subject, app version, iOS version,
  locale). Diagnostics attachment ONLY after an explicit toggle in the composer sheet:
  attaches a generated text report (app version, device model, iCloud availability
  enum, store sizes, counts of decks/notes/cards, last SyncError codes) — **never card
  content** (assert in code + unit test that the report generator has no content
  fields).

## A12. Privacy, App Store, release

- Privacy policy (hosted URL) + App Privacy answers derive from implementation:
  data not collected by developer; iCloud storage is user's own. Completed in B9.3
  from verified behavior (brief §App Store presentation).
- App Store Connect setup checklist (manual bead B0.5): name availability ("FlashApp"),
  bundle id `com.<team>.flashup`, price tier €1.99, category Education, 4+ rating
  questionnaire, Family Sharing toggle OFF if the option exists (verification task 1),
  IT+EN metadata, screenshots demonstrating ChatGPT→CSV→import→study.
- CI: `ci/test.sh` runs SwiftLint, `swift test` for FlashUpKit (macOS), and
  `xcodebuild test` for app + UI tests on an iOS 17 iPhone simulator; `ci/build.sh`
  archives for TestFlight.

---

# PART B — Bead plan

Legend: each bead lists **Deps** (must be DONE first), **Tasks**, **Deliverables**,
**Stop conditions** (all must be true; then STOP), **Out of scope**.
Global rules §0 apply to every bead. Phases are ordered; beads inside a phase may run
in parallel unless Deps say otherwise.

Dependency overview:

```
Phase 0 ─ B0.1 → B0.2 → B0.3
              └→ B0.4        (B0.5 manual, anytime before Phase 9)
Phase 1 ─ B1.1(←B0.2) → B1.2 → B1.3, B1.4
Phase 2 ─ B2.1 → B2.2 → B2.3 ; B2.4, B2.5 (←B1.2)
Phase 3 ─ B3.1(←B0.4,B1.2) → B3.2 → B3.3 → B3.4 ; B3.5(←B3.2)
Phase 4 ─ B4.1 → B4.2(←B2.2,B2.5) → B4.3 ; B4.4 ; B4.5(←B3.2)
Phase 5 ─ B5.1(←B1.4) → B5.2(←B3.5) , B5.3 , B5.4(←B2.x) , B5.5 , B5.6(←B1.3) , B5.7
Phase 6 ─ B6.1(←B3.4,B5.1) → B6.2
Phase 7 ─ B7.1(←B0.3,B5.1) → B7.2 → B7.3 → B7.4 → B7.5 → B7.6
Phase 8 ─ B8.1…B8.6 (←B5.1 + subsystem deps noted)
Phase 9 ─ B9.1 → B9.2 → B9.3
```

---

## Phase 0 — Foundations and verification spikes

### B0.1 — Project scaffold
**Deps:** none.
**Tasks:**
1. Create the Xcode project and targets exactly per §0.3: app target `FlashUp`
   (iOS 17.0, iPhone+iPad, "Mac (Designed for iPad)" enabled, Catalyst OFF), local
   package `FlashUpKit` with `FlashUpDomain`/`FlashUpData` targets + test targets,
   `FlashUpUITests`.
2. Add SPM deps: swift-fsrs (pin to latest release tag; B0.4 will confirm),
   swift-markdown.
3. Enable capabilities: iCloud → CloudKit with container `iCloud.<bundle-id>`,
   Background Modes → Remote notifications, Push Notifications (required for CloudKit
   silent pushes).
4. Add `.swiftlint.yml`, `ci/test.sh`, `ci/build.sh`; placeholder `TabView` with 4
   empty tabs; String Catalog with the tab titles in en+it.
5. Copy the architecture brief into `docs/`, create `docs/decisions/worklog.md`.
**Deliverables:** compiling project, green CI script locally.
**Stop conditions:** app boots to 4-tab shell on iPhone+iPad sims; `swift test` runs
(zero tests OK); lint clean. STOP — no Core Data, no features.
**Out of scope:** any model code, any UI beyond the empty shell.

### B0.2 — Spike: CloudKit store topology proof (ADR)
**Deps:** B0.1. **Type:** spike — throwaway code allowed under `Spikes/` (excluded
from release target), but the ADR is the deliverable.
**Tasks:**
1. Build a minimal `NSPersistentCloudKitContainer` with the two-store topology of
   A1.1 and a toy entity; verify mirroring setup succeeds
   (`initializeCloudKitSchema(options:)` in DEBUG) with the app's container id.
2. Verify: history tracking + remote change notifications fire on both stores;
   local-only mode (no cloudKitContainerOptions) loads the same files.
3. Document in `docs/decisions/ADR-001-store-topology.md`: exact store options,
   schema-initialization procedure, entitlements, gotchas found. Address verification
   tasks 2 and 3 (quota notes from CloudKit docs/console).
**Stop conditions:** ADR-001 committed answering: two-store setup works as specified /
any deviation required (flag for human review). STOP — do not build the real model.
**Out of scope:** production persistence code, sharing (that's B0.3).

### B0.3 — Spike: sharing + deck move proof (ADR)
**Deps:** B0.2. **Type:** spike, two Apple test accounts + two simulators/devices.
**Tasks:**
1. Extend the spike: share a root object via `share(_:to:)`, accept from account B
   into the shared store, confirm mirroring, participant listing, `.readWrite`
   default, leave via `purgeObjectsAndRecordsInZone`.
2. Prove the A5.6 move algorithm on toy entities: copy graph with preserved uuids
   private→shared zone and shared→private, delete source, confirm no residual records
   in CloudKit Console.
3. Confirm `acceptShareInvitations` wiring in a SwiftUI app lifecycle (verification
   task 5) and note the exact delegate/scene hooks used.
4. Write `docs/decisions/ADR-002-sharing-and-move.md` incl. whether ownership
   transfer is feasible (expected: not offered; confirm).
**Stop conditions:** ADR-002 committed; move algorithm confirmed or amended (human
review if amended). STOP.
**Out of scope:** production ShareManager.

### B0.4 — Spike: swift-fsrs API pinning (ADR)
**Deps:** B0.1.
**Tasks:**
1. Pin exact version; enumerate its public API (state struct, rating enum, scheduler
   call, retention parameter, interval preview capability).
2. Prototype the `FSRSService` protocol in Domain + adapter; verify: desired
   retention 0.90 configurable, deterministic outputs for a fixed input sequence
   (replay requirement A6.4), next-interval preview for the four grades.
3. `docs/decisions/ADR-003-fsrs.md` with the mapping table (our Grade ↔ library
   Rating, our stateRaw ↔ library state) and the pinned version.
**Stop conditions:** ADR-003 committed; `FSRSService` protocol merged into Domain with
adapter + determinism unit test. STOP — no Schedule persistence.
**Out of scope:** CDSchedule, queue, UI.

### B0.5 — Manual checklist: App Store Connect setup (human task)
**Deps:** none (needs Apple Developer account; complete before Phase 9).
**Tasks:** execute A12 checklist; record outcomes (name availability, Family Sharing
toggle answer — verification task 1, price tier, rating) in
`docs/decisions/ADR-004-appstore.md`.
**Stop conditions:** ADR-004 committed. Not a coding bead.

---

## Phase 1 — Data layer

### B1.1 — Core Data model V1 + PersistenceController
**Deps:** B0.2 (ADR-001).
**Tasks:**
1. Implement `FlashUp.xcdatamodeld` V1 exactly per A2 (all entities, attributes,
   relationships, delete rules, indexes on uuid/cardUUID/deckUUID/dueAt/deletedAt).
2. `PersistenceController` per A1.1/A4.1 incl. local-only mode, in-memory mode for
   tests, DEBUG `initializeCloudKitSchema` hook behind a launch argument.
3. Base `NSManagedObject` subclasses with `awakeFromInsert`/`willSave` timestamp
   behavior (loop-guarded).
4. Tests (FlashUpDataTests, in-memory + on-disk): model loads without warnings;
   CloudKit-compat lint test that programmatically walks the model asserting A1.2
   rules (no unique constraints, optionals/defaults, inverses, unordered).
**Stop conditions:** tests green incl. the model-lint test; app boots with both stores
attached (or local-only) without console errors. STOP — no repositories.
**Out of scope:** queries, sync processing, UI.

### B1.2 — Repositories and store affinity
**Deps:** B1.1.
**Tasks:**
1. `ContentRepository` (decks/notes/cards/tags/groups/revisions CRUD, uuid lookups,
   non-trashed default predicate) and `StudyRepository` (schedules/logs/import
   batches) with `assign(to: privateStore)` on every study insert + DEBUG assertion
   per A1.3.
2. `findOrCreateTag(name, scope:)` per A3.6 (normalization from Domain).
3. Fetch helpers spanning both stores for content; store-scoped fetches
   (`affectedStores`) where scope matters (personal vs shared listings).
4. Tests: affinity assertion (schedule created while a shared store exists lands in
   private store); tag scope isolation (same normalizedName in personal vs group
   graphs yields distinct CDTags); cross-store deck listing.
**Stop conditions:** tests green. STOP.
**Out of scope:** sync pipeline, dedup, purge.

### B1.3 — TrashService + PurgeService
**Deps:** B1.2.
**Tasks:** implement A8.1 + A8.2 exactly; wire purge to app launch (call site behind a
protocol so B5.x just triggers it); unit tests: cascade flagging, restore returns
progress (schedule untouched), 30-day boundary purge incl. orphan schedule/log rule,
revision pruning, import-batch pruning.
**Stop conditions:** tests green covering every A8.1/A8.2 rule. STOP.
**Out of scope:** Trash UI, delete-all-data.

### B1.4 — SyncMonitor + RemoteChangeProcessor skeleton
**Deps:** B1.2.
**Tasks:**
1. `SyncMonitor` per A4.4 (account status via `CKContainer.accountStatus` +
   `CKAccountChanged`, event notification consumption, availability/activity/error
   state, retry action).
2. `RemoteChangeProcessor` per A4.2 with history-token persistence and the debounce;
   hook points for reconciler/replayer/dedup registered as closures (real
   implementations arrive in B2.2/B3.2/B2.4) — unknown hooks no-op.
3. `Deduplicator` for CDTag per A4.3 (CDSchedule dedup added in B3.2).
4. Tests: token persistence/resume; tag dedup convergence ("lowest uuid wins",
   relinking); monitor state transitions driven by injected notifications.
**Stop conditions:** tests green; manual check: two simulators with same account
converge on a created deck (documented in worklog). STOP.
**Out of scope:** sharing, UI badges.

---

## Phase 2 — Domain logic (pure, no UI)

### B2.1 — ClozeParser
**Deps:** B0.1.
**Tasks:** implement A3.4 scanner + renderer in FlashUpDomain. Exhaustive tests:
single/multiple/repeated groups, hints, malformed (unclosed, `{{c0::}}`, empty text,
nested braces), unicode, group extraction (`groups(in:) -> Set<Int>`), render masking
with/without hint, issues reporting.
**Stop conditions:** all listed cases tested and green. STOP.
**Out of scope:** card generation, editor UI.

### B2.2 — CardGenerator + CardReconciler
**Deps:** B2.1, B1.2.
**Tasks:**
1. `CardGenerator` per A3.1 (Domain: pure templateKey/content computation).
2. `CardReconciler` (Data): sync CDCards to desired templateKeys with stable uuids
   (A3.2), soft-delete removed templates; register as RemoteChangeProcessor hook for
   changed notes.
3. Tests: basic→1, reversed→2, cloze groups {1,3}→2 cards; editing text preserves
   card uuids; removing c2 soft-deletes `cloze:2`; re-adding c2 later creates a NEW
   uuid (soft-deleted one is not resurrected — deliberate: progress on a removed
   deletion is stale); remote-change hook runs reconciliation.
**Stop conditions:** tests green. STOP.
**Out of scope:** FSRS, study.

### B2.3 — NoteTypeConverter
**Deps:** B2.2, B3.2 preferred but not required (history check may stub the log query
behind a protocol until B3.2 lands; wire real query in B3.2's tasks — noted there).
**Tasks:** implement A3.3 with `hasStudyHistory` provider protocol; tests: in-place
conversion when no history; duplicate creation when history or group membership; tags
copied; cards reconciled on the duplicate.
**Stop conditions:** tests green. STOP.
**Out of scope:** editor UI.

### B2.4 — TagNormalizer + tag dedup completion
**Deps:** B1.4.
**Tasks:** `TagNormalizer` per A3.6 in Domain (tests: casefold incl. Turkish-i safe
locale-independence, NFC, whitespace); confirm Deduplicator uses it; add scope-aware
dedup test (personal vs group tags never merge).
**Stop conditions:** tests green. STOP.

### B2.5 — ContentFingerprint
**Deps:** B0.1.
**Tasks:** implement A3.5 (CryptoKit SHA256) + tests (normalization equivalences,
separator injection resistance: ("ab","c") ≠ ("a","bc")); wire hash computation into
CDNote save path (Data).
**Stop conditions:** tests green; every note save updates contentHash. STOP.

---

## Phase 3 — FSRS and study engine

### B3.1 — Schedule persistence + StudyEngine.answer
**Deps:** B0.4, B1.2.
**Tasks:** implement A6.2 exactly (CDSchedule create/load by cardUUID, transition via
FSRSService, CDReviewLog append with full pre-transition snapshot). Tests with a fake
deterministic FSRSService + the real adapter: new→learning→review path, snapshot
fields correct, one save per answer, schedule pinned to private store.
**Stop conditions:** tests green. STOP.
**Out of scope:** queue, undo, UI.

### B3.2 — ScheduleReplayer + multi-device merge + schedule dedup
**Deps:** B3.1, B1.4.
**Tasks:**
1. Implement A6.4 replay; register RemoteChangeProcessor hook for inserted logs.
2. Add CDSchedule dedup to Deduplicator per A4.3 (replay before delete).
3. Wire NoteTypeConverter's real history provider (from B2.3).
4. Tests: interleaved two-device logs replay to identical state regardless of
   insertion order (property-style test over shuffled permutations); revoked logs
   skipped; dedup keeps lowest uuid and reflects union of logs; determinism uses
   (reviewedAt, uuid) tiebreak.
**Stop conditions:** tests green, incl. the permutation test. STOP.

### B3.3 — QueueBuilder + limits
**Deps:** B3.1.
**Tasks:** implement A6.5 (StudySettings defaults 20/200 in UserDefaults-backed
`SettingsStore`, adjustable API only). Tests: due-before-new; per-day caps count
today's logs correctly (incl. revoked excluded); suspension and trash exclusion;
all-decks interleave; midnight rollover uses current calendar.
**Stop conditions:** tests green. STOP.
**Out of scope:** session UI, settings UI.

### B3.4 — Session engine (resume, undo, suspend, reset)
**Deps:** B3.3.
**Tasks:** implement A6.6 SessionState persistence + `StudySession` model (queue,
answer→advance, undo per A6.3 with replay + re-queue at front, suspend/reset actions,
completion stats: cards completed, elapsed time). Tests: save/restore roundtrip, 24h
expiry, undo restores previous schedule state exactly, reset revokes all logs +
fresh schedule, completion stats.
**Stop conditions:** tests green. STOP.
**Out of scope:** all UI.

### B3.5 — MetricsService
**Deps:** B3.2.
**Tasks:** implement A6.7 with day-cache invalidated on new logs/remote merges.
Tests: retention window edges, <10-denominator "—" rule, streak across timezone
change and yesterday-grace, studied-today, due count excludes suspended/trashed.
**Stop conditions:** tests green. STOP.

---

## Phase 4 — Import/export/backup

### B4.1 — CSVParser
**Deps:** B0.1.
**Tasks:** RFC 4180 parser in Domain per A9.1 (streaming over the decoded string is
fine; enforce caps). Tests: quoting/escapes/newlines-in-quotes, CRLF/LF, BOM strip,
non-UTF8 rejection, header case-insensitivity, extra/missing columns, caps.
**Stop conditions:** tests green. STOP.

### B4.2 — ImportPlanner + ImportCommitter + undo
**Deps:** B4.1, B2.2, B2.5, B1.3.
**Tasks:** implement A9.2 (row validation incl. cloze check via ClozeParser; dedup
via fingerprints vs destination deck; ImportPlan model; transactional commit creating
notes/cards/tags + CDImportBatch; undo → trash + `undoneAt`). Tests: each rejection
reason, duplicate default-skip + override, plan counts, commit atomicity (simulated
mid-commit failure leaves no partial batch), undo recoverability via TrashService.
**Stop conditions:** tests green. STOP.
**Out of scope:** UI, file entry points.

### B4.3 — Import UI + entry points + ChatGPT prompt
**Deps:** B4.2, B5.1.
**Tasks:** implement A9.3 (fileImporter, document-type registration + onOpenURL
routing, ImportFlow screens: destination picker incl. group decks when available →
preview with buckets/reasons/toggles → progress → result toast with Undo). Localized
ChatGPT prompt template + copy button. UI test: bundled fixture CSV → import to new
deck → notes visible → undo → trash contains them.
**Stop conditions:** UI test green; manual share-sheet ingest verified once
(worklog). STOP.
**Out of scope:** backup, export.

### B4.4 — Deck CSV export
**Deps:** B4.1, B5.3.
**Tasks:** A9.4 writer (Domain) + ShareLink UI in DeckDetail. Tests: writer
round-trips through CSVParser losslessly for all three types incl. quotes/newlines.
**Stop conditions:** round-trip test green. STOP.

### B4.5 — Backup export/restore
**Deps:** B3.2, B1.3.
**Tasks:** implement A10 (BackupCodec Domain structs + tests; BackupService export
incl. shared snapshots, restore with uuid-skip merge, snapshot→personal conversion,
formatVersion gate; fileExporter/importer UI in Settings→Data arrives in B8.1 —
here expose service + a Data-layer integration test only).
Tests: export→wipe(in-memory)→restore round-trip preserves decks/notes/cards/
schedules/logs; restoring over live data skips existing uuids; unknown formatVersion
refused; shared snapshot becomes personal deck.
**Stop conditions:** tests green. STOP.
**Out of scope:** Settings UI wiring (B8.1), delete-all-data.

---

## Phase 5 — UI shell, Library, editor

### B5.1 — App shell, theming, navigation, sync badge
**Deps:** B1.4.
**Tasks:** real 4-tab shell with per-tab NavigationStack; AppEnvironment composition
root building PersistenceController/services; appearance setting plumbing
(`preferredColorScheme`); `SyncBadge` + Library passive banner per A4.4 with Retry;
PersistenceFailure recovery screen per A7 (retry/export raw files/support). Empty
states for all tabs.
**Stop conditions:** boots on iPhone/iPad; forced local-only mode shows correct
banner; recovery screen reachable via a DEBUG launch argument that simulates load
failure. STOP.
**Out of scope:** feature screens' content.

### B5.2 — Today
**Deps:** B5.1, B3.5, B3.3.
**Tasks:** TodayView per A11.2 (due/new counts, streak, essential metrics, Study Now
CTA routing to scope chooser: all decks or pick deck), StatisticsView detail (Swift
Charts: 30-day reviews/day bar chart, retention figures, per-deck due table).
UI test: metrics render with seeded data.
**Stop conditions:** UI test green; VoiceOver labels on all metrics. STOP.

### B5.3 — Library: decks and notes
**Deps:** B5.1, B1.3.
**Tasks:** DeckListView (create/rename/delete→trash, personal + shared sections,
demo badge, card/due counts), DeckDetailView (notes list with type badges, tag
chips, multi-select bulk actions: add/remove tag, move to deck, duplicate, trash —
brief §Note editor bulk actions), swipe actions. Move/duplicate note operations in
ContentRepository (duplicate = new uuids for note+cards, no progress).
**Stop conditions:** UI test: create deck → add note (stub editor OK if B5.4 not yet
merged; else full) → bulk-tag two notes → trash deck → appears in trash. STOP.
**Out of scope:** group management UI.

### B5.4 — Note editor
**Deps:** B2.1–B2.3, B5.3.
**Tasks:** NoteEditorView per brief §Note editor: type picker (conversion via
NoteTypeConverter with its duplicate-when-history flow + explanatory alert), front/
back Markdown text editors, formatting toolbar (bold, italic, list, code, "Crea
cloze" from selection auto-numbering next free group), live rendered preview toggle
(MarkdownView per A3.7 — implement MarkdownView here), generated-cards preview
(CardGenerator), autosave drafts (debounced save to the real note; new-note drafts
persisted as real notes marked complete on first explicit save? NO — simpler per
brief "automatic draft saving": new note is created on first keystroke and saved
continuously; Cancel trashes it silently, bypassing trash UI via hard delete since
it never had history), warning when an edit removes cloze groups with existing cards
(A3.2).
**Stop conditions:** UI tests: create each type incl. cloze via toolbar; preview
shows correct card count; killing app mid-edit preserves draft; type change on
studied note produces duplicate. STOP.
**Out of scope:** attachments (deferred), revision history UI.

### B5.5 — Search & filters
**Deps:** B5.3, B3.3 (schedule joins).
**Tasks:** implement A11.5 (`.searchable` on Library, filter sheet, sort menu;
in-memory schedule joins for "due/suspended/next review"). Tests: LocalSearchService
unit tests for matching/filter/sort combos incl. accent/case-insensitive.
**Stop conditions:** tests green + UI smoke. STOP.

### B5.6 — Trash UI
**Deps:** B1.3, B5.3.
**Tasks:** TrashView (days-remaining labels, restore, delete-now with confirm,
empty-trash), reachable from Library and Settings→Data. UI test: trash→restore
returns note with intact schedule (seeded).
**Stop conditions:** UI test green. STOP.

### B5.7 — Statistics polish
**Deps:** B5.2. *(Merge into B5.2 if trivial; exists to cap scope there.)*
**Tasks:** accessibility for charts (audio graph/summaries), reduced-motion chart
animations off, iPad layout pass for Today/Statistics.
**Stop conditions:** VoiceOver reads chart summaries; layouts verified both sizes. STOP.

---

## Phase 6 — Study UI

### B6.1 — StudySessionView
**Deps:** B3.4, B5.1, B5.4 (MarkdownView).
**Tasks:** implement A11.3 fully (reveal, grade buttons with FSRS interval captions,
keyboard shortcuts, undo, suspend/reset/edit context menu, progress indicator,
reduced-motion crossfade, VoiceOver flow). Cloze rendering via ClozeParser.render
composed with MarkdownView.
**Stop conditions:** UI test: seeded deck → answer 3 cards with different grades →
undo last → re-answer → session count correct. Accessibility audit of the screen
(labels/actions) noted in worklog. STOP.

### B6.2 — Completion + resume
**Deps:** B6.1.
**Tasks:** SessionCompleteView (cards completed, time spent, streak delta), resume
prompt on launch/tab-entry when SessionState valid (A6.6), reminder-ask trigger hook
after first-ever completion (sheet itself in B8.4 — here emit the event).
**Stop conditions:** UI test: kill app mid-session → relaunch → resume → complete →
completion stats correct. STOP.

---

## Phase 7 — Groups and sharing

### B7.1 — ShareManager + create group + invite
**Deps:** B0.3 (ADR-002), B5.1.
**Tasks:** production ShareManager per A4.1/A5.1; GroupListView + CreateGroupSheet;
share creation with title/permissions; invite via CloudSharingView wrapper +
copy-link. Groups tutorial trigger point registered (sheet content in B8.3).
Integration test (two-account, semi-manual per brief's quality bar): scripted
checklist committed at `docs/testing/sharing-checklist.md` and executed once (worklog).
**Stop conditions:** owner can create group and obtain a working invite URL on
device/sim with account A. STOP.
**Out of scope:** acceptance (B7.2), deck content in groups (B7.4).

### B7.2 — Invitation acceptance
**Deps:** B7.1.
**Tasks:** implement A5.2 (delegate adaptor + acceptShareInvitations into shared
store, joining placeholder, error surfaces: already-member, revoked link, no-iCloud
guidance). Update sharing-checklist and execute acceptance flow across two accounts.
**Stop conditions:** account B sees the group in Groups after accepting; local-only
mode shows the correct "iCloud richiesto per i gruppi" explanation instead of
crashing. STOP.

### B7.3 — Group detail: participants, leave, remove
**Deps:** B7.2.
**Tasks:** GroupDetailView (decks section, participants via share.participants with
owner/editor labels, owner: remove participant; member: leave with A5.7 safeguard
incl. "Copy decks first"); leave = purge zone per A5.3; verify private logs survive
(automated Data test with simulated purge + manual checklist item).
**Stop conditions:** checklist executed: remove + leave both verified across
accounts; Data test green (schedules survive purge). STOP.

### B7.4 — DeckMover + move/copy UI
**Deps:** B7.3, B2.2.
**Tasks:** production `DeckMover` per A5.6 incl. failure reconciliation (5) and the
owner-only move-out / editor copy-to-personal policy; MoveDeckSheet from DeckDetail
and Import destination picker integration (group destinations). Data tests: uuid
preservation, tag re-mapping, revision-drop rules, schedule continuity across move,
duplicate-uuid reconciliation after simulated failed source deletion. Checklist:
move personal→group visible to account B; progress retained on both sides.
**Stop conditions:** all Data tests green; checklist executed. STOP.

### B7.5 — Revision history
**Deps:** B7.4.
**Tasks:** RevisionRecorder per A5.5 (hook into shared-note save path + deck rename;
throttle), RevisionHistoryView (list author/timestamp/diff-preview as before/after
text, Restore with pre-restore snapshot), pruning already in PurgeService (verify
wiring). Tests: throttle, restore semantics, prune at 30d; concurrent-edit
last-writer behavior documented via test (two contexts, updatedAt policy per brief).
**Stop conditions:** tests green; checklist: edit from B, restore from A. STOP.

### B7.6 — Group deletion + ownership UX copy
**Deps:** B7.5.
**Tasks:** owner deletion flow per A5.4; ownership explanation copy (A5.3, brief
§Ownership) in Group detail; participant-side experience when a group disappears
(graceful empty state + archived-progress note). Checklist execution.
**Stop conditions:** checklist executed both roles; no crash on participant when
owner deletes mid-use. STOP.

---

## Phase 8 — Settings, onboarding, system surfaces

### B8.1 — Settings
**Deps:** B5.1, B3.3, B4.5, B5.6, B1.4.
**Tasks:** SettingsRoot per brief §Settings: study limits (20/200 editors), reminders
row (state; controls in B8.4), SyncStatusView (availability, last sync activity,
retry, iCloud guidance), Data (import entry, deck export pointer, backup
export/restore wiring fileExporter/Importer to B4.5, trash link), appearance picker,
accessibility guidance text, privacy info screen, Help placeholder link (B8.6),
Delete-all-data entry (flow in B8.5).
**Stop conditions:** every brief §Settings bullet reachable; backup export+restore
works end-to-end from UI (UI test with small seed). STOP.

### B8.2 — Onboarding + demo deck
**Deps:** B4.2, B5.1, B6.1.
**Tasks:** mandatory 3-step onboarding per A11.4 (import journey w/ ChatGPT prompt
mention, review interaction, grades explained), demo deck CSVs (it/en, ~15 notes
covering all three types, study-method themed content authored in this bead),
installed via ImportCommitter with `isDemo`; TutorialState persistence.
**Stop conditions:** fresh install → onboarding → demo deck studyable immediately;
onboarding never reappears (state test); skippable is NOT allowed (mandatory) but ≤
3 screens. STOP.

### B8.3 — Contextual tutorials + Help
**Deps:** B8.2, B7.1.
**Tasks:** Groups tutorial (first Groups entry: create/invite/share decks) and
Settings tutorial (first Settings entry), short + skippable + replayable from Help;
Help screen with FAQs (authored: import format, sync troubleshooting, groups &
privacy of progress, trash/backup, contact) in it+en.
**Stop conditions:** tutorials fire exactly once (state tests), replay works. STOP.

### B8.4 — Reminders
**Deps:** B6.2, B8.1.
**Tasks:** implement A11.4 reminder flow (post-first-session sheet consuming B6.2's
event, permission requested only on enable, daily UNCalendarNotificationTrigger,
Settings controls change/disable, handle permission-denied state with Settings
deep-link guidance). Tests: trigger scheduling math; state machine unit tests;
manual notification delivery check (worklog).
**Stop conditions:** tests green; manual check done. STOP.

### B8.5 — Delete all my data
**Deps:** B8.1, B4.5, B7.6.
**Tasks:** implement A8.3 exactly (explanatory screen incl. separate owned-groups
warning, ELIMINA typed confirmation, pre-deletion backup offer, ordered execution,
return to onboarding). Data test for the execution order on in-memory stores;
UI test for the confirmation gate (wrong text ≠ enabled).
**Stop conditions:** tests green; manual two-account check: owned group vanishes for
participant, joined group untouched for its owner. STOP.

### B8.6 — Support + review prompt
**Deps:** B8.1.
**Tasks:** SupportComposer per A11.6 (mailto with prefill, consent-gated diagnostics
report, content-free assertion + unit test), review request per A11.4 milestone with
one-shot persistence.
**Stop conditions:** unit test proving diagnostics contain no note/card fields; review
request fires once in a seeded-milestone UI test. STOP.

---

## Phase 9 — Localization, accessibility, release QA

### B9.1 — Localization completeness
**Deps:** all UI beads.
**Tasks:** audit String Catalog: zero untranslated it/en entries (fail CI via a
script in `ci/l10n-check.sh` parsing xcstrings state); localized FSRS grade names,
interval captions, dates via formatters; screenshots of key screens in both locales
attached to worklog; pseudo-localization pass for truncation on small iPhone.
**Stop conditions:** l10n-check green in CI; truncation issues fixed. STOP.

### B9.2 — Accessibility & appearance audit
**Deps:** all UI beads.
**Tasks:** full pass per brief quality bar: VoiceOver task flows (onboarding, import,
study, settings), Dynamic Type up to accessibility sizes, increased contrast, reduced
motion, dark/light/system, keyboard on iPad; fix findings; record audit matrix in
`docs/testing/a11y-matrix.md`.
**Stop conditions:** matrix committed with all cells pass. STOP.

### B9.3 — Release QA, TestFlight, App Store package
**Deps:** everything, B0.5.
**Tasks:**
1. Execute the brief's full test matrix: purchase-fresh-install path (TestFlight),
   onboarding, import, study, reminders, backup/restore, permanent deletion; sharing
   checklist re-run on ≥ 2 accounts and ≥ 2 devices incl. offline edits + conflicts;
   device matrix small iPhone / large iPhone / iPad / Apple Silicon Mac. Log results
   in `docs/testing/release-matrix.md`.
2. Migration test: install a build with a synthetic V0→V1-style store fixture? V1 is
   first release — instead verify PersistenceFailure recovery path and
   MigrationBackup dry-run with a corrupted-store fixture.
3. TestFlight: internal round → fixes → small external student cohort → triage; no
   release-blocking defects open.
4. App Store: localized metadata, screenshots/video demonstrating ChatGPT→CSV→
   import→study, privacy policy URL, App Privacy from verified behavior, submit per
   ADR-004.
**Stop conditions:** release-matrix all pass; zero open blockers; submission
completed. END OF PLAN.

---

## Appendix: bead-sizing and agent guidance

- Preferred bead granularity above is 0.5–2 agent-days. If a bead balloons, STOP at
  the first unmet assumption and write the finding to `docs/decisions/` instead of
  expanding scope.
- Never "improve" neighboring code drive-by; file a worklog follow-up.
- When the brief and this spec disagree, the brief wins; stop and flag.
- When CloudKit reality and ADR-001/002 disagree, stop and flag — sync architecture
  changes are never made inside a feature bead.
