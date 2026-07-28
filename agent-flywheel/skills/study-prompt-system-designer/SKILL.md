---
name: study-prompt-system-designer
description: Design course-aware prompt systems, prompt registries, output schemas, and eval fixtures for study-agent features such as tutoring, flashcard generation, quiz generation, explanations, and source-grounded answering.
---

# Study Prompt System Designer

Use this skill when a feature changes prompt behavior, course profiles, generated study objects, tutoring style, or eval fixtures.

## Core Model

Prompts should compose in layers:

```text
base study policy
+ course profile
+ task prompt
+ user/session state
+ retrieved evidence
+ output schema
```

Avoid monolithic prompts and scattered string branches.

## Required Prompt Metadata

Each prompt needs:

- `id`
- `version`
- `purpose`
- `inputs`
- `outputSchema`
- `groundingPolicy`
- `courseProfileFields`
- `knownFailureModes`
- `evalFixtures`

## Course Profile Guidance

A course profile should influence:

- expected reasoning style;
- exam format;
- card density;
- allowed card types;
- explanation depth;
- citation strictness;
- common traps or confusables.

It should not hardcode one university, one professor, or one user's habits into the core platform.

## Eval Requirements

For prompt behavior changes, define fixtures for:

- normal case;
- insufficient evidence;
- ambiguous source;
- course-profile variation;
- malformed model output;
- overgeneration or undergeneration.

## Output

Return a prompt design note with schemas, examples, eval cases, and implementation tasks.
