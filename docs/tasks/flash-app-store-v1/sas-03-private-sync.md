# Task Bead: sas-03-private-sync Implement automatic personal CloudKit sync

Status: Open
Priority: P0
Type: task
Depends On: sas-02-persistent-library
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

Private-store changes have truthful account/offline status, retry, persistent-history processing and deterministic convergence hooks; real E2E evidence remains human-gated.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-03
- AC-04
- AC-10
- Slice 03

## Grilling Evidence

- Submission delays if CloudKit E2E is not proven; mocks cannot close account gates.

## Worker Profile

reuse app-store-data-engineer

Rationale:

Sync tokens, store events and schedule replay depend directly on the foundation owner's decisions.

## Context

The code can be built and fixture-tested before account activation, while schema/device evidence stays unverified.

## What To Do

- Implement SyncMonitor, account-state mapping, retry, event/status handling, history tokens, remote processing, deduplication and schedule replay hooks.
- Keep the release store configured for private CloudKit before load; prove account changes do not replace its URL or lose locally-created content.
- Add the domain-facing `LibraryRepository.retrySync()` seam and production composition wiring.
- Prepare a same-account device checklist including soft-delete/restore/permanent-erasure propagation without claiming it executed.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/Sync/
- Packages/FlashUpKit/Sources/FlashUpData/Persistence/
- Packages/FlashUpKit/Sources/FlashUpDomain/Repositories/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- App/AppEnvironment.swift
- docs/testing/cloudkit-personal-checklist.md

## Acceptance Criteria

- [ ] Fixture tests prove token resume, retry, offline behavior and deterministic replay.
- [ ] Content created under a no-account fixture survives availability change and becomes export-eligible without store replacement.
- [ ] Retry is publicly callable and never fabricates a successful status.
- [ ] No card text reaches logs.
- [ ] Container/schema/device cells remain HUMAN_REQUIRED until evidence exists.

## Verification

- `Focused sync/history tests`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `Manual checklist remains UNVERIFIED`: expected to pass or produce documented output

## Out Of Scope

- App Store signing/schema deployment, Groups/CKShare, feature UI beyond composition wiring.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
