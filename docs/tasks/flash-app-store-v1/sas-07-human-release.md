# Task Bead: sas-07-human-release Execute human Apple-account and submission gates

Status: Open
Priority: P0
Type: manual-release
Depends On: sas-06-quality-evidence
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

The exact signed and processed build is submitted only after real CloudKit, archive, TestFlight, metadata and legal evidence makes every required gate PASS.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-04
- AC-10
- Slice 07

## Grilling Evidence

- Owner requires CloudKit E2E and forbids agent-created PASS for account operations.

## Worker Profile

reuse app-store-release-governor

Rationale:

The release governor records evidence while the human account holder performs external mutations.

## Context

This task is expected to remain HUMAN_REQUIRED until membership and identifiers are active.

## What To Do

- Configure/verify team, App ID, bundle/container, schema, legal URLs, signing and price schedule; archive/validate/upload; execute same-account CloudKit including deletion propagation, internal TestFlight, iPhone/iPad, and Apple-Silicon-Mac iPad-app matrices; complete App Store Connect and submit only with explicit authorization.

## Likely Files / Packages

- Config/
- docs/testing/
- docs/reviews/
- docs/decisions/worklog.md

## Acceptance Criteria

- [ ] Every required gate has primary evidence from the exact build.
- [ ] The €2.99 to €4.99 schedule is tied to actual launch date.
- [ ] Any absent evidence remains HUMAN_REQUIRED and blocks GO.

## Verification

- `Signed entitlement/profile dump`: expected to pass or produce documented output
- `Validate App result`: expected to pass or produce documented output
- `CloudKit same-account device checklist incl. deletion propagation`: expected to remain HUMAN_REQUIRED until real evidence
- `Processed internal TestFlight iPhone/iPad/Apple-Silicon-Mac smoke matrix`: expected to remain HUMAN_REQUIRED until real evidence
- `ASC checklist`: expected to pass or produce documented output

## Out Of Scope

- New feature work, inferred PASS, push/publish/submission without explicit owner authorization.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
