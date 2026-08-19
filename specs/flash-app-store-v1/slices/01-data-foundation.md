# Slice 01 — Versioned private-store foundation

## Contract unlocked

`FlashUpData` can open, close and reopen one versioned, CloudKit-compatible
`Private.sqlite` without losing or deleting original files on failure.

## API seam and ownership

`PersistenceController` owns model loading, store description, local/CloudKit options,
contexts and lifecycle. `MigrationRecovery` owns pre-migration file copies and recovery
artifacts. No view imports these types.

## Runnable artifact

An isolated on-disk store harness creates representative entities, closes, reopens and
reads them. A corrupt-store fixture enters recovery while leaving original bytes intact.

## Verification

- Programmatic model lint enforces CloudKit-compatible attributes/relationships/defaults.
- On-disk reopen and in-memory test configuration pass.
- Persistent history and remote-change options are present on the single description.
- Corrupt/migration failure preserves `Private.sqlite`, WAL and SHM and never invokes a
  delete-store repair.
- Account/container checks are recorded `UNVERIFIED`, not simulated PASS.

## Must stay green

All pure-domain, import/media and existing repository oracle tests.

## Feedback that changes this slice

A real CloudKit schema limitation creates a decision request and stops widening the model.

