---
name: workflow-optimizer
description: Review an agent session, completed task, or conversation to identify reusable workflow improvements for AGENTS.md, skills, worker profiles, templates, prompts, quality gates, and orchestration rules.
---

# Workflow Optimizer

Use this skill at the end of a conversation, implementation batch, review cycle, or repeated failure.

## Goal

Improve the flywheel itself. Find places where the user had to babysit, agents asked avoidable questions, task beads lacked context, worker profiles were too vague, quality gates missed issues, or instructions should become reusable policy.

## Inputs

Read the available artifacts:

- conversation summary or transcript;
- task beads touched;
- worker briefs and profiles used;
- review findings;
- verification failures;
- user corrections;
- new assumptions or decisions;
- files changed.

## Review Questions

- Did an agent block on a decision it could have safely assumed?
- Did an agent assume something that should have required user approval?
- Did a task bead lack acceptance criteria, verification, context, or dependency detail?
- Did a worker profile need stricter scope, file boundaries, or report format?
- Did AGENTS.md miss a durable rule?
- Did a skill need a trigger, step, reference, or template update?
- Did prompt/RAG/SRS/eval work reveal a reusable quality gate?
- Did coordination need `br`, `bv`, Agent Mail, or file reservations earlier?
- Did repeated friction suggest a new worker profile?

## Output

Use `templates/workflow-improvement.md` for each proposed change.

Classify proposals:

- `apply-now`: low-risk instruction/template correction.
- `review-first`: useful but needs human or reviewer approval.
- `defer`: useful later, not worth adding ceremony yet.
- `reject`: considered but not worth doing.

## Rules

- Propose concrete edits, not vague advice.
- Prefer one small reusable rule over broad policy expansion.
- Do not silently change workflow-critical instructions unless the user asked for implementation.
- Record why the change reduces babysitting, improves quality, or improves parallel agent throughput.
