# Log: GAP-06P shared pure Flywheel materialization

Date: 2026-07-25
Area: flywheel

## Summary

Implemented the provider-neutral `study_agent_devkit.flywheel.materialization`
boundary and switched the existing runner profile/brief commands to consume the
shared renderers. The package owns canonical codecs, bounded path/Base64/text
validation, deterministic self-contained run planning, and in-memory manifest
validation. It does not import capability-gap code or perform filesystem,
subprocess, network, model, Git, or worker-dispatch work.

## Files Changed

- `src/study_agent_devkit/flywheel/__init__.py`: public package exports.
- `src/study_agent_devkit/flywheel/materialization.py`: closed v1 value objects,
  renderers, planner, and validator.
- `scripts/flywheel-runner.py`: behavior-preserving shared renderer wiring for
  profile and brief generation.
- `tests/flywheel/`: codec, bounds, tamper, planner, architecture, and direct
  runner characterization coverage.

## Verification

- `pytest -q`: 151 passed.
- `ruff check .`: passed.
- strict mypy with the pinned local harness: passed, 33 source files.
- `scripts/run-runner-smoke.sh`: passed.
- `scripts/check-flywheel.sh`: passed.
- `git diff --check`: passed.
- Independent semantic review: approved.
- Independent architecture audit: accepted.
- GitHub Actions CI run `30166565551`: passed on Python 3.12 and 3.13,
  including tests, Ruff, mypy, wheel build, clean-wheel import, and pinned
  harness provenance.

## Notes

- The direct runner retains its existing command semantics and output shape;
  dynamic profile dates are supplied by the CLI while the shared planner is
  deterministic.
- Legacy runner compatibility is available only through a private trusted
  adapter. Manifest bytes cannot select it, and the exported validator always
  applies strict promotion rules.
- GAP-06 resolution, persistence, promotion, and filesystem sink behavior are
  intentionally not included; those remain GAP-06A/B work.
