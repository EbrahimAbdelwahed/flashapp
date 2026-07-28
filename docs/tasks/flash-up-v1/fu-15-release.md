# Task Bead: fu-15-release Audit, validate, and submit Flash Up v1

Status: Open
Priority: P0
Type: manual-release
Depends On: fu-10-settings-onboarding, fu-14-guidance-and-erasure
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

The localized, accessible app has documented device/account QA, App Store configuration, TestFlight evidence, and a completed submission.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B0.5
- B9.1
- B9.2
- B9.3

## Grilling Evidence

- Release decisions require the human Apple Developer account holder and verified production behavior.

## Worker Profile

create ios-release-governor

Rationale:

Release audit is a specialized evidence-and-human-operations role, not feature implementation.

## Context

Release criteria cannot be inferred from tests; they are a final manual verification and publication lane.

## What To Do

- Complete App Store Connect checklist, localization/a11y audits, device and sharing matrix, TestFlight rounds, metadata, privacy, and submission evidence.

## Likely Files / Packages

- ci/
- docs/testing/
- docs/decisions/ADR-004-appstore.md
- App/Resources/

## Acceptance Criteria

- [ ] B0.5 and B9.1–B9.3 stop conditions hold.
- [ ] No release blockers remain and submission is recorded.

## Verification

- `l10n-check`: expected to pass or produce documented output
- `Accessibility matrix`: expected to pass or produce documented output
- `Release matrix`: expected to pass or produce documented output
- `TestFlight and App Store checklist`: expected to pass or produce documented output

## Out Of Scope

- New feature work or silent scope changes.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
