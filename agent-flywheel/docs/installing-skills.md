# Installing Skills

This repository stores skills under `skills/` so they can be versioned with the devkit.

To make a skill available to Codex, copy or symlink the skill folder into your Codex skills directory.

Typical local target:

```text
~/.codex/skills/
```

Example:

```bash
cp -R skills/feature-spec-architect ~/.codex/skills/
cp -R skills/implementation-orchestrator ~/.codex/skills/
cp -R skills/worker-profile-factory ~/.codex/skills/
cp -R skills/code-quality-governor ~/.codex/skills/
cp -R skills/simplify-and-refactor-code-isomorphically ~/.codex/skills/
cp -R skills/workflow-optimizer ~/.codex/skills/
cp -R skills/generate-morphology-first-anatomy-cards ~/.codex/skills/
```

For active development, prefer symlinks so edits in this repo are reflected immediately:

```bash
ln -s "$PWD/skills/feature-spec-architect" ~/.codex/skills/feature-spec-architect
```

After installing, start a new Codex session so skill metadata is loaded.

## Recommended Initial Set

Install these first:

- `feature-spec-architect`
- `implementation-orchestrator`
- `worker-profile-factory`
- `code-quality-governor`
- `simplify-and-refactor-code-isomorphically`
- `workflow-optimizer`

Install these when the product codebase reaches the relevant area:

- `study-prompt-system-designer`
- `study-rag-architect`
- `generate-morphology-first-anatomy-cards` when generating source-grounded anatomy Anki cards with morphology-first reconstruction and deterministic quality gates.
