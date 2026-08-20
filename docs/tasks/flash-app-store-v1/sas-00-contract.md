# Task Bead: sas-00-contract Freeze the App Store 1.0 contract and run

Status: Open
Priority: P0
Type: contract
Depends On: none
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

ADR-006, amended source-of-truth documents, canonical slices, a validated Flywheel graph, and an explicit human-gate ledger govern all later work.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-10
- Slice 00

## Grilling Evidence

- Owner decisions recorded on 2026-08-19 and accepted in ADR-006.

## Worker Profile

none needed

Rationale:

This is an orchestrator-owned governance pass; implementation workers must not reinterpret it.

## Context

The prior graph conflicts with the approved launch scope and is stale relative to implemented mock behavior.

## What To Do

- Amend brief/spec and ADR-004, create ADR-006, materialize the feature spec/slices/run, mark conflicting old group work superseded, and validate dispatch artifacts.

## Likely Files / Packages

- flash-up-architecture-brief.md
- flash-up-implementation-spec.md
- docs/decisions/
- docs/specs/
- specs/flash-app-store-v1/
- docs/flywheel-runs/flash-app-store-v1/
- docs/tasks/flash-app-store-v1/
- docs/worker-briefs/flash-app-store-v1/

## Acceptance Criteria

- [ ] No 1.0 task depends on Groups, a shared store, mandatory onboarding, reference-only backups or an external cohort.
- [ ] Every Apple-account gate is HUMAN_REQUIRED/UNVERIFIED.
- [ ] assets/emma-avatar is untouched.

## Verification

- `Flywheel validate --stage spec`: expected to pass or produce documented output
- `Flywheel validate --stage dispatch`: expected to pass or produce documented output
- `Scoped semantic review`: expected to pass or produce documented output

## Out Of Scope

- Application implementation, Apple account operations, remote publishing.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
