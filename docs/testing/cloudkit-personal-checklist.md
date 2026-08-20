# Personal CloudKit sync checklist

This checklist is the human-gated evidence plan for the version 1.0 private store. It
must be run with the same Apple Account on two supported devices, using the exact signed
build under review. Fixture tests and a local Core Data store do not close these cells.

No cell below has been executed by the implementation worker. Until primary evidence is
attached, each remains both `HUMAN_REQUIRED` and `UNVERIFIED`; submission stays blocked.

| Cell | Device 1 | Device 2 | Expected evidence | Status |
| --- | --- | --- | --- | --- |
| Private container and production schema | Sign in to the release Apple Account; launch and create a deck | Sign in to the same account; launch the same build | Private `Private.sqlite` store loads and the production schema is deployed | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Offline authoring and study | Disable network; create/edit notes, answer cards, and quit | Keep the app offline; relaunch and read the same local content | Local authoring/study remains complete with no account/network | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Reconnect and convergence | Make an edit while offline, reconnect, wait for export | Open after reconnect and wait for import | Both devices show the same deck, note, media, schedule, and review history | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Conflict convergence | Edit the same note and answer the same card offline | Make a different edit/answer offline | Reconnect both; deterministic merge is stable after relaunch on both devices | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Media propagation | Add a supported media attachment and reconnect | Wait for import and open the card | Attachment bytes render on the second device and survive relaunch | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Relaunch and token resume | Force-quit during/after sync, then relaunch | Relaunch after the first device reconnects | Pending history resumes without duplicate logs or lost content | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Soft-delete propagation | Trash a deck/note and reconnect | Wait for import and inspect trash | Soft deletion reaches the second device and remains recoverable | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Restore propagation | Restore the trashed deck/note and reconnect | Wait for import and inspect the library | Restoration reaches the second device with progress intact | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Permanent erasure propagation | Use “Delete all my data”, complete both confirmations, reconnect | Wait for import and relaunch | Local and private CloudKit data are permanently erased on both devices | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Sign out and same-account return | With account A loaded, sign out and inspect Anonymous; sign back into A | N/A | A content is hidden while signed out and the same isolated A profile returns without implicit merge | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Apple Account A → B boundary | Create uniquely identifiable non-sensitive fixtures in A, then switch the device to B | Inspect B and CloudKit Dashboard metadata for both accounts | No A fixture appears locally or remotely in B; A remains intact when revisited | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Anonymous transfer consent | Author locally while signed out, sign in, choose “Not now”, then explicitly transfer | Open the same account on device 2 | Nothing exports before consent; explicit transfer is media-complete, source-preserving and idempotent | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Legacy upgrade quarantine | Upgrade a build containing the pre-ADR-007 global store | Inspect active account, Legacy recovery and source files | Legacy data is local-only, never auto-attached to an account, and original files remain recoverable | `HUMAN_REQUIRED` / `UNVERIFIED` |
| Pending identified erasure | Start erase for A, interrupt connectivity/sign out, then return to A | Observe the second device after reconnect | Pending deletion is not reported complete early and eventually propagates only within A | `HUMAN_REQUIRED` / `UNVERIFIED` |

Record the build number, OS/device pair, Apple Account (without credentials), container
identifier, timestamps, and screenshots/log metadata in the release evidence ledger. Do not
record card text in diagnostics. A failed cell is `FAIL`, not a reason to weaken the local
first behavior or to replace the store.
