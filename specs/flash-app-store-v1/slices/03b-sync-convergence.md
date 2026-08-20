# Slice 03B — Truthful sync and deterministic convergence

## Contract unlocked

Within the already-routed identified profile, sync state is truthful, remote history is
recoverable and deterministic, and processing failures never disable local authoring.

## Required remediation

- Refresh account state at lifecycle start; availability alone never means up-to-date.
- Track overlapping setup/import/export event identity and surface processor failures.
- Quarantine corrupt/stale cursors and replay idempotently from nil before checkpoint.
- Reconcile cards for changed notes; union review logs by UUID; revoked-only history resets
  stale schedules; malformed identities never win destructive deduplication.
- Preserve checkpoint-before-prune ordering and retryable cleanup.
- Wire the public retry into Settings with actionable EN/IT failure guidance.

## Verification

Behavior tests cover genuine Core Data token relaunch/resume, corrupt/empty/stale cursors,
crash-before-checkpoint, shuffled logs, identical/divergent duplicate UUIDs, revoked logs,
changed-note conflicts, malformed entities, overlapping events and debounced failure. The
complete prior correctness/security finding list must receive independent approval.

## Human boundary

Same-account devices, A→B during active import/export, both private databases, schema and
deletion propagation stay `HUMAN_REQUIRED / UNVERIFIED`.
