# ADR-003 — FSRS engine: pinned version, mapping and determinism

Status: Accepted
Date: 2026-07-28
Bead: `fu-03-fsrs-spike` (source bead B0.4)
Deciders: implementation agent; owner sign-off required only for the deviation in §2.

## Context

Spec §A6.1 requires the `open-spaced-repetition/swift-fsrs` package, pinned to an exact
version, wrapped behind an `FSRSService` protocol so that no other file imports it. The
schedule storage in §A2 and the multi-device replay in §A6.4 both depend on the engine
being deterministic and on knowing exactly which of its fields have to be persisted.

## 1. The latest release cannot be used

`swift-fsrs` has exactly two tags: `v4.1.0` and `v5.0.0`. In **v5.0.0 the scheduler API is
`internal`**: the types are `public` but `FSRS.init(parameters:)`, `FSRS.next(...)`,
`FSRS.repeat(...)` and `FSRSParameters.init(...)` are not. An importing module can build a
`Card` and read `Rating`, and can do nothing else.

Verified by compiling a probe package against `exact: "5.0.0"`:

```
error: 'FSRS' initializer is inaccessible due to 'internal' protection level
error: incorrect argument label in call (have 'requestRetention:', expected 'from:')
```

The second error is the giveaway: the only reachable `FSRSParameters` initialiser is the
synthesised `Codable` one. Desired retention — the single parameter the brief pins — cannot
be set.

The access levels were fixed on `main` after the tag: commit
`4fbaf20184d62f82a9f44f343337c61a2c5483e9` (2026-05-25) declares `next`, `repeat`,
`getRetrievability`, `rollback`, `forget`, `reschedule`, the initialisers and the model
properties `public`, and adds `Sendable` conformances. **No release has been tagged since.**

## 2. Decision: pin the commit, not the tag

```swift
.package(
    url: "https://github.com/open-spaced-repetition/swift-fsrs.git",
    revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9"
)
```

This is a deviation from §A6.1's "pinned to an exact version" only in letter: a revision pin
is strictly more exact than a tag, and `Package.resolved` records it. The alternatives were:

| Option | Why not |
| --- | --- |
| Stay on `v5.0.0` | The engine cannot be driven at all. Not viable. |
| Vendor the sources into the repo | Takes on permanent maintenance of algorithm code and silently forks it; §0.2's dependency list exists to avoid exactly this. |
| Reimplement FSRS-5 in `FlashUpDomain` | Same maintenance cost plus the risk of a subtly wrong algorithm in the product's core promise. |

**Consequence to accept:** we depend on unreleased code. The mitigation is that
`SwiftFSRSAdapter` is the only file that imports it, so moving to a future tag is a one-line
change plus a re-run of this bead's tests. `fu-15-release` must re-check whether a release
tag has appeared before submission.

## 3. Pinned configuration

| Setting | Value | Why |
| --- | --- | --- |
| Algorithm version | **v5** | Selected implicitly by the 19-element default weight vector (`FSRSAlgorithmVersion.detect`: 21 elements would select v6). v5 matches the `CDSchedule` field set in §A2. |
| Weights `w` | library defaults (19 values) | Brief: no user-facing parameter tuning. |
| `requestRetention` | **0.90** | Spec §A6.1. |
| `enableFuzz` | **false** | Critical. Fuzz randomises each interval per call, which would make §A6.4 replay produce different schedules on different devices. It happens to default to `false` at this commit; the adapter sets it explicitly so a future default change cannot silently break replay. |
| `enableShortTerm` | library default (`true`) | Gives the sub-day learning steps that the study UI captions ("<10 min"). |

## 4. Mapping tables

Domain raw values are what `CDReviewLog.gradeRaw` and `CDSchedule.stateRaw` persist. They
are deliberately identical to the library's raw values, so stored history survives an engine
swap.

| `Grade` (domain) | raw | swift-fsrs `Rating` | UI (en / it) |
| --- | --- | --- | --- |
| `.again` | 1 | `.again` | Again / Di nuovo |
| `.hard` | 2 | `.hard` | Hard / Difficile |
| `.good` | 3 | `.good` | Good / Buono |
| `.easy` | 4 | `.easy` | Easy / Facile |

`Rating.manual` (raw 0) is deliberately unmapped: Flash Up never issues it, and the engine
throws on it.

| `ScheduleState` (domain) | raw | swift-fsrs `CardState` |
| --- | --- | --- |
| `.new` | 0 | `.new` |
| `.learning` | 1 | `.learning` |
| `.review` | 2 | `.review` |
| `.relearning` | 3 | `.relearning` |

## 5. What has to be persisted (input to `fu-04-data-core`)

The scheduler recomputes `elapsedDays` from `lastReview` and the review time
(`AbstractScheduler` overwrites the incoming value) and produces `scheduledDays` as output.
Therefore a `Card` handed back to the engine only needs `due`, `stability`, `difficulty`,
`reps`, `lapses`, `state` and `lastReview`.

**The `CDSchedule` attribute set in §A2 is sufficient for deterministic replay. No new
attribute is required** — provided the v5 algorithm stays selected. FSRS-6 adds a
`learningSteps` counter to the card that v5 does not use; adopting v6 later would require a
schema migration, which is why the version is pinned here rather than left to the default
weight vector.

## 6. Evidence

`Packages/FlashUpKit/Tests/FlashUpDomainTests/SwiftFSRSAdapterTests.swift`, 12 tests,
all passing:

- desired retention defaults to 0.90;
- folding a grade sequence twice yields an identical state, and two independent adapter
  instances agree — the determinism requirement of §A6.4;
- a first answer leaves `.new`, sets `reps = 1`, `lastReviewedAt`, and schedules forward;
- `Again` on a review card increments `lapses` and moves it to `.relearning`;
- preview returns four outcomes ordered Again ≤ Hard ≤ Good ≤ Easy, works for unseen cards,
  and does not commit — the previewed outcome equals the state produced by actually
  answering with that grade;
- a lower desired retention schedules further out (0.70 vs 0.90);
- persisted raw values match the table in §4.

Reference values from the probe, for a new card at a fixed instant with retention 0.90 and
fuzz off: Again 1 min, Hard 5 min, Good 10 min, Easy 16 days. After `good, good`, the next
interval is 4 days at retention 0.90 and 20 days at 0.70.

## 7. Follow-ups

- `fu-15-release`: re-check for a tagged release that includes the public API and, if one
  exists, move the pin from the revision to the tag.
- `fu-06-study-engine`: `ScheduleReplayer` folds non-revoked logs sorted by
  (`reviewedAt`, `uuid`) through `FSRSService.next` — deliberately out of scope here.
