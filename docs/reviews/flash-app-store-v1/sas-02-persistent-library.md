# Review: sas-02-persistent-library

Date: 2026-08-19
Verdict: APPROVED
Baseline: `25843bc`

## Evidence

- Independent full SwiftPM run: 264 tests in 29 suites passed.
- Worker `ci/test.sh`: package/lint checks and 20 UI tests passed, including recovery,
  concurrent retry and media-initialization failure routes.
- Worker Release simulator matrix: iPhone 15 and iPad Pro 11-inch (M4), iOS/iPadOS 17.4,
  both built successfully. SwiftLint reported zero violations; `git diff --check` passed.
- Correctness reviewer: APPROVED after verifying immutable V1/current V2 migration,
  lossless review-log relaunch, valid restored progress and one-owner storage lifecycle.
- Security/data-safety reviewer: APPROVED after verifying typed failures, targeted writes,
  forced conflict retry, deterministic malformed/duplicate handling, media integrity,
  aggregate erasure and DEBUG-only test composition.

## Accepted behavior

- Production composes one persistent `CoreDataLibraryRepository` and durable
  `FileMediaStore`; in-memory implementations remain explicit preview/test adapters.
- `LibraryRepository` operations surface typed failures. No failed read/write is presented
  as an empty or successful result.
- Core Data mutations touch intended aggregates only, preserve unrelated/unknown rows and
  retry proven optimistic conflicts from a fresh context.
- Baseline V1 is immutable, V2 is current, and real V1 bytes migrate on a local staged copy
  before adoption. Failed/corrupt stores retain verified recovery artifacts.
- Content, scheduling, full previous review state, settings, import/trash, demo seed and
  device-local session behavior survive relaunch. Restore maps legacy card identities before
  writing dependent schedules/logs.
- Recovery retry serializes ownership, closes old coordinators, cannot leak a partial owner
  after media failure, and exposes root-level retry/raw-export/support actions.

## Deliberately open

- `sas-03` owns CloudKit history/status/retry and convergence behavior. Real account,
  container/schema and multi-device evidence remains `HUMAN_REQUIRED`.
- `sas-04` owns the complete media archive and production backup/restore port/UI path.
- Signing, Archive, TestFlight, App Store Connect and device gates remain unverified.
