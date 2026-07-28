# Contributing

This project defines the development workflow for a future study-agent platform. Contributions should improve clarity, repeatability, and code quality.

## Standards

- Keep instructions concise and agent-usable.
- Prefer templates and checklists over long essays.
- Do not add dependencies or external tools unless they materially improve the workflow.
- Keep skills focused. One skill should do one job well.
- Add examples when a workflow is hard to understand from the template alone.

## Changing Skills

When editing a skill:

1. Keep `SKILL.md` short enough to load comfortably in context.
2. Move long examples or variants into `references/`.
3. Update README references if skill names or responsibilities change.
4. Test the skill mentally against one realistic user request.

## Changing Templates

Templates should be strict enough to guide agents, but not so detailed that every feature feels bureaucratic. If a field is rarely useful, remove it or move it to an optional reference.

## Review Expectations

Before merging workflow changes:

- Check that the artifact ladder still makes sense.
- Check that new instructions do not conflict with `AGENTS.md`.
- Check that added ceremony has a clear payoff.
- Check that examples are study-agent relevant.
