# FlashApp backup format 3

Status: Accepted for version 1.0
Authority: ADR-006
File extension: `.flashupbackup`

## Container

The file is a ZIP32 archive using stored entries only. Version 1.0 adds no compression
dependency. Encrypted entries, ZIP64, data descriptors, duplicate paths, absolute paths,
`..` components, symlinks, and compression methods other than `stored` are rejected.

The archive contains exactly:

```text
manifest.json
media/<lowercase-sha256>
```

`manifest.json` is UTF-8 JSON with `format = "flashup-backup"` and
`formatVersion = 3`. It contains app/build version, UTC export time, settings, personal
decks/notes/cards/tags, schedules, append-only review logs, and media records:

```json
{"id":"UUID","sha256":"lowercase hex","byteCount":123,"mimeType":"image/png","path":"media/<sha256>"}
```

There is no group or shared-snapshot representation. Demo and trashed content are not
exported.

## Limits

- archive bytes: 2 GiB
- manifest bytes: 256 MiB
- media entries: 20,000
- one media entry: 64 MiB
- total uncompressed media bytes: 2 GiB
- total entries: 20,001

The reader enforces all limits before allocation or mutation.

## Export contract

Export writes to a temporary sibling file, streams and hashes each media blob, verifies
that every manifest reference has one matching entry, validates the completed archive,
then atomically replaces the destination. Failure leaves neither a partial destination nor
modified library state.

## Restore contract

Restore parses, bounds-checks, hashes, and stages the entire archive before opening a
write transaction. It then performs a non-destructive merge:

- an existing object UUID wins and is never overwritten;
- review logs append only when their UUID is absent;
- schedules are inserted only when absent, then deterministic replay reconciles state;
- media are content-addressed by SHA-256 and deduplicated;
- a second restore of the same archive adds nothing;
- any validation, staging, or transaction failure makes zero observable mutations.

Legacy JSON formats 1 and 2 may be imported only when they contain no media references.
A legacy document with media references is rejected with `legacyBackupMissingMedia`.
Unknown major versions are rejected with a localized newer-version error.

Any future layout or merge-policy change requires a new format version and an ADR.
