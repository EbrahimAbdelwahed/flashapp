# GAP-06B: Idempotent local Flywheel promotion adapter

Status: Done
Priority: P1
Depends on: GAP-06A

## Goal

Materialize one accepted promotion job into the existing validated Flywheel run
layout and optional authorized goal artifact, without creating task state,
spawning, or publishing.

## Allowed files

- `src/study_agent_devkit/capability_gap/local_flywheel_promotion.py`
- additive receipt/protocol contracts in
  `src/study_agent_devkit/capability_gap/resolution_contracts.py`
- additive private claim/receipt operations in
  `src/study_agent_devkit/capability_gap/resolution_store.py`
- additive materialization methods in
  `src/study_agent_devkit/capability_gap/resolution_service.py`
- additive public exports in
  `src/study_agent_devkit/capability_gap/__init__.py`
- focused adapter/integration tests and fixture projects
- this task/spec and one log

## Forbidden

- rewriting or copying the runner
- changing the resolution database schema, indexes, or version
- source-code mutation in target projects
- `br`, dispatch packets, worker spawn, Codex goal API, Git/GitHub, merge,
  release, deployment
- any output for rejected/deferred/duplicate resolutions

## Done

- Accepted-only, gate-preserving, path-safe, process-loss/idempotency contract
  passes offline end to end.
- Existing runner smoke and all full gates remain green.
- Independent integration, semantic, and security review is clean.
