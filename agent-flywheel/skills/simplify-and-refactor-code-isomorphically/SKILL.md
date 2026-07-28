---
name: simplify-and-refactor-code-isomorphically
description: Expert behavior-preserving code simplification and refactoring. Use when asked to make code clearer, smaller, more maintainable, less duplicated, less tangled, more modular, easier to test, or easier to extend without changing externally observable behavior across Python, TypeScript/React/Next.js, Swift/SwiftUI, CLIs, services, UI state, LLM workflows, or data pipelines.
---

# Simplify And Refactor Code Isomorphically

## Mission

Transform code into a simpler equivalent representation. Behavior stays the same; the model a future engineer must hold in their head gets smaller.

Refactor like an expert maintainer, not a formatter. Find the concept that is making the code hard to reason about, pin current behavior, then perform the smallest high-leverage transformation that removes accidental complexity.

## Practitioner Standard

- Optimize for local reasoning: after the change, a reader should need fewer files, flags, branches, temporal assumptions, and hidden side effects to understand the behavior.
- Reduce concepts before reducing lines. A shorter version with more implicit coupling is worse.
- Preserve domain language where it carries meaning; rename vague plumbing, not useful vocabulary.
- Prefer making invariants explicit over adding comments that describe fragile code.
- Keep public behavior stable: inputs, outputs, timing, ordering, side effects, persistence, auth, accessibility, logs, telemetry, errors, and retry behavior all count.
- Refuse "cleanup" that smuggles product changes. If behavior should change, name it as a separate task.

## Core Rules

- Start from evidence: read the code, callers, tests, docs, runtime conventions, generated references, route conventions, and adjacent implementations before choosing an abstraction.
- Separate discovery from editing. Do not start moving code until the behavior boundary and verification path are clear.
- Change one axis at a time: naming, extraction, data-shape normalization, boundary movement, deletion, and feature behavior should not be mixed casually.
- Prefer mechanical, reversible steps. Make each step easy to review and easy to abandon.
- Keep compatibility shims when callers outside the edit scope may rely on old names, shapes, or paths.
- Delete code only after proving it has no live caller or after documenting the migration path.
- If verification is weak, add characterization coverage or narrow the refactor until the residual risk is acceptable.

## Operating Loop

1. Form the behavior map:
   - Identify the visible contract: public API, UI flow, CLI output, data schema, persistence, external services, and failure modes.
   - Trace from entrypoints and callers, not just from the file that looks messy.
   - Write down the invariants that must survive: defaults, null handling, order, permissions, retry policy, cache behavior, error taxonomy, and user-visible wording.
2. Diagnose the dominant complexity:
   - Duplication, long control flow, hidden state, feature envy, temporal coupling, primitive obsession, weak names, mixed I/O and domain logic, leaky abstraction, or shotgun changes.
   - Pick the single complexity source whose removal makes the next change easier.
3. Pin behavior:
   - Run existing focused tests.
   - Add characterization tests, golden fixtures, CLI samples, UI interaction checks, or small unit tests around pure logic when behavior is underspecified.
   - If automation is not practical, capture a precise manual before/after check.
4. Select the transformation:
   - Inline false abstractions before extracting new ones.
   - Extract pure decisions from side-effectful orchestration.
   - Collapse duplicated branches into explicit data or small named predicates.
   - Move boundaries only when the dependency direction becomes simpler.
   - Strengthen types and names without silently narrowing accepted input.
5. Execute as a proof chain:
   - Make a small transformation.
   - Run the narrow check.
   - Compare behavior.
   - Repeat only while the next step is still clearly behavior-preserving.
6. Stop deliberately:
   - Stop when the requested pain is removed, the next change would need a product decision, or verification no longer supports the risk.
   - Report structural changes, behavior evidence, commands run, and remaining risk.

Read `references/refactor-checklist.md` before a multi-file refactor, public API/module boundary change, risky UI/state refactor, async/concurrency rewrite, performance-sensitive rewrite, dead-code removal, or any work with weak test coverage.

## Expert Transformation Tactics

- Name the decision, not the mechanics: replace `if` forests with concepts like `isEligibleForPublication`, `requiresReview`, or `nextRetryAt` when those concepts exist in the domain.
- Pull pure policy out of orchestration: keep parsing, validation, authorization, persistence, network calls, and rendering from blurring together.
- Push data normalization to the boundary: internal code should not repeatedly defend against the same raw shape.
- Collapse parallel structures: duplicated switches, duplicated maps, and matching arrays usually want one source of truth.
- Replace flags with modes when combinations matter; replace modes with separate functions when call sites become clearer.
- Prefer direct code over generic frameworks until at least two real call sites share the same semantics.
- Use types to encode invariants when the language and codebase style support it.
- Delete adapter layers that only pass through values and add no compatibility, policy, logging, or isolation.
- Keep adapter layers that protect external contracts, secrets, provider-specific APIs, or compatibility.

## Red Flags

- A clever abstraction whose name is broader than its proven use cases.
- A new helper that forces callers to learn more parameters, flags, or lifecycle rules than before.
- A refactor that changes API defaults, thrown errors, response shapes, database writes, UI labels, keyboard behavior, auth checks, review gates, or publication rules.
- Widened blast radius from moving shared helpers too high in the dependency tree.
- Snapshot updates used as proof instead of evidence to inspect.
- Deleting "unused" code without searching dynamic imports, route conventions, reflection, generated references, docs, scripts, and runtime configuration.
- Splitting large files by line count instead of by stable responsibility.
- Replacing explicit domain rules with generic "config" that hides behavior.
- Adding caching, batching, parallelism, lazy loading, or debounce behavior in a task that was supposed to preserve behavior.

## Decision Heuristics

- If the code is hard because it does too many jobs, separate responsibilities.
- If it is hard because the same rule appears in many places, centralize the rule near the data boundary or domain concept.
- If it is hard because a helper hides too much, inline it and let the real shape show.
- If it is hard because state changes over time, make states, transitions, and ownership explicit.
- If it is hard because call sites are noisy, improve the API from the call site inward.
- If it is hard because dependencies point both ways, introduce a narrower boundary or move the policy to the side that owns the decision.
- If it is hard because tests are absent, characterize first or reduce scope.

## Output

For substantial refactors, report:

- Complexity diagnosis: what made the code hard.
- Transformation chosen: why this refactor was the smallest useful move.
- Behavior preserved: contracts, edge cases, side effects, and compatibility.
- Verification: exact commands and outcomes.
- Residual risk: weak coverage, manual checks, or follow-up work.
