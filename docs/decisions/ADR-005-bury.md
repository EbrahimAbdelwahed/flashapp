# ADR-005 — Burying a card: a second user flag on the schedule

Status: Accepted
Date: 2026-08-11
Bead: study card actions (extends `fu-06-study-engine`, `fu-09-today-study-ui`)
Deciders: implementation agent; owner approved the scope.

## Context

Spec §A11.3 already requires a card context menu in the reviewer offering *Suspend*, *Reset*
and *Edit note*. `LibraryRepository.setSuspended` and `resetCard` were implemented in
`fu-06-study-engine` but never wired to any UI, so the menu was the missing half.

Burying — hiding a card for the rest of the day, the way Anki does — was **not** in the
spec at all. It is the action a learner actually wants when a card is merely inconvenient
right now: suspension is too permanent, and answering it dishonestly corrupts the schedule.
It matters most with `reversed` and `cloze` notes, where meeting the sibling card ten seconds
after the one that prompted the action is precisely the annoyance.

Adding it required the first change to the schedule attribute set since §A2 was written.

## 1. Decision: `buriedUntil: Date?` on `ReviewState`

A single optional date next to `suspendedAt`:

```swift
public var suspendedAt: Date?
public var buriedUntil: Date?
```

A card is buried while `buriedUntil > now`. `StudySessionModel` sets it to the start of
tomorrow.

**No unbury pass ever runs.** The expiry is evaluated at read time, in
`QueueCandidate.isBuried(at:)`, so a buried card returns to the queue by itself when the
date passes. The alternatives were worse:

| Option | Why not |
| --- | --- |
| A `Bool` plus a "buried on" date | Two fields encoding one fact, and the day boundary logic then has to live at every read site instead of in the value. |
| A scheduled job or launch-time sweep | A background pass that mutates schedules is a merge conflict generator under CloudKit, and it makes the queue depend on having been launched. |
| Reuse `dueAt`, pushing it a day | Destroys the FSRS interval. Burying is a display choice, not an answer, and must never touch the scheduler's numbers. |

## 2. Consequence for `fu-04-data-core`

`CDSchedule` as described in spec §A2 gains one attribute:

| Attribute | Type | Optional | Default |
| --- | --- | --- | --- |
| `buriedUntil` | Date | yes | nil |

It lives in the private store alongside `suspendedAt`, is relationship-free like the rest of
`CDSchedule`, and needs no migration today because the Core Data stack does not exist yet.
`BackupSchedule` already carries it as an optional, so backups written before this change
still decode with `buriedUntil == nil`.

Note for whoever implements the store: **suspension and burial are not scheduling output.**
Every write that replaces a schedule with one the engine produced has to carry them across.
In the domain this is `ReviewState.carryingUserFlags(from:)`, and the persistent repository
must do the equivalent in `record` and in the replay after an undo.

## 3. Three latent bugs this uncovered

All three predate burying and were fixed alongside it, because a second flag — and the tests
written for it — made them reachable rather than merely theoretical.

**A schedule is not evidence that a card was studied.** Hiding a card the user has never
seen has to be recorded somewhere, and that somewhere is a schedule carrying nothing but the
flag. Every "is this card new?" test asked whether a schedule existed, so such a placeholder
turned the card into a review that was already overdue — it left the New count and entered
the due queue without ever having been answered. The question is now
`ReviewState.isUnseen` (`state == .new && reps == 0 && lastReviewedAt == nil`), and
`QueueBuilder.build` sends new cards to the second pass even when a placeholder gives them a
date in the past.

Under suspension alone the bug was reachable only by suspending a new card and then
un-suspending it; burial made it reachable with no second user action at all, because the
flag expires on its own and leaves the placeholder behind.

**The queue order was not total.** `QueueBuilder` sorted due cards by `dueAt` alone and new
cards by (`noteCreatedAt`, `templateKey`). `sorted` is not stable in Swift and the candidates
arrive from a dictionary, so cards that tied came out in a different order on every launch —
and, once two devices hold the same collection, in a different order on each of them. Both
sorts now fall back to the card uuid, the same device-independent rule `ScheduleReplayer`
already uses to make replay reproducible. This is our own ordering code and does not touch
the pinned FSRS engine, which only ever computes one card's interval.

**Undo un-suspended cards silently.** `LibraryStore.rebuildSchedule` dropped the schedule
whenever a replay left no surviving answers, taking the user's flag with it. Answering a
suspended card and then undoing that answer therefore un-suspended it. The schedule is now
kept as a flag-only placeholder whenever the user has hidden the card
(`setScheduleWithoutHistory`), and `resetCard` follows the same rule: a reset discards
history, and suspension is not history.

## 4. What is deliberately not undoable

The reviewer's Undo covers answering, suspending and burying. It does **not** cover *Reset
progress* or *Delete note*:

- undoing a reset would need an API to un-revoke specific logs, which is a new persistence
  surface for a rare action that is already behind a confirmation dialog;
- a deleted note goes to the Trash, which is the existing and better recovery path.

Both are confirmation-gated instead. Undo remains single-step, as the brief specifies.

## 5. Evidence

- `Packages/FlashUpKit/Tests/FlashUpDomainTests/QueueBuilderTests.swift` — burial excludes a
  card from the queue and from both counts; it expires without intervention; suspension
  outlasts an expired burial; a card hidden before it was ever studied comes back as new and
  not as due; user flags survive a scheduler-produced state; every permutation of candidates
  that tie produces the same queue.
- `Packages/FlashUpKit/Tests/FlashUpDataTests/StudyActionsTests.swift` — burying a note hides
  its siblings and lets them back in; burial survives `record` and the replay after
  `revokeLastAnswer`; un-suspending a never-studied card leaves no schedule behind;
  `cardInfo` excludes revoked logs and orders newest first.
- `FlashUpUITests/UserFlowUITests.swift` — suspending from the actions menu removes the card
  and Undo puts it back; the card info sheet opens from the menu.

## 6. Follow-ups

- Flags (Anki's coloured bookmarks) were considered and deliberately left out: they need a
  persisted field, a `SearchFilters` case and Library UI, which is a batch of its own.
- Haptics on these commit-level moments are still absent app-wide
  (`docs/ux-principles.md` §4); adding them here alone would be inconsistent.
- `SearchFilters.State` has no `buried` case. If the Library should be able to list buried
  cards, that is a small follow-on.
