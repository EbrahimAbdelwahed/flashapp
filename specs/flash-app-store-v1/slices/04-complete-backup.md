# Slice 04 — Complete backup and merge-safe restore

## Contract unlocked

A `.flashupbackup` archive independently restores personal content, study progress,
settings and every supported referenced media byte without overwriting live records.

## API seam and ownership

`BackupManifest` remains portable Domain data. `BackupArchiveService` in Data owns archive
layout, staging, media hashing, atomic export and transaction orchestration. `MediaStore`
remains the single blob owner. A Domain `BackupArchiveServicing` port is injected by
`AppEnvironment`; Settings may consume only this port. This slice owns the port, Data
implementation, composition wiring, and removal of the legacy direct JSON export path.

## Runnable artifact

Export a fixture with image and audio, wipe an isolated destination, restore, render both
assets, then restore the same archive again and observe a zero-additions summary.

## Verification

- Manifest and every media hash/reference validate before repository mutation.
- Valid round-trip preserves bytes, UUIDs, schedules, logs and settings.
- Duplicate restore is idempotent and never overwrites live UUIDs.
- Unknown version, truncation, missing blob, hash mismatch and decompression limits produce
  typed errors and zero partial changes.
- Export uses a temporary destination and atomic finalization.
- A composition test proves the production Settings dependency resolves to the archive
  service, not the legacy `BackupDocument` JSON path.

## Must stay green

Existing CSV/`.apkg` import, media content addressing and reference rendering.

## Feedback that changes this slice

If archive format choices materially affect interoperable backups or size limits, update
ADR-006/backup-format docs before committing the public format.
