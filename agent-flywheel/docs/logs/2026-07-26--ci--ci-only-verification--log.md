# Log: CI-only verification

Date: 2026-07-26
Area: CI

## Summary

Made GitHub Actions the sole executable verification environment for the
devkit. The workflow already owned pytest, Ruff, mypy, package build, pinned
harness checks, and clean-wheel import; it now also owns the deterministic
flywheel scaffold, validator, and runner smoke suite.

## Files Changed

- `.github/workflows/ci.yml`: runs `scripts/check-flywheel.sh` once on the
  Python 3.13 matrix leg.
- `AGENTS.md`: forbids local execution of verification commands and requires a
  green workflow for the exact commit.
- `README.md` and `docs/operations.md`: distinguish CI gates from operational
  commands and optional environment diagnostics.

## Verification

- No verification commands were executed locally, by policy.
- GitHub Actions for the published commit is the acceptance gate.

## Notes

- The first CI run exposed that the GitHub Ubuntu image did not provide
  `ripgrep`; the Python 3.13 leg now installs it before the flywheel smoke.
- `scripts/run-core-tools-smoke.sh` remains a manual diagnostic because `br`,
  `bv`, and Agent Mail are external binaries that are not version pinned or
  installed by the workflow.
