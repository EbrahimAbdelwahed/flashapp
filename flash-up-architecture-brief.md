# FlashApp — Architecture and Product Constraints

Status: approved product brief for specification work  
Purpose: source of truth for Claude/Fable and implementation planning

## Instruction to the specification author

Treat every statement marked **Required** as a fixed constraint. Do not reopen
product strategy, replace the Apple stack, add monetization, or expand the
launch scope. Where implementation details remain open, compare viable
approaches and select the smallest production-ready option that preserves these
constraints.

This is not a prototype or throwaway MVP. The target is the first complete
release submitted to the App Store, followed by incremental updates.

## Product definition

FlashApp is a low-friction flashcard application for students who already have
cards generated elsewhere, especially in ChatGPT. The core journey is:

**ChatGPT → CSV → import → study**

The product is for university students with Apple devices, particularly those
in their first years who are still developing a study method and are discouraged
by subscriptions or complicated flashcard software.

### Positioning

- **Required:** compete against recurring subscriptions and unnecessary
  complexity, not against Anki.
- **Required:** communicate “pay once, import what you already have, and start
  studying.”
- **Required:** no advertising inside the application.
- **Required:** no subscription for core or launch functionality.

## Commercial and App Store constraints

- **Required:** paid download at €1.99.
- **Required:** no free tier, trial, in-app purchase, or subscription.
- **Required:** all launch functionality is included in the purchase.
- **Required:** disable Family Sharing if App Store Connect permits it.
- **Required:** App Store category is Education.
- **Required:** expected age rating is 4+, subject to the final App Store
  questionnaire.
- **Required:** worldwide availability with Italian and English localization.
- **Required:** initial marketing focuses on Italy.
- **Required:** no third-party advertising or analytics SDK.
- **Required:** use only aggregate App Store analytics and Apple-native crash
  and performance diagnostics.
- **Required:** never collect the contents of users’ cards for analytics or
  support.
- **Required:** working name is “FlashApp”; availability and final spelling must
  be checked before submission.

## Platform scope

- **Required:** native iPhone and iPad application built with SwiftUI.
- **Required:** minimum operating system is iOS/iPadOS 17.
- **Required:** test and distribute the compatible iPad build on Apple Silicon
  Macs.
- **Required:** do not build a dedicated macOS or Mac Catalyst target for the
  first release.
- **Required:** Android is outside the launch scope.
- **Required:** support Italian and English from the first release.
- **Required:** support light, dark, and system-controlled appearance.
- **Required:** support Dynamic Type, VoiceOver, increased contrast, reduced
  motion, and keyboard interaction where appropriate.
- **Deferred:** custom themes, fonts, and card backgrounds.

## Architectural principles

### Local-first operation

- **Required:** the local database is the operational source used by the UI.
- **Required:** personal content and study remain usable without a network
  connection.
- **Required:** synchronization happens automatically when iCloud is available.
- **Required:** an unavailable or disabled iCloud account produces a clear,
  nonblocking state rather than making the personal application unusable.
- **Required:** expose a subtle synchronization status and a manual retry
  action.

### Persistence and CloudKit

Collaboration is a launch requirement. SwiftData’s automatic CloudKit
integration does not cover the required shared-database workflow. Therefore:

- **Required:** use Core Data with `NSPersistentCloudKitContainer`.
- **Required:** use the user’s private CloudKit database for personal content
  and personal study data.
- **Required:** use CloudKit sharing (`CKShare`) and shared record zones for
  collaborative groups.
- **Required:** do not create a proprietary account, password, login, or
  authentication backend.
- **Required:** use the Apple Account/iCloud state already available on the
  device.
- **Required:** use stable UUIDs for domain entities.
- **Required:** persist creation, update, and soft-deletion timestamps.

### Schema evolution

- **Required:** use a versioned Core Data model from the first release.
- **Required:** prefer additive, CloudKit-compatible schema changes.
- **Required:** perform automatic migration only when safe.
- **Required:** never solve a migration failure by deleting the user’s store.
- **Required:** preserve the original data and provide a recovery path when a
  migration fails.
- **Required:** create a recoverable local backup before structural migrations.

## Domain model and ownership boundaries

The specification must preserve the distinction between shared learning
material and private learning progress.

### Content entities

#### Deck

- **Required:** a named collection of notes.
- **Required:** launch with a flat deck structure; no nested decks.
- **Required:** a deck is either personal or assigned to one collaborative
  group.
- **Required:** a deck can move between personal space and a group after
  import.

#### Note

- **Required:** belongs to exactly one deck.
- **Required:** stores the authored source from which one or more review cards
  are generated.
- **Required:** supports plain text and Markdown in textual fields.
- **Required:** stores the original source rather than only rendered output.
- **Required:** authored content is text; attachments accompany it rather than
  replacing it.
- **Required:** support image and audio attachments, referenced from note text
  and stored as content-addressed blobs (ADR-004 §6).
- **Deferred:** video and other attachment kinds.
- **Required:** attachments never replace note identity: a note keeps its uuid
  and its fingerprint when attachments change.

#### Note types

- **Required:** basic front/back note, producing one card.
- **Required:** reversed note, producing forward and reverse cards.
- **Required:** cloze note, producing a card for each cloze group.
- **Required:** use Anki-compatible cloze syntax, such as
  `{{c1::hidden text}}`.
- **Required:** allow a note type to change freely before any generated card has
  study history.
- **Required:** after study begins, conversion creates a duplicate in the new
  type rather than corrupting existing progress.

#### Card

- **Required:** a generated review unit with a stable identity.
- **Required:** each generated card owns an independent FSRS state.
- **Required:** content identity must remain stable enough for collaborators to
  retain private progress when shared content changes.

#### Tag

- **Required:** tags cross deck boundaries.
- **Required:** user-authored names are free-form.
- **Required:** normalized comparison is case-insensitive to prevent duplicates
  such as `Anatomia` and `anatomia`.

### Private study entities

#### Schedule

- **Required:** remains private to one user, including for shared decks.
- **Required:** stores the current FSRS scheduling state for one generated card.

#### ReviewLog

- **Required:** append-only record for every study response.
- **Required:** records time, selected grade, and the FSRS transition needed to
  audit or reconstruct scheduling.
- **Required:** logs from different devices merge rather than overwrite one
  another.
- **Required:** current FSRS state can be recalculated from the ordered history
  when devices review the same card offline.
- **Required:** shared-deck participants never share ReviewLog or Schedule data.

#### ImportBatch

- **Required:** records the source, time, destination, created notes, rejected
  rows, and detected duplicates for one import.
- **Required:** enables an entire import to be undone by moving its notes to the
  trash.

## Spaced repetition

- **Required:** use the maintained
  [`open-spaced-repetition/swift-fsrs`](https://github.com/open-spaced-repetition/swift-fsrs)
  package rather than implementing FSRS manually.
- **Required:** use four grades: Again, Hard, Good, and Easy, localized for the
  UI.
- **Required:** default desired retention is 90%.
- **Required:** do not expose low-level FSRS parameters in the first release.
- **Required:** default deck limits are 20 new cards and 200 reviews per day.
- **Required:** both limits are user-adjustable.
- **Required:** users can undo the most recent response.
- **Required:** users can suspend a card or reset its scheduling.

## CSV contract

### Canonical format

- **Required:** UTF-8 CSV with a header.
- **Required columns:** `type`, `front`, `back`, `tags`.
- **Required type values:** `basic`, `reversed`, `cloze`.
- **Required:** cloze source is stored in `front`.
- **Required:** `back` may contain additional explanation for a cloze note.
- **Required:** multiple tags are separated by semicolons.
- **Required:** destination deck is selected in the application rather than
  encoded in the CSV.

### Import experience

- **Required:** import from Files, Share Sheet, and compatible application
  handoffs.
- **Required:** provide a copyable prompt that asks ChatGPT to generate the
  canonical format.
- **Required:** destination can be a new deck, existing personal deck, or
  collaborative group.
- **Required:** show a preview before committing.
- **Required:** identify invalid rows with actionable explanations.
- **Required:** detect duplicate note content within the destination deck.
- **Required:** skip duplicates by default while allowing explicit import.
- **Required:** create an ImportBatch and permit complete undo.

### Export and recovery

- **Required:** export an individual deck in the canonical CSV format.
- **Required:** export a versioned FlashApp backup containing personal decks,
  notes, FSRS state, review history, settings, and snapshots of shared content.
- **Required:** restore a full FlashApp backup.
- **Required:** restored shared snapshots become personal copies; backups do not
  recreate groups, participants, or permissions.
- **Required:** import an Anki `.apkg`, both container generations, with the
  field mapping confirmed by the user before anything is written (ADR-004).
- **Deferred:** Anki `.apkg` export.

## Collaborative groups

Groups represent classes or study circles, not a single deck.

- **Required:** an owner creates a group and shares an invitation link.
- **Required:** accepting the link adds the participant to the group.
- **Required:** one user may create or join multiple groups.
- **Required:** one group contains multiple decks.
- **Required:** users choose a group during import or move a deck into a group
  later.
- **Required:** group members collaborate on deck, note, and tag content.
- **Required:** the group creator is the technical owner and administrator.
- **Required:** invited members are editors by default.
- **Required:** design the permission model so granular roles can be added
  later.
- **Deferred:** advanced permission-management UI.

### Ownership constraints

- **Required:** make technical ownership understandable without implying that
  every participant owns the CloudKit share.
- **Required:** members may leave a group.
- **Required:** administrators may remove participants.
- **Required:** the technical owner must keep or delete the group; ownership
  transfer must not be promised unless the selected CloudKit design verifies
  it.
- **Required:** before group deletion, warn participants and provide a way to
  copy shared decks into personal space.
- **Required:** leaving a group preserves the user’s private FSRS history as an
  unlinked personal archive.

### Collaborative safety

- **Required:** shared deck and note text has a 30-day version history.
- **Required:** each revision records author and timestamp.
- **Required:** authorized members can restore a previous version.
- **Required:** simultaneous content edits resolve predictably; use the most
  recent `updatedAt` value as the baseline policy unless the specification
  chooses a safer merge that preserves the same product behavior.

## Deletion and recovery

### Trash

- **Required:** deleting a note or deck performs a soft delete by setting
  `deletedAt`.
- **Required:** trashed content is excluded from study and normal library views.
- **Required:** retain content, generated cards, FSRS state, and history for 30
  days.
- **Required:** restoration returns the object and progress to the prior state.
- **Required:** synchronize trash and restoration through CloudKit.
- **Required:** permanently remove expired content and dependent data after 30
  days.
- **Required:** a deck deletion includes its contained notes.

### Delete all data

- **Required:** provide “Delete all my data” separately from the trash.
- **Required:** deletion is immediate and permanent, bypassing the 30-day trash.
- **Required:** use destructive styling and a “Permanent deletion” badge.
- **Required:** explain exactly which local, private CloudKit, and owned shared
  data is affected.
- **Required:** warn separately about effects on group participants.
- **Required:** require two-step confirmation, including typing `ELIMINA`.
- **Required:** offer backup export before deletion.

## Study experience

- **Required:** main “Study now” action.
- **Required:** study one deck or combine all eligible decks.
- **Required:** present due reviews before new cards.
- **Required:** show the prompt, reveal the answer, then present FSRS grades.
- **Required:** preserve an interrupted session and resume it.
- **Required:** completion view shows cards completed and time spent.
- **Required:** show essential metrics: studied today, cards due, 7-day and
  30-day retention, and study streak.
- **Required:** no leaderboards or complex gamification in the first release.

## Note editor

- **Required:** create and edit notes manually.
- **Required:** choose basic, reversed, or cloze type.
- **Required:** Markdown editing and rendered preview.
- **Required:** tools for bold, italic, lists, code, and creating a cloze from
  selected text.
- **Required:** automatic draft saving.
- **Required:** preview the generated review cards.
- **Required:** move and duplicate notes.
- **Required:** bulk tag and organizational actions where they reduce
  repetitive work.

## Navigation and discovery

Use four primary sections:

1. **Today:** due reviews, new cards, streak, and summary statistics.
2. **Library:** personal decks, notes, tags, import, search, and trash.
3. **Groups:** classes, shared decks, participants, and invitations.
4. **Settings:** study behavior, reminders, sync, data, privacy, and help.

Detailed statistics are reached from Today rather than adding a fifth primary
tab.

### Search

- **Required:** local search over deck names, fronts, backs, and tags.
- **Required:** filters for note type, new, due, suspended, personal, and
  shared.
- **Required:** sorting by name, modification time, next review, and card count.
- **Required:** do not send card contents to a search server.

## Onboarding and contextual education

### First launch

- **Required:** a short mandatory tutorial.
- **Required:** explain import, the review interaction, and the four FSRS
  grades.
- **Required:** include a ready-to-study demonstration deck.
- **Required:** avoid accounts, long carousels, and unrelated configuration.

### Feature tutorials

- **Required:** show the Groups tutorial only on first entry to Groups.
- **Required:** explain group creation, invitation links, and sharing decks.
- **Required:** show the Settings tutorial only on first entry to Settings.
- **Required:** contextual tutorials are short, skippable, and replayable from
  Help.
- **Required:** persist tutorial completion state so tutorials do not reappear
  unnecessarily.

## Reminders

- **Required:** use local notifications; no notification backend is needed.
- **Required:** after the first completed study session, ask the user to choose
  a daily reminder time.
- **Required:** request the iOS notification permission only after the user
  chooses to enable reminders.
- **Required:** allow changing the time or disabling reminders in Settings.

## Settings

Settings must provide:

- study limits and behavior;
- reminder time and notification state;
- iCloud synchronization status and recovery guidance;
- import, export, and backup;
- trash;
- light, dark, and system appearance;
- accessibility guidance where useful;
- privacy information;
- support and replayable tutorials;
- permanent data deletion.

## Support and feedback

- **Required:** Help contains tutorials and concise FAQs.
- **Required:** Contact Support opens a prefilled email.
- **Required:** attach diagnostics only after explicit consent.
- **Required:** never attach card content.
- **Required:** request an App Store review only after a positive usage
  milestone.
- **Required:** do not repeatedly nag for ratings.

## Release quality bar

- **Required:** automated tests cover CSV parsing, note-to-card generation,
  FSRS integration, trash behavior, and data migration.
- **Required:** CloudKit integration tests use at least two Apple Accounts and
  multiple devices.
- **Required:** test shared groups, offline edits, conflict resolution, leaving
  groups, and deletion.
- **Required:** test purchase, onboarding, import, study, reminders, backup,
  restoration, and permanent deletion.
- **Required:** verify VoiceOver, Dynamic Type, dark mode, and reduced motion.
- **Required:** test a small and large iPhone, iPad, and Apple Silicon Mac.
- **Required:** perform internal TestFlight testing followed by a small external
  cohort of real students.
- **Required:** do not submit while release-blocking defects remain.

## App Store presentation

- **Required:** screenshots or video must demonstrate the complete
  ChatGPT-to-study journey.
- **Required:** prepare localized Italian and English metadata.
- **Required:** publish a privacy policy consistent with the no-tracking and
  iCloud-only data model.
- **Required:** complete App Privacy declarations from verified implementation,
  not assumptions in this brief.

## Technical verification required during specification

These are validation tasks, not invitations to change the product:

1. Confirm current App Store Connect support for disabling Family Sharing on a
   new paid application.
2. Confirm CloudKit quotas and operational behavior at the expected scale.
3. Validate the exact Core Data store topology for private and shared CloudKit
   databases.
4. Validate moving a deck between personal and group stores while preserving
   stable content identifiers and private progress.
5. Validate invitation acceptance and shared-store handling in a SwiftUI
   application.
6. Define deterministic reconciliation of concurrent ReviewLogs and content
   edits.
7. Define the versioned FlashApp backup schema and migration policy.
8. Confirm the final app name, bundle identifier, category, rating, and price
   tier before submission.

## Explicitly deferred

- Android application.
- Dedicated macOS or Mac Catalyst target.
- Video attachments (images and audio are supported — ADR-004).
- Nested decks.
- Advanced group permission UI.
- Custom visual themes.
- Anki `.apkg` **export** (import is supported — ADR-004).
- Built-in AI generation, PDF import, and Study Agent integration.
- Leaderboards and complex gamification.

Deferred items must not complicate the first release beyond preserving clean
extension boundaries where explicitly required.
