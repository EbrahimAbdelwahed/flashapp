# GAP-06P: Shared pure Flywheel materialization planner

Status: Done
Priority: P1
Depends on: GAP-05C

## Goal

Extract the minimum pure render/parse/validation boundary required to turn
approved proposal artifacts into a normal dispatch-stage-valid Flywheel run.
Both the existing CLI and GAP-06 promotion adapter must use the same code.

## Constraints

- Allowed production files:
  `src/study_agent_devkit/flywheel/materialization.py`, additive package init,
  and minimal behavior-preserving replacements in
  `scripts/flywheel-runner.py`.
- Allowed tests: new characterization/unit tests for the shared functions and
  existing runner smoke adjustments only when behavior remains unchanged.
- Shared API is exactly `render_worker_profile`, `render_worker_brief`,
  `plan_run`, and `validate_materialization_plan`.
- Behavior-preserving prefactor with existing runner smoke green.
- No shell, subprocess, `br`, Git, network, model, or worker spawn in the pure
  module.
- No copied control-plane logic and no accepted-promotion behavior in this bead.
- Pure planning fails on placeholders, missing sections, draft status,
  unsupported profile directives, or incomplete task contracts.
- Direct `python scripts/flywheel-runner.py ...` invocation and clean-wheel
  package imports remain supported.

## Done

- Characterization and adversarial tests pin rendering, validation, tamper
  resistance, and legacy-runner compatibility.
- The CLI consumes the shared renderers and private trusted compatibility
  adapter; the exported validator always enforces strict promotion semantics.
- Local smoke/full gates are green, and independent semantic and architecture
  review approved the implementation.

## Verification

- `python -m pytest -q tests/flywheel`
- `scripts/run-runner-smoke.sh`
- `scripts/check-flywheel.sh`
- Ruff, strict mypy, build, and clean-wheel import
