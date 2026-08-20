# Semantic review: sas-03a-account-routing

Status: BLOCKED
Date: 2026-08-20
Reviewers: independent correctness reviewer; independent security/data-loss reviewer

## Blocking findings

1. Account-change transitions discard the new bundle, so `AppEnvironment` retains the
   closed previous repository/media ports and can leave old content mounted.
2. A newly cloned Legacy profile is never selected; upgrade can present a blank Anonymous
   library while preserving but hiding the user's prior data.
3. Bootstrap is reentrant and can publish `transitionSuperseded` as a false storage failure;
   there is no explicit bootstrapping/write-fenced application state.
4. Legacy cloning does not carry the existing Recovery tree and therefore fails its own
   exact-root verification when recovery artifacts exist.
5. Keychain add attributes reuse lookup-only keys, the duplicate branch can return an
   unpersisted secret, and adapter failure modes lack coverage.
6. Repository observers/tasks are not cancelled by `close()`, and account-change has no
   immediate write fence. The required `ci/test.sh` gate crashes before UI tests.
7. The alleged transition test resolves `.noAccount` both times; it does not exercise
   A→B, sign-out, return-to-A, cold indeterminate, catalog/key failure, legacy recovery or
   superseded generations.

## Required remediation

- Publish a generation-bound transition stream to `AppEnvironment`; enter bootstrapping or
  switching fail-closed, revoke old ports/writes, then atomically install the new bundle.
- Make Legacy an active local-only route until explicit transfer; clone and verify the full
  agreed sidecar/recovery inventory without altering originals.
- Separate Keychain lookup/add dictionaries; accept duplicate only after successful exact
  32-byte reread.
- Cancel all repository observers/tasks during close and centralize account-change ownership.
- Add deterministic account/race/failure fixtures and make `ci/test.sh` complete through UI.

Apple-account, signed-build, CloudKit schema/device and live A→B checks remain
`HUMAN_REQUIRED / UNVERIFIED`.

## Re-review 1

Status remains BLOCKED after the first remediation. Resolved: Keychain add/duplicate
handling, Recovery/WAL/SHM inventory, observer teardown and a real local A→B→Anonymous→A
fixture. Residual blockers:

- `FlashUpApp` does not unmount `RootTabView` during bootstrapping/switching, and feature
  `@State` models retain the previous profile's repository/content after bundle replacement.
- A failed persistent-store close clears its fence; session sidecar operations are not
  lifecycle-gated and the media port is not sealed before close, allowing stale A access.
- Legacy verification mishandles the historical external `Application Support/Media` path.
- Legacy is hidden for signed-in/indeterminate upgrades instead of becoming the active
  quarantined local profile pending explicit transfer.
- Bootstrap joiners await bundle creation but not atomic installation; catalog-corruption,
  close-failure and AppEnvironment lifecycle fixtures are missing.
