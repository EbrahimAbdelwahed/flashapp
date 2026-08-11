# FlashApp — Agent Instructions

## Source of truth

- Product decisions: `flash-up-architecture-brief.md`.
- Engineering contract: `flash-up-implementation-spec.md`.
- Design direction for every UI batch: `docs/ux-principles.md` (owner amendment, 2026-07-28).
- Delivery state, batch beads, worker briefs, and review evidence: `docs/flywheel-runs/flash-up-v1/`.

If the brief conflicts with the implementation specification, stop and record the conflict as an ADR; the brief wins.

## Flywheel workflow

`agent-flywheel/` is the local orchestration kit copied into this repository. Use its runner and templates rather than inventing another task protocol:

```text
approved spec -> batch bead -> worker brief -> scoped implementation -> review evidence -> worklog / ADR
```

Read the assigned batch bead before changing code. A batch may contain several original B-prefixed beads only where its acceptance criteria name the original coverage. Do not expand a batch across a CloudKit, FSRS, data-loss, or public-product decision: write an ADR and stop instead.

## FlashApp non-negotiables

- iOS/iPadOS 17+, SwiftUI, Core Data with `NSPersistentCloudKitContainer`; no SwiftData.
- `FlashUpDomain` remains pure and portable; dependency direction is App -> Data -> Domain.
- Card content stays on-device except the user's iCloud and explicit exports. Logs never contain card text.
- User-facing copy ships in English and Italian; every UI change includes accessibility and reduced-motion behavior.
- Never delete a user store to repair migration or sync failures.

## Coordination and verification

- Keep changes within the assigned batch's file boundary and report any follow-up as a new bead candidate.
- Prefer one active owner per batch; use the dependency graph in `docs/flywheel-runs/flash-up-v1/batch-plan.md` before parallel dispatch.
- Do not publish, push, or create a remote GitHub repository without explicit user authorization.
- Each completed batch updates `docs/decisions/worklog.md` once that file exists and records the requested verification evidence.
