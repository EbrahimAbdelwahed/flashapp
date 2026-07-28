---
name: code-quality-governor
description: Review implemented changes for correctness, maintainability, test coverage, prompt/eval safety, source-grounding, and open-source readiness before merge or handoff.
---

# Code Quality Governor

Use this skill after implementation and before merge, handoff, or PR creation.

## Review Stance

Prioritize findings over summaries. Look for bugs, regressions, weak contracts, missing tests, prompt drift, and architectural coupling.

## Checklist

### General

- Changes match the spec and task bead.
- Public APIs are small and documented.
- No unrelated refactors.
- No new dependency without justification.
- Errors are handled intentionally.
- Types are strict and meaningful.

### Study-Agent Domain

- LLM calls are isolated in services/adapters.
- UI does not call LLM providers directly.
- Generated study objects have provenance.
- RAG answers preserve citation/source traceability.
- Unsupported answers are handled explicitly.
- Course profile behavior is deterministic and testable.
- Prompt changes include versioning and fixtures/eval notes.
- SRS behavior is tested against scheduling edge cases.

### Frontend

- Loading, empty, error, and success states exist.
- Controls are accessible.
- Text does not overflow expected containers.
- Data mutations show pending/error feedback.

### Verification

- Narrow tests were run.
- Broader checks were run when practical.
- Failures are documented and not hidden.

## Output

Use `../../templates/review-report.md` from this devkit, or the same section structure if the template path is unavailable in an installed skill copy.

If no issues are found, say so clearly and list residual risk or test gaps. If issues are found, order them by severity with file/line references when possible.
