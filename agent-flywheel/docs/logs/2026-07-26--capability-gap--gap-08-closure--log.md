# Log: GAP-08 closure

Date: 2026-07-26
Area: capability-gap

## Summary

Closed the accepted-only GitHub branch and draft pull-request capability gap
against the approved contract. GitHub remains an optional technical sink and
does not gain merge, release, deployment, issue, or engineering authority.

## Files Changed

- `docs/tasks/GAP-08.md`: marked the task done and recorded its exact approved
  behavior source and CI evidence.
- `docs/specs/capability-gap-github-draft-pr.md`: marked the approved contract
  done and recorded completion evidence.
- `docs/specs/capability-gap-private-factory.md`: removed stale GAP-04B/GAP-08
  deferrals while preserving the deferred hosted transport beads GAP-05D and
  GAP-07B.

## Verification

- Exact commit `ac884212eb05b5ca916bd6b2345ec4d77b5dbf3a`.
- [GitHub Actions run 30205827258](https://github.com/EbrahimAbdelwahed/study-agent-devkit/actions/runs/30205827258): green on Python 3.12 and 3.13 with 317 tests, Ruff, strict mypy, wheel/clean-wheel import, and Flywheel smoke.
- Local executable checks were not run, as forbidden by repository policy.

## Notes

- Approved behavior source: `docs/specs/capability-gap-github-draft-pr.md`.
- No source, test, dependency, CI, API, architecture, or product behavior was
  changed by this documentation closure.
