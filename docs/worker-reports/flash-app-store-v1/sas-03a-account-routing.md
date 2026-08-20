# Worker Report: sas-03a-account-routing

Status: complete (review remediation handoff; semantic review pending)
Run ID: `flash-app-store-v1`
Task: `docs/tasks/flash-app-store-v1/sas-03a-account-routing.md`
Brief: `docs/worker-briefs/flash-app-store-v1/sas-03a-account-routing.md`
Agent: Luna
Reported: 2026-08-20

## Files Changed

- `Packages/FlashUpKit/Sources/FlashUpData/AccountStores/AccountStoreCoordinator.swift`
- `Packages/FlashUpKit/Sources/FlashUpData/Persistence/PersistenceController.swift`
- `Packages/FlashUpKit/Sources/FlashUpData/Media/FileMediaStore.swift`
- `Packages/FlashUpKit/Sources/FlashUpData/Repositories/CoreDataLibraryRepository.swift`
- `Packages/FlashUpKit/Sources/FlashUpData/Sync/RemoteChangeProcessor.swift`
- `Packages/FlashUpKit/Tests/FlashUpDataTests/AccountStoreRoutingTests.swift`
- `App/AppEnvironment.swift`

The working tree also contains pre-existing rejected SAS-03 sync files and other concurrent
changes; they were not reverted or claimed by this worker.

## Behavior Implemented

- Production `AppEnvironment` now consumes a generation-bound transition stream, exposes
  bootstrapping/switching states, revokes ports fail-closed during transitions, and atomically
  installs the ready library/media bundle. Bootstrap/retry is single-flight and non-reentrant.
- `AccountStoreCoordinator` owns one active profile, generation-checks transitions, observes
  `CKAccountChanged` centrally, applies an immediate write fence, and closes the previous Core
  Data/media owner before replacement. Superseded transitions cannot publish stale owners.
- Anonymous, identified Apple Account, and Legacy profiles use separate `Private.sqlite`,
  media, session, history/recovery paths. Identified profiles alone receive private CloudKit
  options.
- Apple Account record names are reduced to HMAC-SHA256 fingerprints using a non-synchronizable,
  device-only Keychain secret. Raw identity/path values are not exposed in the public bundle,
  logs, defaults, UI or exports.
- Missing/corrupt catalog or a missing key for existing account profiles enters typed recovery;
  a replacement key is never silently generated.
- Pre-ADR-007 global store files are inventoried and cloned into a local-only Legacy profile with
  SQLite/WAL/SHM, Recovery, media, session and history sidecars plus byte/digest and inventory
  verification; originals remain in place and the cloned Legacy profile is selected.
- Keychain query/add are separate operations; duplicate-add recovery rereads exactly 32 bytes.
- Closing a profile removes observers and cancels history/debounce tasks; stale references cannot
  read the previous profile's media bytes after account routing.

## Verification Commands and Outcomes

- `swift test --package-path Packages/FlashUpKit --filter 'FlashUpDataTests.AccountStoreRoutingTests'`:
  PASS, 9/9 routing tests, including A→B→Anonymous→A, cold indeterminate, catalog/key,
  Legacy recovery, and generation-supersession coverage.
- `swift test --package-path Packages/FlashUpKit`: PASS, 286 tests / 34 suites.
- `./ci/lint.sh`: PASS, 0 violations / 141 files.
- `xcodebuild build -project FlashUp.xcodeproj -scheme FlashUp -configuration Debug
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.4' ... CODE_SIGNING_ALLOWED=NO`:
  PASS, `BUILD SUCCEEDED`.
- `./ci/test.sh`: PASS on the lifecycle-remediated tree, SwiftLint 0/141, SwiftPM 286/286,
  simulator UI 21/21, `** TEST SUCCEEDED **`, and `All checks passed`. The subsequently
  applied retry single-flight refactor was recompiled and linted separately. The previously
  observed `NSInternalInconsistencyException: Invalid parameter not satisfying: bundleIdentifier
  != nil` teardown crash was not reproduced after lifecycle cleanup.
- `git diff --check`: PASS.
- Real Apple Account, signed build, CloudKit container/schema, A→B/same-account and device
  sidecar evidence: `HUMAN_REQUIRED / UNVERIFIED` (not marked PASS).

## Open Questions or Blockers

- The real-device account transition and CloudKit framework ordering remain
  `HUMAN_REQUIRED / UNVERIFIED`. A signed A→B run must inspect both private databases and verify
  no cross-account export; no Apple/account gate is marked PASS.
- Semantic/security review should confirm the account-scoped lifecycle boundary before 03B; no
  remote convergence behavior was changed here.
- The authoritative remediation list remains
  `docs/reviews/flash-app-store-v1/sas-03a-account-routing.md`; semantic re-review is required.

## Follow-up Beads Needed

- `sas-03b-sync-convergence`: integrate account-scoped routing with truthful history/event
  processing, retry visibility, and account-bound sync lifecycle; remains out of scope here.
- Human release gate: execute signed real-device account and CloudKit matrix; do not infer PASS
  from these local fixtures.
