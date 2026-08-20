# FlashApp — Architecture and Product Constraints

Status: approved product brief for specification work  
Purpose: source of truth for Claude/Fable and implementation planning

## Owner amendments — App Store version 1.0 (2026-08-19 / 2026-08-20)

ADR-006 supersedes conflicting launch requirements below:

- version 1.0 includes automatic personal iCloud sync through one active private Core Data
  store selected from isolated anonymous/Apple-Account/legacy profiles;
- collaborative Groups, CloudKit sharing, and the shared store are deferred beyond 1.0;
- primary navigation is Today, Library, and Settings; Import remains inside Library and
  Statistics is reached from Today;
- the paid launch price is €2.99, changed manually to €4.99 one month after launch;
- onboarding is short and skippable and still leaves a generalist demo deck available;
- backups include referenced media bytes and restore by safe, idempotent merge;
- internal TestFlight is required; an external cohort is not a 1.0 gate;
- submission is blocked until personal CloudKit sync is proven end-to-end;
- Apple-account operations remain human-required and unverified until evidence exists.

ADR-007 supersedes ADR-006's global-store clauses: the current CloudKit user identity is
resolved before loading an account store; account A and B never share a profile directory;
anonymous/legacy workspaces are local-only and require an explicit validated copy into an
iCloud profile; cold indeterminate identity opens Anonymous rather than cached account data.

See `docs/decisions/ADR-006-app-store-v1-contract.md`,
`docs/decisions/ADR-007-account-scoped-stores.md`, and the
`flash-app-store-v1` run for the implementation and evidence contracts.

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

- **Required:** paid download at €2.99 at launch, changed manually to €4.99 one
  calendar month after the actual launch date.
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
- **Required:** on a cold launch where Apple Account identity cannot be proven, open the
  anonymous local workspace rather than exposing a cached identified-account library.
- **Required:** an already-open identified workspace remains usable during an ordinary
  network outage that does not signal an account change.

### Persistence and CloudKit

Personal CloudKit synchronization is a launch requirement. Collaboration is
deferred beyond 1.0. Therefore:

- **Required:** use Core Data with `NSPersistentCloudKitContainer`.
- **Required:** use the user’s private CloudKit database for personal content
  and personal study data.
- **Deferred:** use CloudKit sharing (`CKShare`) and shared record zones for
  collaborative groups.
- **Required:** do not create a proprietary account, password, login, or
  authentication backend.
- **Required:** use the Apple Account/iCloud state already available on the
  device.
- **Required:** resolve the opaque CloudKit user identity before loading an identified
  production store and isolate each Apple Account in its own profile directory.
- **Required:** load at most one profile store; sign-out selects Anonymous, A→B selects B,
  and returning to A reopens A without implicit merging or deletion.
- **Required:** raw CloudKit identity, derived fingerprint, email and account name are never
  displayed or logged. Routing uses a device-keyed opaque fingerprint.
- **Required:** anonymous and provenance-unknown legacy content remains local-only until the
  user explicitly copies a fully validated, media-complete snapshot into the current iCloud
  profile.
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

Version 1.0 stores personal learning material and private learning progress in the private
store. The distinction from future shared material is deferred with Groups.

### Content entities

#### Deck

- **Required:** a named collection of notes.
- **Required:** launch with a flat deck structure; no nested decks.
- **Required for 1.0:** every deck is personal.
- **Deferred:** assigning or moving a deck to a collaborative group.

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
- **Required:** content identity remains stable across personal edits and multi-device
  synchronization.

#### Tag

- **Required:** tags cross deck boundaries.
- **Required:** user-authored names are free-form.
- **Required:** normalized comparison is case-insensitive to prevent duplicates
  such as `Anatomia` and `anatomia`.

### Private study entities

#### Schedule

- **Required:** remains private to one user.
- **Required:** stores the current FSRS scheduling state for one generated card.

#### ReviewLog

- **Required:** append-only record for every study response.
- **Required:** records time, selected grade, and the FSRS transition needed to
  audit or reconstruct scheduling.
- **Required:** logs from different devices merge rather than overwrite one
  another.
- **Required:** current FSRS state can be recalculated from the ordered history
  when devices review the same card offline.
- **Deferred:** shared-deck participant behavior.

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
- **Required for 1.0:** destination can be a new or existing personal deck.
- **Deferred:** collaborative-group destinations.
- **Required:** show a preview before committing.
- **Required:** identify invalid rows with actionable explanations.
- **Required:** detect duplicate note content within the destination deck.
- **Required:** skip duplicates by default while allowing explicit import.
- **Required:** create an ImportBatch and permit complete undo.

### Export and recovery

- **Required:** export an individual deck in the canonical CSV format.
- **Required:** export a versioned FlashApp backup containing personal decks,
  notes, FSRS state, review history, settings, and every referenced supported media byte.
- **Required:** restore a full FlashApp backup.
- **Deferred:** shared snapshots, groups, participants, and permissions are outside the
  1.0 backup format.
- **Required:** import an Anki `.apkg`, both container generations, with the
  field mapping confirmed by the user before anything is written (ADR-004).
- **Deferred:** Anki `.apkg` export.

## Collaborative groups — deferred beyond version 1.0

Groups represent classes or study circles, not a single deck.

Every `Required` clause in this section is a requirement for the future Groups release,
not version 1.0. No 1.0 task or release gate depends on this section.

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
- **Required:** explain exactly which local and private CloudKit data is affected.
- **Required:** deletion names the active profile only. Identified-account deletion remains
  pending until CloudKit export succeeds; inactive account and anonymous profiles are not
  implicitly deleted.
- **Deferred:** warnings about effects on group participants.
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

Use three primary sections in version 1.0:

1. **Today:** due reviews, new cards, streak, and summary statistics.
2. **Library:** personal decks, notes, tags, import, search, and trash.
3. **Settings:** study behavior, reminders, sync, data, privacy, and help.

Detailed statistics are reached from Today rather than adding a fifth primary
tab.

### Search

- **Required:** local search over deck names, fronts, backs, and tags.
- **Required:** filters for note type, new, due, suspended, and personal.
- **Required:** sorting by name, modification time, next review, and card count.
- **Required:** do not send card contents to a search server.

## Onboarding and contextual education

### First launch

- **Required:** a short, skippable tutorial.
- **Required:** explain import, the review interaction, and the four FSRS
  grades.
- **Required:** include a ready-to-study demonstration deck.
- **Required:** avoid accounts, long carousels, and unrelated configuration.

### Feature tutorials

- **Deferred:** show the Groups tutorial only when Groups ships.
- **Deferred:** explain group creation, invitation links, and sharing decks.
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
- **Required:** personal CloudKit integration tests use the same Apple Account on
  multiple devices and cover offline edits, reconnect, convergence, and deletion.
- **Required:** account-boundary tests cover sign-out, return to the same account, A→B during
  pending import/export, cold indeterminate identity, legacy quarantine, explicit anonymous
  transfer and inspection of both accounts' private CloudKit records.
- **Deferred:** shared-group, invitation, leaving, ownership, and group-deletion tests.
- **Required:** test purchase, onboarding, import, study, reminders, backup,
  restoration, and permanent deletion.
- **Required:** verify VoiceOver, Dynamic Type, dark mode, and reduced motion.
- **Required:** test a small and large iPhone, iPad, and Apple Silicon Mac.
- **Required:** perform internal TestFlight testing. An external cohort is not a
  version 1.0 release gate.
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
3. Validate the exact private Core Data/CloudKit store topology for version 1.0.
4. **Deferred with Groups:** validate moving a deck between personal and group stores.
5. **Deferred with Groups:** validate invitation acceptance and shared-store handling.
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
