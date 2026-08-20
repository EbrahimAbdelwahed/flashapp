# Task Bead: sas-03a-account-routing Isolate production stores by Apple Account

Status: Open
Priority: P0
Type: task
Depends On: sas-02-persistent-library
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

Identity preflight opens exactly one recoverable Anonymous, Legacy or identified profile with every sidecar isolated.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-01
- AC-02
- AC-03
- AC-04A
- Slice 03A

## Grilling Evidence

- ADR-007 resolves the A-to-B data boundary with account-scoped stores.

## Worker Profile

reuse app-store-data-engineer

Rationale:

The existing Data owner controls store lifecycle, media/session paths and AppEnvironment ownership.

## Context

No CloudKit-backed store may load before identity is resolved; legacy provenance is unknown.

## What To Do

- Implement identity resolver, Keychain-backed HMAC fingerprint, recoverable profile catalog and generation-checked AccountStoreCoordinator.
- Scope Core Data/media/session/history/recovery, compose one owner, and clone old global data into Legacy local-only with verified originals.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/AccountStores/
- Packages/FlashUpKit/Sources/FlashUpData/Persistence/
- Packages/FlashUpKit/Sources/FlashUpData/Media/
- Packages/FlashUpKit/Sources/FlashUpData/Repositories/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- App/AppEnvironment.swift

## Acceptance Criteria

- [ ] Identity resolves before store load.
- [ ] Anonymous/Legacy have nil CloudKit options and A/B have distinct private paths.
- [ ] Only one profile owner is open and no sidecar crosses profiles.
- [ ] Catalog/key failure enters recovery.
- [ ] Legacy clone preserves originals and never attaches CloudKit.
- [ ] Raw identity/fingerprint/path reaches no log/UI/default/export.
- [ ] Real account cells remain HUMAN_REQUIRED.

## Verification

- `Focused routing/adoption/failure tests`: expected to pass or produce documented output
- `swift test`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `ci/lint.sh`: expected to pass or produce documented output

## Out Of Scope

- Remote convergence remediation, archive transfer, visible UI, Apple operations, assets/emma-avatar/.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
