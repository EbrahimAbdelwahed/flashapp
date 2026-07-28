---
name: worker-profile-factory
description: Create reusable worker profiles before launching specialized Codex workers, including scope, boundaries, quality gates, and report expectations.
---

# Worker Profile Factory

Use this skill when an orchestrator needs a reusable specialist worker, especially for repeated work across task beads, repositories, frameworks, tools, or quality domains.

## Workflow

1. Define the task scope in one concrete sentence.
2. Identify the worker specialization needed to complete that scope without redesigning the feature.
3. If the specialization depends on a framework, tool, library, platform, or current best practice, research the relevant current docs before writing the profile.
4. Create a worker profile using `templates/worker-profile.md`.
5. Fill every boundary field before delegation:
   - mandate;
   - in-scope work;
   - allowed files or packages;
   - forbidden decisions;
   - required context to read first;
   - quality gates;
   - verification expectations;
   - report format;
   - reuse trigger.
6. Only after the profile is complete, launch the worker or paste the profile into the worker brief.

## Profile Rules

- Prefer a narrow, reusable role over a one-off vague agent.
- Keep architecture, product, prompt-policy, and data-model decisions with the orchestrator unless explicitly delegated.
- Give workers exact file boundaries when concurrent edits are possible.
- Make forbidden decisions concrete so workers know when to stop and report back.
- Include current-doc references when the worker must follow a fast-moving framework or tool.
- Treat the profile as reusable guidance; task-specific details belong in the worker brief.

## Output

Return:

1. Task scope.
2. Worker specialization.
3. Research notes or "not needed".
4. Completed worker profile.
5. Launch or briefing instructions for the worker.
