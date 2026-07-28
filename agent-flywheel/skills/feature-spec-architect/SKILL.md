---
name: feature-spec-architect
description: Turn a rough product or engineering idea into a precise implementation-ready feature spec for the study-agent platform. Use when the user describes a vague feature, asks to plan a capability, or wants questions before implementation.
---

# Feature Spec Architect

Use this skill before implementation when a feature is vague, cross-cutting, high-risk, or prompt/RAG/data-model related.

## Workflow

1. Restate the feature in one concrete sentence.
2. Identify missing decisions that would materially affect implementation.
3. Ask at most 5 targeted questions if needed. If reasonable assumptions are safe, state them and continue.
4. Produce a feature spec using `templates/feature-spec.md`.
5. Include explicit non-goals and acceptance criteria.
6. Mark whether the spec needs:
   - an ADR;
   - prompt eval fixtures;
   - RAG/source-grounding tests;
   - UI states;
   - data migration;
   - worker decomposition.

## Quality Bar

A good spec lets a fresh worker answer:

- What behavior changes?
- What stays out of scope?
- What entities and APIs are affected?
- What prompt/RAG behavior is expected?
- How will success be verified?
- What failure cases matter?

## Study-Agent Defaults

- Source grounding is required for explanations, generated cards, and RAG answers unless explicitly out of scope.
- Course profile behavior should be structured data plus prompt composition, not scattered prompt branches.
- Generated flashcards and quiz questions must carry provenance.
- Anki export is an integration, not the canonical scheduling model.
- Deep provider assumptions belong behind adapters.

## Output

Return a complete spec and a short "decision log" of assumptions. If the user is likely to continue directly into implementation, include a draft task bead list at the end.
