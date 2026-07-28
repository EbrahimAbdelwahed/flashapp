# GAP-06 maintainer resolution and accepted promotion

Status: Done
Date: 2026-07-25
Depends on: GAP-05C at
`07146ba32b888687ad10457d031b20524e25af8c`

## Goal

Resolve one immutable GAP-05C decision exactly once. Rejected, deferred, and
duplicate outcomes create no implementation work. Accepted outcomes alone emit
one canonical, idempotent promotion job that a technical adapter can
materialize into the existing Flywheel run shape, including an authorized goal
artifact and a dispatch-stage-valid run, without creating task state, emitting
dispatch packets, spawning workers, or granting repository publication
authority.

## Risk and slice strategy

High risk: authenticated authority, public contracts, persistence/CAS, durable
side effects, and a filesystem integration.

- GAP-06P: extract the minimum pure Flywheel planning/render/validation
  primitives into one packaged module consumed by both the existing CLI and
  promotion path.
- GAP-06A: closed resolution contracts, private SQLite resolution store,
  compare-and-set service, and accepted-only canonical promotion outbox.
- GAP-06B: idempotent local Flywheel adapter that materializes reviewed inputs,
  validates normal gates, and records a promotion receipt.

GAP-06 is not Done until all three slices and their adversarial closure are
green.

## Authority boundary

`MaintainerResolutionAuthority` is trusted host workflow code. Its
`resolve(DecisionViewV1)` method returns `ResolutionCommandV1 | None`. The
public resolution service owns the private store; no public mutator accepts a
resolution command directly. It receives a trusted read-only
`ProposalPackageSource`; callers pass only a decision ID. The service always
loads the exact GAP-05C package persisted for that decision before consulting
authority. The source exposes exact read-only
`get_by_decision_id(decision_id)` and `get_by_proposal_id(proposal_id)` methods;
the latter is used only to validate duplicate targets.

`DecisionViewV1` contains exactly `schema_version=1`, `proposal_id`,
`decision_id`, `requested_authority`, sorted visible `option_ids`, sorted
visible `bead_ids`, and `package_fingerprint`. The fingerprint uses domain
`b"study-agent-devkit-gap06-package-v1\0"` over the exact persisted GAP-05C
package bytes. The authority returns one command bound to the exact proposal and
decision IDs.

Closed outcomes:

- `rejected`: no branch payload;
- `deferred`: exact bounded opaque `defer_reference`;
- `duplicate`: exact different 64-hex `duplicate_of_proposal_id`;
- `accepted`: `selected_option_id` from the visible proposal plus exact bounded
  grill receipt references.

The authority receipt is trusted context, not a cryptographic proof. The service
derives `authority_receipt_fingerprint` with domain
`b"study-agent-devkit-gap06-authority-v1\0"` over exact canonical command
fields. No model, proposal builder, imported report, or caller-supplied hash can
resolve a decision through the supported API.

`GrillReceiptV1` contains exactly `subject_kind=proposal|bead`, the exact
proposal or bead ID, bounded opaque `receipt_id`, and 64-hex evidence digest.
Accepted commands require one proposal receipt and exactly one receipt per
visible bead. The command cannot provide worker briefs, file scopes, commands,
artifact bodies, goal flags, exclusions, or readiness claims.

The service derives approved artifact state, selected option binding, fixed
exclusions, goal presence, and the complete promotion body from the persisted
GAP-05C package. Artifact ID, kind, body, and dependencies remain unchanged;
only the outer artifact state becomes `approved`. Any missing runner-required
section, unresolved placeholder, embedded `Status: Draft`, invalid dependency,
or unsupported worker-profile directive fails deterministic planning before an
accepted resolution can commit. No scope is repaired or inferred.

Every accepted bead body must already be runner-complete with exact non-empty
sections: `Outcome`, `Slice Strategy`, `Spec Coverage`, `Grilling Evidence`,
`Worker Profile`, `Context`, `What To Do`, `Likely Files / Packages`,
`Acceptance Criteria`, `Verification`, and `Out Of Scope`. The worker-profile directive is only
`create <opaque-id>` or `none needed`; `reuse` and unspecified directives fail.

The shared renderer maps these sections losslessly:

- worker goal/mandate from `Outcome`;
- allowed files from `Likely Files / Packages`;
- invariants and acceptance criteria from `Acceptance Criteria`;
- verification commands from `Verification`;
- forbidden files/decisions from `Out Of Scope` plus fixed no-scope-expansion
  policy;
- stop conditions from unresolved/unsafe conditions already named in the bead;
- review gate fixed to independent semantic review.

`create` produces one self-contained profile from that closed template.
`none needed` creates no profile file, but its worker brief still contains goal,
allowed/forbidden scope, invariants, acceptance criteria, verification, stop
conditions, and review gate. Nothing is inferred from ambient files or new
model output.

## Resolution and promotion contracts

`GapResolutionV1` contains exactly:

- `schema_version=1`, `resolution_id`, `proposal_id`, `decision_id`, `outcome`;
- `selected_option_id`, `defer_reference`, and
  `duplicate_of_proposal_id`, with the same exact tagged-union nullability as
  `ResolutionCommandV1`;
- canonical `grill_receipts`, `authority_receipt_fingerprint`,
  `requested_authority`, and `resolved_at` as UTC microsecond RFC 3339.

`resolution_id` hashes the canonical body excluding itself with domain
`b"study-agent-devkit-gap06-resolution-v1\0"`.

`GapResolutionV1` contains no promotion ID, avoiding a circular content hash.
After deriving `resolution_id`, only an accepted outcome derives a
`FlywheelPromotionBundleV1`, which
contains exactly:

- schema version `1`;
- promotion ID, resolution ID, proposal ID, decision ID, and ordered cohort
  gap keys;
- selected option ID and requested authority;
- approved ADR/spec/bead artifacts;
- grill receipts, a deterministic Flywheel materialization plan derived by the
  shared planner, verification plan, and non-goals;
- optional `ImplementationGoalV1`;
- fixed required gates:
  `worker_briefs|tests|semantic_review|publication_authority`;
- fixed exclusions:
  `github_issue|repository_merge|release|deployment`.

The bundle embeds `MaterializationPlanV1` returned by the shared pure planner.
It is promotion-ID-free and contains exactly `schema_version=1`,
an opaque `run_id` supplied by the caller, and ordered `files`. GAP-06 supplies
`gap06-<first-24-hex-of-resolution_id>`, but the shared Flywheel type contains
no capability-gap provenance.
Each `MaterializationFileV1` contains exactly `relative_path` and padded-Base64
`content_b64`. Paths are unique normalized run-tree-relative POSIX paths.
Absolute paths, `.`/`..`, empty segments, backslashes, NUL,
duplicate/case-fold-colliding paths, and more than 128 files fail. Each file is
at most 256 KiB and the complete plan at most 2 MiB. The manifest inside the
plan uses the resolution-derived run ID, so neither plan nor run identity
depends on the later promotion ID.

Every plan includes these files in its 2-MiB total bound: `manifest.json`,
`context/context.md`, `spec/feature-spec.md`, ADRs under `decisions/`, tasks
under `tasks/`, created profiles under `profiles/`, all worker briefs under
`briefs/`, and optional `implementation-goal.json`. The manifest links each
exact relative path.

GAP-06 derives the bounded context Markdown without inference from exact
proposal/decision IDs, cohort gap keys, evidence fingerprint, selected option,
closed dimensions/reproduction summaries, and active-work references. It
contains no learner text or delivery identity and is at most 256 KiB. Missing
context is a planning error, so every accepted plan can satisfy the runner's
dispatch-stage context gate.

The promotion ID hashes the canonical promotion body excluding itself with
domain `b"study-agent-devkit-gap06-promotion-v1\0"`.

`ImplementationGoalV1` exists only for
`planning_and_implementation_goal`. It contains exactly `schema_version=1`,
derived `goal_id`, `proposal_id`, `spec_artifact_id`, sorted `bead_ids`, and
`status=authorized_not_started`. The goal ID uses domain
`b"study-agent-devkit-gap06-goal-v1\0"` over the body excluding its ID. It
authorizes orchestration only; it does not spawn a worker, create a Codex task,
or authorize Git/GitHub.

All codecs reject unknown fields, booleans as integers, noncanonical JSON,
oversized bytes before parsing, hash/cross-link drift, and invalid branch
combinations.

`ResolutionCommandV1` contains exactly `schema_version=1`, `proposal_id`,
`decision_id`, `outcome`, `selected_option_id`, `defer_reference`,
`duplicate_of_proposal_id`, and `grill_receipts`. Exact tagged-union branches:

- `rejected`: all branch values null and no grill receipts;
- `deferred`: only `defer_reference` is non-null and no grill receipts;
- `duplicate`: only `duplicate_of_proposal_id` is non-null and no receipts;
- `accepted`: only `selected_option_id` is non-null and the exact grill tuple is
  non-empty.

At most 65 grill receipts are allowed. Command bytes are at most 128 KiB,
resolution bytes 256 KiB, promotion bytes 2 MiB, and sink receipt bytes 64 KiB.
All opaque IDs use GAP-05C's regex; every textual value uses its UTF-8/control
policy. Tuples are sorted by their documented ID and duplicates fail.
Approved artifacts order as ADR, spec, then bead ID; grill receipts order by
subject kind and ID; plan files order by relative path. Verification and
non-goal tuples preserve their already-canonical GAP-05C order. Required gates
and exclusions use the fixed order written above.

## GAP-06A persistence and CAS

Use a third, separately reviewed SQLite database rather than changing exact
GAP-05B or GAP-05C schemas. Schema version 1 contains only:

- `resolution_packages`: one canonical resolution and nullable accepted
  promotion bytes per unique decision/proposal, with verified indexed
  resolution/outcome/promotion projections;
- `materialization_claims`: zero or one row per accepted promotion, binding a
  unique stable `sink_id` before external work and holding a nullable canonical
  receipt.

Canonical bytes are the source of truth; indexed columns are verified
projections. The public
`SQLiteResolutionService(database, proposal_source, authority, clock)` owns a
private store. `resolve(decision_id)` validates the ID and queries the
resolution database first. Exact retry validates and returns the first
persisted winner without calling proposal source, authority, planner, or clock.
Only a new decision loads the persisted GAP-05C package and plans a possible
accepted outcome. A concurrent different command loses the CAS and receives
the persisted winner.
First resolution uses `BEGIN IMMEDIATE`; a unique decision row is the
compare-and-set from unresolved to one terminal outcome. `BaseException` rolls
back.

Duplicate targets must exist in `ProposalPackageSource`, differ from the current
proposal, and not resolve to a duplicate. Once any proposal has inbound
duplicate links, its own decision cannot later resolve as duplicate; this keeps
the graph rooted and acyclic. Non-accepted rows have null promotion bytes.

The third database preserves the already-reviewed exact GAP-05B/GAP-05C
schemas and separates maintainer authority state. Cross-database foreign keys
are unavailable; the service compensates by loading canonical source packages
through the trusted read protocol and persisting/revalidating their proposal,
decision, and package content IDs on every new resolution.

## GAP-06B durable adapter boundary

`FlywheelPromotionSink` exposes a stable 64-hex `sink_id` and
`apply(bundle) -> FlywheelPromotionReceiptV1`. It is a technical, idempotent
adapter port injected into the service by the trusted host, not selected by the
caller for each attempt. `materialize(promotion_id)`:

1. validates the complete resolution database;
2. in a short transaction, creates or validates the durable
   `(promotion_id, sink_id, receipt=NULL)` claim; another sink ID collides;
3. returns a persisted receipt without invoking the sink on exact retry;
4. invokes the claimed idempotent sink outside any SQLite transaction;
5. opens a short `BEGIN IMMEDIATE`, revalidates the same job and claim, and
   compare-and-set inserts the verified receipt; a concurrent winner is returned
   when byte-identical and conflicts fail.

A process loss after external materialization but before receipt commit may
invoke the same claimed sink again. Therefore it must key exclusively by
promotion ID and return the same receipt for the same bytes; a different sink
cannot apply that promotion and conflicting bytes fail.

`FlywheelPromotionReceiptV1` contains exactly `schema_version=1`, `receipt_id`,
`promotion_id`, `sink_id`, `promotion_bundle_fingerprint`, `run_id`,
`file_manifest_digest`, and `status=materialized`. It contains no clock.
The bundle fingerprint uses domain
`b"study-agent-devkit-gap06-promotion-bytes-v1\0"` over exact promotion bytes.
The file-manifest digest uses domain
`b"study-agent-devkit-gap06-file-manifest-v1\0"` over ordered canonical
`(relative_path, sha256(file_bytes))` entries. The receipt ID uses domain
`b"study-agent-devkit-gap06-receipt-v1\0"` over its body excluding the ID.

The reference `LocalFlywheelPromotionSink` is the only filesystem-aware module.
It receives one configured project root and:

- rejects symlinks and any target escaping the root;
- stages under the target `docs/flywheel-runs` directory and atomically renames
  the plan's resolution-derived run directory;
- on retry, verifies every existing canonical byte and returns the same receipt;
- never overwrites a different run;
- writes a self-contained existing manifest/artifact layout under the staged
  run directory: approved spec, ADR, task beads, derived worker
  profiles/briefs, and implementation-goal JSON when requested;
- invokes the shared pure planner/validator, not shell/subprocess, and commits
  only when planning and dispatch-stage validation have no errors;
- does not create `br` beads, spawn workers, modify source code, call GitHub, or
  run Git/merge/release/deploy.

It emits no worker dispatch packets: the existing ready-only path requires `br`
authority and subprocess-backed task state. After promotion, the normal
orchestrator may explicitly create `br` beads and call the existing dispatch
lane. GAP-06 does not duplicate dependency readiness.

This is the concrete reconciliation of the public GAP-06 wording: promotion
creates the approved, dispatch-stage-valid authorization package and optional
goal; actual ready-only dispatch remains the next normal orchestrator action
after explicit `br` task-state authority. GAP-06 itself does not claim that
authority.

GAP-06P must land first. It extracts only pure render/parse/validate functions
behind `study_agent_devkit.flywheel.materialization`. That neutral module owns
the codecs/types `PromotedRunInputV1`, `RunArtifactV1`,
`WorkerProfileRenderInputV1`, `WorkerBriefRenderInputV1`,
`MaterializationPlanV1`, `MaterializationFileV1`, and
`ValidationFindingV1`; it never imports capability-gap types. GAP-06A maps its
persisted package into these inputs. It renders manifest, context, artifact,
profile, brief, and goal bytes; it performs no argument parsing, filesystem
write, `br`, dispatch, or orchestration. The existing CLI imports the same
renderers and validator. Copying runner logic or importing the CLI script is
forbidden.
Validation follows manifest artifact references rather than assuming global or
self-contained physical locations. `reuse <profile>` is rejected unless that
profile body is immutable input; GAP-06 supplies none, so accepted promotions
must use `create <profile>` or `none needed`.

Exact shared API:

- `render_worker_profile(input: WorkerProfileRenderInputV1) -> bytes`;
- `render_worker_brief(input: WorkerBriefRenderInputV1) -> bytes`;
- `plan_run(input: PromotedRunInputV1) -> MaterializationPlanV1`;
- `validate_materialization_plan(
  plan: MaterializationPlanV1
  ) -> tuple[ValidationFindingV1, ...]`.

`PromotedRunInputV1` contains exactly `schema_version=1`, `run_id`,
`feature_title`, `source_ref`, bounded `context_body`, one spec artifact,
ordered ADR/task artifacts, and optional exact goal JSON bytes.
`RunArtifactV1` contains exactly `kind=adr|spec|task`, `artifact_id`, `body`,
and ordered `depends_on`. Render-input objects contain only the exact task,
spec/context references, and closed parsed sections named above.
`ValidationFindingV1` contains exactly `schema_version=1`,
`severity=error|warning`, bounded opaque `code`, nullable normalized relative
path, and bounded UTF-8 `message`. At most 256 findings are returned; code is at
most 64 ASCII characters and message at most 4 KiB.

The validator operates entirely on the in-memory plan, follows manifest
references, returns structured findings, and performs no reads or writes.
Filesystem containment, symlink checks, staging, and final-location validation
belong only to `LocalFlywheelPromotionSink`. Existing CLI arguments,
orchestration, filesystem writes, subprocess-backed `br`, and dispatch stay
outside the shared module.

## Retry and failure semantics

- Exact resolved retry: identical receipt, no authority or clock.
- Current authority disagreement after resolution does not matter; exact retry
  returns the persisted first winner without callbacks.
- Concurrent resolution: one terminal winner returned to all callers.
- Authority returns `None` or raises: decision remains unresolved and no
  resolution or promotion bytes are written.
- Rejected/deferred/duplicate: no promotion job and sink cannot be invoked.
- Accepted with missing grill/brief, changed draft body, unresolved choice, or
  authority mismatch: no resolution is committed.
- Process loss before resolution commit: still unresolved.
- Sink failure: resolution remains accepted and promotion job pending.
- Process loss after claim leaves the same sink durably bound and pending.
- Sink retry/process loss: same bundle, idempotent run, one canonical receipt.
- Stored schema/bytes/index/member/receipt drift: fail closed.

## Verification

- Every branch, exact/conflicting retry, race, process loss, callback ordering,
  authority mismatch, stale/tampered proposal, and accepted-only job creation.
- Readiness bounds, exact draft-body/state promotion, option/authority binding,
  missing grills/briefs, unresolved decisions, and goal presence/absence.
- Corrupted resolution/job/receipt/schema/index/FK and hostile SQLite storage
  classes.
- Proposal-source substitution, caller-built package rejection, duplicate
  target existence/inbound-link cycle prevention, and stale package failures.
- Local sink path traversal/symlink/existing conflict/staging loss/idempotent
  retry and shared runner validation.
- End-to-end accepted/rejected scenarios; rejected produces no run, accepted
  produces a valid dispatch-stage-ready but non-dispatched run plus optional
  authorized goal.
- Architecture firewall: core resolution modules have no filesystem, model,
  provider, network, subprocess, GitHub, Git, merge, release, or deploy imports;
  only the technical local sink may use filesystem APIs.
- Ruff, strict mypy, full tests, wheel/clean import, Python 3.12/3.13 CI,
  independent semantic/security review.

## Out of scope

- Feature code, worker spawning, Codex goal API calls, `br` mutation, GitHub
  sync, Git operations, merge, release, deployment, or learner/product state.
