# Feature Spec: Course-Aware Prompt Profiles

Status: Example
Owner: product-orchestrator
Date: 2026-06-21

## Goal

Allow the platform to adapt tutoring, flashcard generation, quiz generation, and explanation style based on a structured course profile.

## Problem

Study prompts cannot be one-size-fits-all. A medical histology course, a law course, and an engineering course need different density, reasoning style, citation strictness, flashcard shape, and exam assumptions.

## Users

- Student configuring a course.
- Agent generating study material.
- Developer adding new course profile behavior.

## In Scope

- Define `CourseProfile` and `PromptPolicy` domain types.
- Add prompt composition from base policy, course profile, task prompt, user state, and retrieved evidence.
- Add two seed profiles: `medical-conceptual` and `generic-mcq`.
- Add eval fixtures proving that the same source material produces different card policies under different profiles.

## Out of Scope

- UI for editing profiles.
- Marketplace of shared profiles.
- Fine-tuning.
- Provider-specific prompt syntax.

## Domain Model

Affected entities:

- `CourseProfile`: structured course-level learning and exam assumptions.
- `PromptPolicy`: derived constraints used by prompt composers.
- `PromptTemplate`: versioned prompt definition.
- `PromptRun`: execution metadata for audit trails.

## API / Interface Contract

```ts
export interface CourseProfile {
  id: string
  name: string
  domain: "medicine" | "law" | "engineering" | "language" | "generic"
  examFormat: "oral" | "mcq" | "written" | "mixed"
  reasoningStyle: "memorization" | "conceptual" | "procedural" | "clinical"
  citationPolicy: "required" | "preferred" | "optional"
  flashcardPolicy: {
    preferredTypes: Array<"basic" | "cloze" | "mcq">
    atomicity: "strict" | "balanced"
    maxCardsPerSourceChunk?: number
  }
}
```

## Prompt Behavior

- Prompt IDs affected:
  - `flashcard.generate.v1`
  - `tutor.answer.v1`
  - `quiz.generate.v1`
- Course profile inputs:
  - domain
  - exam format
  - reasoning style
  - citation policy
  - flashcard policy
- Output schema:
  - unchanged for tutor answers;
  - flashcard output must include `courseProfileId` and `promptVersion`.
- Grounding requirements:
  - generated cards must cite source chunk IDs.
- Eval fixtures required:
  - one source chunk processed under two profiles.

## RAG / Source Grounding

- Required sources: source chunks already retrieved by caller.
- Citation behavior: citations required for generated cards.
- Unsupported-answer behavior: return `insufficient_evidence` rather than inventing.

## UX Notes

- No UI in this first implementation.

## Risks

- Overfitting profiles to one user's medical workflow.
- Letting prompt strings branch in uncontrolled ways.
- Making profile fields too broad to test.

## Acceptance Criteria

- [ ] `CourseProfile` and `PromptPolicy` are exported from core.
- [ ] Prompt composition accepts a course profile.
- [ ] Two seed profiles exist.
- [ ] Flashcard prompt eval fixture shows profile-sensitive output constraints.
- [ ] Prompt metadata includes version and known failure modes.

## Verification

- Unit: profile validation and prompt policy derivation.
- Integration: prompt composition snapshot tests.
- Evals: fixture for two profiles over the same evidence.
- Manual: inspect generated prompt for no provider-specific assumptions.

## Open Questions

- Should user-authored profiles be allowed in MVP?
- Should profile changes invalidate prior generated cards?

## Task Beads

- `task-001`: Define core profile and policy types.
- `task-002`: Implement prompt registry metadata.
- `task-003`: Implement prompt composer.
- `task-004`: Add seed profiles.
- `task-005`: Add eval fixtures and docs.
