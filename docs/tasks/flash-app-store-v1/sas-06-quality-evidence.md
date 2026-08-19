# Task Bead: sas-06-quality-evidence Build the App Store quality and evidence gates

Status: Open
Priority: P0
Type: audit
Depends On: sas-05-release-surface
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

All locally provable release gates have repeatable evidence and every external gate is explicitly HUMAN_REQUIRED/UNVERIFIED.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-09
- AC-10
- Slice 06

## Grilling Evidence

- No UNKNOWN P0 may be re-labeled PASS; archive-derived privacy/entitlement claims wait for the exact archive.

## Worker Profile

create app-store-release-governor

Rationale:

Release matrices, CI, privacy, licenses and evidence need one skeptical owner rather than feature implementers self-certifying.

## Context

Current CI is iPhone/iOS 17.4-centric and no privacy/license/release matrix is complete.

## What To Do

- Extend automated matrices without losing defaults; audit privacy/required-reason/network/logging/dependencies/licenses/import hardening; populate localization/accessibility/device/release ledgers.
- Prepare archive-dependent commands without claiming execution.

## Likely Files / Packages

- ci/
- Config/
- docs/testing/
- docs/legal/
- docs/reviews/
- App/Resources/

## Acceptance Criteria

- [ ] All non-human matrix cells have evidence or honest FAIL.
- [ ] No secret, placeholder legal claim, unsupported accessibility claim or inferred archive PASS remains.
- [ ] Existing default coverage is preserved.

## Verification

- `ci/test.sh`: expected to pass or produce documented output
- `l10n check`: expected to pass or produce documented output
- `release matrix inspection`: expected to pass or produce documented output
- `Semantic release review`: expected to pass or produce documented output

## Out Of Scope

- Signing, App Store Connect mutation, feature expansion, remote publishing.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
