# GAP-05C immutable proposal and decision contract

Status: Done
Date: 2026-07-25
Depends on: GAP-05B at
`dc2d0048e1411e28db84d3d4f8c3f6e4575f57da`

## Goal

Freeze one redacted GAP-05B candidate, or one explicitly reviewed cohort, into
one immutable technical proposal and one unresolved maintainer decision request.
This slice asks for authority; it cannot grant, resolve, promote, dispatch, or
publish anything.

## Risk classification

High. GAP-05C introduces public devkit contracts, a new persistence schema, and
an authority boundary. It therefore requires plan review, bounded
implementation, independent adversarial tests, semantic review, and security
review before closure.

## Dependency and authority boundary

- Input is only a complete immutable `CandidateSnapshot` from GAP-05B.
- A draft builder is trusted behavior-layer code. It receives frozen redacted
  proposal evidence, never a store, delivery identity, sender scope, path,
  command, credential, network client, Flywheel client, or GitHub client.
- The package has no model/provider dependency. A skill, playbook, human
  workflow, or model adapter may implement the builder outside this package.
- GAP-05C persists only draft artifacts and an unresolved decision request.
- There is no resolution API, approved artifact, goal, bead mutation, dispatch,
  dependency installation, subprocess, network, GitHub, repository merge,
  release, or deployment surface.

## Frozen cohort

`ProposalEvidenceV1` owns the canonical ordered candidate evidence and derives
its unique GAP-05B gap-key tuple. There is no separately constructible cohort
object.

- One key needs no merge authority.
- More than one key is default-deny and requires an injected
  `CohortMergeAuthority`. Its `authorize(candidate_gap_keys)` method returns
  either `None` or a `CohortMergeReceiptV1` containing exactly the requested
  sorted keys and a bounded opaque `review_id`.
- The authority is trusted host workflow code. The builder cannot receive or
  invoke it and cannot create a valid multi-key proposal by returning text.
- `merge_review_fingerprint` is derived internally as
  `sha256(b"study-agent-devkit-gap05c-merge-review-v1\0" +
  canonical_json_bytes({"candidate_gap_keys": [...], "review_id": ...}))`.
  It is integrity evidence for the host receipt, not cryptographic proof.
- A gap key may belong to at most one persisted proposal. A maintainer merge
  must therefore happen before any member receives a proposal.
- Format similarity, target-family similarity, model output, occurrence count,
  or active-work links never imply cohort equivalence.

## Frozen evidence

Before invoking merge authority or builder, the service validates and
canonicalizes every candidate snapshot. After a successful multi-key
authorization, it constructs `ProposalEvidenceV1` with exactly
`schema_version`, `candidates`, and `merge_review`. `merge_review` is null for a
single key; otherwise it has exactly `candidate_gap_keys`, `review_id`, and the
internally derived `merge_review_fingerprint`. Each candidate object has exactly:

- `gap_key`, `dimensions`, `contributions`, `occurrence_count`, `first_seen`,
  `last_seen`, and `active_work`;
- each contribution has exactly `record_b64` and `reproduction`;
- `record_b64` is RFC 4648 standard Base64 with required padding and must decode
  and re-encode byte-identically to the complete canonical redacted record;
- reproduction has exactly `status`, `fixture_id`, and `evidence_digest`;
- deterministic occurrence total and first/last-seen timestamps;
- active-work entries have exactly `kind` and `work_id`.

Dimensions use the exact public `GapOutboxDimensions.to_json()` field set.
Timestamps use UTC RFC 3339 with exactly six fractional digits and `Z`.
Candidates sort by gap key; contributions sort by decoded canonical record
bytes and then canonical reproduction-object bytes; active-work sorts by
`(kind, work_id)`.

`cohort_fingerprint` is a
domain-separated SHA-256 over canonical
`{"candidate_gap_keys": [...], "merge_review_fingerprint": <hex-or-null>}`
bytes using prefix `b"study-agent-devkit-gap05c-cohort-v1\0"`.
`evidence_fingerprint` is SHA-256 of the complete canonical
`ProposalEvidenceV1` bytes using prefix
`b"study-agent-devkit-gap05c-evidence-v1\0"`. Delivery identity and sender
scope are structurally absent.

The ordered gap-key tuple, not `cohort_fingerprint`, is the lookup/idempotency
identity. The fingerprint identifies the frozen cohort plus its merge-review
evidence and is verified as an indexed projection.

The first committed evidence remains immutable even if later imports add
contributions to the GAP-05B aggregate. A later request containing a gap key
already assigned to a proposal returns that proposal only when the requested
cohort is identical; otherwise it fails with a cohort collision.

## Draft builder contract

`ProposalDraftBuilder` receives only `ProposalEvidenceV1` and returns a closed
`ProposalDraftV1` with exactly `schema_version`, `options`,
`recommended_option_id`, `artifacts`, `verification`, `non_goals`, and
`requested_authority`:

- two to five uniquely identified `ProposalOptionV1` values, each with exactly
  `option_id`, `summary`, and one or more `tradeoffs`;
- one recommended option ID present in that option set;
- `DraftArtifactV1` values with exactly `kind`, `artifact_id`, `artifact_state`,
  `body`, and `depends_on`;
- exactly one `adr`, exactly one `spec`, and one or more `bead` artifacts;
- every `artifact_state` is structurally fixed to `draft`; ADR/spec
  dependencies are empty and bead dependencies are limited to returned bead IDs
  and acyclic;
- one or more deterministic verification statements;
- one or more explicit non-goals;
- exact `RequestedAuthority`:
  `planning_only|planning_and_implementation_goal`.

Only `ProposalDraftV1` has a schema-version field; option and artifact objects
do not. Draft artifacts are bounded UTF-8 engineering text. They are untrusted,
non-executable data even though the builder is
trusted behavior-layer code: artifact IDs are opaque logical IDs, never paths,
and no file is created. Unknown fields, C0/C1 controls other than newline/tab,
invalid UTF-8, oversized content, duplicate IDs, dependency cycles, missing
recommendations, and empty required sections fail before persistence.

The builder runs before the SQLite write transaction. A builder exception or
invalid draft mutates nothing. A concurrent first creation may invoke two
builders, but exactly one package commits; the losing caller returns the exact
persisted package for the identical cohort. A normal exact retry after commit
does not invoke the builder.

`RequestedAuthority` describes only the action being requested from the future
maintainer decision. Neither enum value grants authority in GAP-05C.

## Immutable package

`ImprovementProposalV1` contains exactly:

- `schema_version`, `proposal_id`, `cohort_fingerprint`,
  `evidence_fingerprint`, `evidence`, `draft`, and `created_at`.

`proposal_id` is a domain-separated SHA-256 of the canonical proposal body
excluding the ID itself, with prefix
`b"study-agent-devkit-gap05c-proposal-v1\0"`.
There is no separate proposal fingerprint: `proposal_id` is the proposal
content hash and all references use it.

`MaintainerDecisionRequestV1` contains exactly:

- `schema_version`, `decision_id`, `proposal_id`, `requested_authority`,
  `status`, and `created_at`.

`decision_id` is a domain-separated SHA-256 of the canonical request body
excluding the ID, with prefix
`b"study-agent-devkit-gap05c-decision-v1\0"`. Status is structurally fixed to
`unresolved`, and its timestamp equals the proposal timestamp.
`ProposalDecisionPackageV1` has exactly `schema_version`, `proposal`, and
`decision`. Every decode requires byte-for-byte canonical roundtrip and
recomputes cohort/evidence/proposal/decision fingerprints and all cross-links.
The package bytes are the sole canonical persistence record; no redundant
package fingerprint is stored.

The trusted clock must return a timezone-aware value. It is normalized to UTC
and encoded with exactly six fractional digits and `Z`.

## Bounds

Candidate count, per-candidate/total contribution count, active-work count, and
candidate-byte bounds are checked before merge authority, builder, clock, or
write. The final evidence bound is checked after merge authorization but before
builder:

- at most 16 candidates;
- at most 256 contributions per candidate and 256 total contributions;
- at most 256 active-work references per candidate and 256 total references;
- at most 512 KiB canonical bytes per candidate;
- at most 1 MiB of canonical proposal-evidence bytes.

Builder output is checked before clock or write:

- two to five options, at most eight tradeoffs per option;
- one ADR, one spec, and one to 64 beads;
- at most 64 dependencies per bead;
- one to 64 verification statements and one to 64 non-goals;
- opaque IDs match `^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$`;
- each text value at most 16 KiB UTF-8, total canonical draft at most 512 KiB;

After reading the trusted clock and before opening a write transaction, the
complete canonical package must be at most 2 MiB. Every schema-version field is
the exact integer `1`; booleans are rejected.

Text is preserved exactly; no Unicode normalization is performed. It must be
UTF-8 encodable and may contain tab and line feed, but no other Unicode
`Cc`/`Cs` code points. Exceeding any limit is a closed validation failure and
mutates nothing.

## Persistence

Use a separate SQLite database and `SQLiteProposalStore`; do not change the
reviewed GAP-05B schema.

Schema version 1 contains only:

- `proposal_packages`: internal PK, unique indexed `proposal_id`,
  `decision_id`, and `cohort_fingerprint`, plus the sole canonical
  `package_bytes`;
- `proposal_members`: one row per gap key, with `UNIQUE(gap_key)` and an FK to
  the package.

`PRAGMA user_version` is the sole schema metadata and must equal integer `1`.
Initialization occurs only when the database has no application tables and
`user_version == 0`; any non-empty unknown schema or unknown version is
rejected. Initialization and every reopen validate exact DDL, indexes, foreign
keys, and metadata. Writes use one `BEGIN IMMEDIATE` transaction. Reads use one
explicit read transaction and reconstruct the complete package from canonical
bytes, recompute all indexed projections and memberships, and reject any drift
or corruption. No resolved-state column or mutation API exists in this slice.
GAP-06 may add a separately reviewed additive resolution table; it must not
mutate the immutable request or package.

## Failure and retry semantics

- Unknown/invalid candidate or draft data: no mutation.
- Builder failure: no mutation.
- Process loss before commit: no visible proposal or decision.
- Before merge authority or builder, lookup validates the complete store and all
  memberships. An identical member set returns the byte-identical package,
  irrespective of newer evidence or authorization input, without calling
  authority, builder, or clock.
- Same cohort with changed evidence: returns the already-frozen package.
- Overlapping but non-identical cohort: collision, no mutation.
- After builder validation, `BEGIN IMMEDIATE` repeats the membership check.
  Concurrent identical creation commits one package; the loser returns the
  exact winner without persisting or comparing its generated draft.
- Concurrent overlapping cohorts: at most one succeeds; no gap key is shared.
- Stored schema, proposal, membership, decision, or fingerprint corruption:
  fail closed before returning a package.

## Verification

- Contract codecs, exact field sets, bounds, Base64 canonicality, graph
  validation, every stated domain separator/fingerprint, and canonical
  roundtrips.
- Single/multi-candidate creation, explicit merge authorization, independent
  gaps, retry without callback, changed later evidence, and overlap collision.
- Builder failure/invalid output rollback, process-kill/reopen, and concurrent
  identical/overlapping creation.
- Database schema drift, row deletion/tampering, projection drift, and foreign
  key corruption.
- Architecture firewall proving no model/provider, Flywheel, GitHub, network,
  subprocess, arbitrary-path, GAP-06 promotion, or public-harness reverse
  dependency.
- Missing/rejecting merge authority despite a forgeable review hash; oversize at
  every level; fixed `artifact_state`; hostile controls/dependency graphs;
  retry with changed evidence; process loss between package/member inserts;
  swapped/deleted/corrupt membership; and tampering of every indexed ID.
- Ruff, strict mypy, full tests, package build, clean-wheel import, Python
  3.12/3.13 CI, semantic review, and security review.

## Out of scope

- Decision resolution or authentication.
- Accepted promotion, approved specs/beads, goals, worker dispatch, or code.
- Model calls, prompt implementations, Flywheel mutation, GitHub sync,
  transports, merge, release, or deployment.
