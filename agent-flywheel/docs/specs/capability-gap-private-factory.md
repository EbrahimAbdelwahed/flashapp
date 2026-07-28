# Capability-gap private factory implementation

Status: Done
Date: 2026-07-25
Canonical public contract: `study-agent-harness` commit
`e74c4da9c737f97dd460c606dbb7afcc66137b84`

## Goal

Implement the private half of the approved capability-gap loop without granting
the tutor, imported data, or an optional transport any engineering authority.
The devkit consumes the harness's exact redacted outbox contract; it never
redefines that codec.

## Dependency graph

```text
GAP-05A public outbox (done)
  -> GAP-05B private import/reproduction
     -> GAP-05C immutable proposal/decision
        -> GAP-06 maintainer resolution/promotion
           -> GAP-07 adversarial local closure
              -> GAP-08 optional accepted-only GitHub draft pull request (done)
```

`GAP-04B` is implemented in the public harness as the separately optional,
local PDF-to-Markdown adapter. `GAP-05D` and `GAP-07B` remain deferred because
they require concrete transport/authentication and hosted-deployment decisions.

## GAP-05B contract

### Package boundary

- New private package: `study_agent_devkit.capability_gap`.
- It imports `GapOutboxBundle` and related closed types from the pinned
  `study-agent-harness`; no codec or enum is copied.
- The public harness must never import this package.
- Default tests are offline and make no model, Flywheel, GitHub, shell, or
  network call.

### Trusted import context

- Remote intake receives only a host-authenticated, already-derived
  64-character `delivery_import_id` and the expected bundle fingerprint. It
  never receives sender scope. The importer treats the ID only as an
  idempotency key and compares the trusted expected fingerprint with the
  fingerprint of the validated bytes.
- Local file intake derives the equivalent ID exactly as
  `sha256(b"study-agent-devkit-local-delivery-v1\0" + b"local-file\0" +
  bundle_fingerprint.encode("ascii")).hexdigest()`.
- The devkit never receives or persists sender scope. The delivery import ID is
  stored only in the operational delivery row and is absent from candidate,
  reproduction, proposal, and decision evidence.

### Validation and transaction boundary

1. Parse `GapOutboxBundle.from_bytes(payload)`.
2. Require byte-for-byte canonical roundtrip and
   `OUTBOX_SCHEMA_VERSION == 2`; do not use the historical V1 aliases.
3. Compute and compare the bundle fingerprint with the trusted import context
   before opening a write transaction.
4. Start one SQLite `BEGIN IMMEDIATE` transaction.
5. Claim the delivery ID with its exact bundle fingerprint.
6. If the same claim already committed, return its persisted canonical
   `ImportReceiptV1` bytes without invoking active-work or reproduction
   callbacks. If the ID is bound to different bytes, fail.
7. For each record, verify an existing candidate with the same claimed gap key
   has identical closed dimensions and operation kind; otherwise fail the whole
   transaction.
8. Add one contribution per record and link exact active-work matches.
9. Commit delivery, candidate, contribution, link, and reproduction rows
   atomically.

No partial candidate is visible after validation failure, collision, process
loss before commit, or fixture failure.

### Candidate aggregation

- `deliveries` binds delivery ID to bundle fingerprint and the exact persisted
  canonical import receipt. `ImportReceiptV1` contains exactly
  `schema_version=1`, `bundle_fingerprint`, and sorted
  `candidate_gap_keys`; it contains no delivery identity or duplicate flag.
- `candidates` binds the claimed gap key to exact canonical redacted dimension
  bytes.
- `contributions` uses an internal delivery primary-key foreign key, has a
  unique `(delivery_pk, gap_key)` key, and stores the complete canonical
  redacted record as received. It never repeats the textual delivery import ID.
- `reproductions` is one-to-one with a contribution. `candidate_active_work`
  contains only exact informational links.
- Candidate identity is the imported `GapKeyV1` claim plus exact redacted
  dimensions; imported key binding is integrity evidence, not authentication.
- Different delivery IDs may contribute once each to the same candidate.
- A contribution preserves the imported occurrence count and bounded time
  range. Candidate totals are deterministic sums/min/max of contributions.
- Occurrence totals are never materialized in SQLite `INTEGER`; the canonical
  records retain arbitrary-size Python integers within the outbox payload limit,
  and snapshots derive sum/min/max in Python.
- Candidate snapshots preserve every closed redacted contribution and
  reproduction result without delivery identity.
- Different requested operation kinds never merge, even when their target
  family is similar.
- Active work is a trusted, immutable snapshot of closed `spec|bead`
  references injected through a narrow `ActiveWorkIndex` protocol. Only exact
  gap-key links are automatic; links never suppress contributions.

### Offline reproduction

- A `ReproductionRegistry` owns a closed allowlist of fixture IDs and trusted
  typed callbacks registered by exact closed dimensions. It is an allowlist and
  authority boundary, not a process sandbox.
- Handlers receive only a parsed redacted record. They cannot receive a path,
  command, source body, sender scope, or delivery ID.
- A handler returns only `reproduced|not_reproduced` plus a SHA-256 evidence
  digest; the registry supplies the fixture ID.
- Missing fixtures record `not_reproducible_from_export`, no fixture ID, and no
  evidence digest.
- Handler exceptions fail the import transaction; retry remains safe.

### Persistence

- SQLite schema version 1 with foreign keys enabled.
- Tables: `deliveries`, `candidates`, `contributions`,
  `candidate_active_work`, and `reproductions`.
- Candidate evidence APIs expose immutable typed snapshots and never expose
  delivery IDs or sender scope.
- All externally supplied strings are closed enums, fixed digests, or bounded
  opaque identifiers. SQLite statements are parameterized.

## GAP-05B acceptance

- Hostile, noncanonical, unknown-schema, key-collision, delivery-collision, and
  fixture-failure inputs mutate nothing.
- Exact retry is byte-for-byte idempotent across process restart.
- Exact retry after restart returns the persisted receipt and invokes neither
  active-work nor reproduction callbacks.
- Two trusted delivery IDs for one bundle contribute independently once.
- A multi-record bundle whose later fixture fails rolls back every record.
- A process-kill/reopen probe and two concurrent imports prove atomic recovery
  and one committed contribution per delivery.
- A canonical bundle with an occurrence count larger than SQLite's signed
  integer range imports and aggregates without truncation.
- Same target family with different operation kinds remains separate.
- Active work links are exact and informational; no approved spec/bead, goal,
  code, dependency, issue, network effect, or dispatch is created.
- Architecture tests prove the dependency direction and absence of network,
  subprocess, arbitrary path, Flywheel, and GitHub imports in the package.

## GAP-05C through GAP-07 boundaries

- GAP-05C may consume only immutable GAP-05B candidate snapshots. It will create
  deterministic draft proposals and unresolved decisions, never approved work.
- GAP-06 will require a separately authenticated maintainer authority and a
  compare-and-set resolution. Only `accepted` may materialize reviewed
  Flywheel inputs; merge, release, deploy, and GitHub remain excluded.
- GAP-07 adds no new production authority. It is an adversarial offline closure
  over the completed local chain.

## GAP-08 completion

The optional accepted-only GitHub branch and draft pull-request sink is
implemented under the approved contract in
`docs/specs/capability-gap-github-draft-pr.md`. Exact commit
`ac884212eb05b5ca916bd6b2345ec4d77b5dbf3a` passed GitHub Actions run
[30205827258](https://github.com/EbrahimAbdelwahed/study-agent-devkit/actions/runs/30205827258)
on Python 3.12 and 3.13 with 317 tests, Ruff, strict mypy, wheel and
clean-wheel import checks, and Flywheel smoke.

## Verification

- Focused pytest contract/integration/security tests.
- Ruff and strict mypy over source and tests.
- Package build and clean-wheel import.
- Python 3.12 and 3.13 GitHub Actions.
- `pyproject.toml` pins `study-agent-harness` to exact commit
  `e74c4da9c737f97dd460c606dbb7afcc66137b84`; CI and clean-wheel tests verify
  the installed contract commit rather than relying on an untagged `0.2.0`.
- Independent architecture/security review before GAP-05B is marked done.

## Completion

The local GAP-05B through GAP-07 chain and the optional GAP-08 GitHub sink are
implemented, independently reviewed, and covered by offline tests. The
remaining optional hosted transport beads (`GAP-05D` and `GAP-07B`) remain
deferred pending their explicit product and authority decisions. The public
harness owns the completed local `GAP-04B` converter boundary.
