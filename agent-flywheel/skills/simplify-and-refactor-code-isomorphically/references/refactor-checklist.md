# Refactor Checklist

Use this reference for non-trivial simplification or refactor work. The goal is not merely a cleaner diff; the goal is a smaller, more truthful program model with behavior evidence.

## Contents

- Behavior Boundary
- Complexity Diagnosis
- Transformation Recipes
- Verification Ladder
- Stack-Specific Notes
- Strong Refactor Review
- Stop Conditions
- Report Template

## Behavior Boundary

Capture these before editing:

- Public APIs, exported symbols, route names, command names, environment variables, config keys, model/schema fields, and persisted data.
- Inputs and outputs, including defaults, empty states, null handling, validation, ordering, rounding, localization, and serialization.
- Side effects: filesystem writes, database writes, cache invalidation, network calls, LLM calls, emails/messages, logs, telemetry, scheduling, and mutations of shared state.
- Failure behavior: thrown exceptions, error codes, HTTP statuses, user-visible messages, retries, fallbacks, and partial-success semantics.
- Concurrency and lifecycle behavior: debouncing, cancellation, async ordering, locks, transactions, UI lifecycle assumptions, and cleanup.
- Security and permissions: auth checks, tenant boundaries, privacy filtering, secret handling, and publication/review gates.

## Complexity Diagnosis

Use this table to choose a transformation instead of refactoring by taste.

| Symptom | Likely cause | Strong move | Avoid |
| --- | --- | --- | --- |
| Same rule repeated in many files | Rule lacks an owner | Move rule to the domain or data boundary that owns it | Global utility with vague parameters |
| Function is long but mostly linear | Multiple levels of detail | Extract named sub-decisions or phases | Splitting every 20 lines |
| Function is long because of cases | Missing data model or mode concept | Use explicit case data, table-driven dispatch, or polymorphism if local style supports it | Hiding cases in callbacks |
| Call sites pass many booleans | Implicit modes | Introduce named mode objects or separate functions | More optional flags |
| Helper is hard to name | Weak abstraction | Inline it and refactor what becomes visible | Keeping a misleading generic name |
| Tests require huge setup | Side effects mixed with policy | Extract pure policy and keep orchestration thin | Mocking more internals |
| Small change touches many files | Shotgun dependency | Move the decision closer to its owner | Creating a catch-all manager |
| State bugs recur | Hidden lifecycle or ownership | Model states and transitions explicitly | More defensive checks everywhere |
| UI component is hard to change | Rendering, state, data fetching, and effects are tangled | Split container/state/presentation along existing patterns | Decorative component fragmentation |
| Error handling is inconsistent | No error boundary or taxonomy | Normalize errors at boundary, preserve external messages | Rewording errors casually |

## Transformation Recipes

### Extract Pure Policy

1. Identify a side-effect-heavy function with a branchy decision inside it.
2. Copy the decision inputs into a small pure function.
3. Preserve the old orchestration order.
4. Test the pure function against current edge cases.
5. Keep side effects at the outer layer.

Use for validation, eligibility, scheduling, filtering, ranking, permissions, prompt selection, and UI state derivation.

### Inline Before Extracting

1. Find a wrapper/helper whose name is broader than its work.
2. Inline it into the one or two call sites.
3. Remove pass-through parameters.
4. Let repeated real concepts become visible.
5. Extract only the concept that remains stable.

Use when code has abstraction debt: factories, managers, utils, service wrappers, and helpers that mostly forward arguments.

### Collapse Duplicate Branches

1. Align duplicated branches side by side.
2. Mark what is identical, what is data, and what is real behavior difference.
3. Move data differences into explicit maps or records.
4. Keep behavior differences as named functions.
5. Test at least one representative per case.

Use for CLI subcommands, UI filters, subject/topic handling, provider routing, report generation, and status mapping.

### Normalize At The Boundary

1. Find repeated checks for raw input shape.
2. Choose the earliest trustworthy boundary: parser, API handler, DB adapter, file loader, LLM response parser, or UI form adapter.
3. Convert raw input into a stable internal shape once.
4. Make downstream code assume the normalized shape.
5. Preserve raw error semantics for external callers.

Use for JSON, CSV, route params, environment variables, LLM structured output, query strings, and imported legacy data.

### Make State Explicit

1. List possible states and transitions.
2. Identify impossible or invalid combinations in current flags.
3. Replace loose booleans with named states, enums, discriminated unions, or small structs where local style supports it.
4. Centralize transition logic.
5. Verify lifecycle behavior and edge transitions.

Use for async loading, publication workflows, review queues, onboarding, auth, sync, imports, retries, and long-running jobs.

### Improve API From Call Sites

1. Read three representative callers before editing the implementation.
2. Design the call that would make each caller obvious.
3. Preserve old entrypoints when external callers may exist.
4. Move conversion/adaptation behind compatibility wrappers.
5. Remove wrappers only after caller migration is complete.

Use when call sites are noisy, parameter order is error-prone, or implementation structure leaked outward.

### Split A Large File

Split only when a stable ownership line exists:

- Shell/container vs presentational UI.
- Pure domain policy vs I/O orchestration.
- Parser vs normalized model.
- Provider adapter vs provider-independent service.
- CLI argument parsing vs command execution.
- Test fixtures/builders vs assertions.

Do not split merely because a file is long. A long coherent file is often better than scattered fragments.

## Verification Ladder

Prefer the narrowest reliable proof, then expand:

1. Existing focused unit/component tests around the touched behavior.
2. Characterization tests for tricky branches before refactoring.
3. Golden fixtures for parsers, serializers, CLI output, generated prompts, and report artifacts.
4. Property or metamorphic checks when exact outputs vary but invariants are stable.
5. Integration or route tests when persistence, auth, LLM/service boundaries, or APIs are involved.
6. Typecheck/lint/build for moved boundaries or typed language changes.
7. Manual before/after checks for UI flows, CLI output, or behavior without practical automated coverage.

Snapshots and golden files are evidence to inspect, not proof by themselves. If they change, explain exactly why the change is still behavior-preserving or split it into a separate behavior-change task.

Record exact commands and outcomes. Do not hide unrelated pre-existing failures.

## Stack-Specific Notes

### Python

- Preserve import-time side effects, CLI entrypoints, argparse behavior, environment variable names, logging setup, warning behavior, and file path resolution.
- When splitting modules, avoid circular imports and keep optional dependencies lazy if the existing code does.
- Use dataclasses, typed dictionaries, protocols, or small value objects only when they clarify existing data contracts.
- Keep broad exception handling semantics stable unless the task explicitly asks to fix them.

### TypeScript, React, and Next.js

- Preserve server/client component boundaries, route segment conventions, server actions, cache semantics, suspense/loading/error behavior, and environment variable visibility.
- Do not move provider calls, secrets, or privileged data into client components.
- Preserve accessible names, keyboard flow, focus behavior, pending states, empty states, and error states.
- Keep hooks deterministic. Changing dependency arrays, memoization, or effect timing is behavior-affecting until proven otherwise.
- Prefer discriminated unions for explicit UI/data states when the local style supports them.

### Swift and SwiftUI

- Preserve `@State`, `@Binding`, `@ObservedObject`, `@StateObject`, `@Environment`, and model ownership semantics.
- Check actor/main-thread assumptions when moving async work.
- Avoid changing persistence identifiers, Codable fields, SwiftData/CoreData schemas, entitlements, or navigation routes during cleanup.
- Extract views by responsibility and data ownership, not just visual layout.
- Verify previews/tests do not hide lifecycle differences introduced by extraction.

### CLIs and Scripts

- Preserve exit codes, stdout/stderr split, JSON schema, color/pager behavior, prompts, config precedence, and working-directory semantics.
- Keep dry-run and apply behavior distinct.
- Do not change command names, flags, or defaults under a refactor without compatibility or migration notes.

### LLM and Study Workflows

- Keep LLM calls isolated in service modules.
- Preserve prompt versions, schemas, provenance, source-grounding, unsupported-answer handling, and model/provider selection.
- Refactor prompt or retrieval code with fixtures/evals when outputs affect study material.
- Do not "simplify" away citations, support judgments, confidence gates, or audit metadata.

## Strong Refactor Review

Before declaring success, ask:

- Is the new code easier to reason about from a real entrypoint?
- Did the number of concepts go down, or only the number of lines?
- Are invariants more explicit than before?
- Did any behavior drift hide under naming, extraction, or deduplication?
- Are new abstractions named narrowly enough for their proven semantics?
- Is each moved boundary aligned with ownership, dependency direction, and runtime constraints?
- Can the next likely change be made in fewer places?
- Did verification cover the riskiest preserved behavior?

## Stop Conditions

Stop refactoring when:

- The requested pain is removed.
- The next step requires a product, API, UX, data-model, or performance decision.
- Verification no longer supports the blast radius.
- The next abstraction would have only one speculative caller.
- You are about to update snapshots or fixtures without a clear equivalence story.
- The remaining mess belongs to a different module or task.

## Report Template

Use this compact structure for a substantial refactor report:

```markdown
## Refactor Summary
<what was simplified structurally>

## Complexity Removed
<dominant complexity source and why the chosen transformation was appropriate>

## Behavior Preserved
<contracts, edge cases, side effects, compatibility shims, and invariants checked>

## Verification
- `<command>`: <outcome>

## Residual Risk
<missing coverage, manual checks, assumptions, or follow-up>
```
