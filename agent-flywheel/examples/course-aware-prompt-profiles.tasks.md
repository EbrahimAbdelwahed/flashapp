# Task Beads: Course-Aware Prompt Profiles

## task-001 Define core profile and policy types

Status: Open
Priority: P1
Type: task
Depends On: none

### Context

The prompt system needs structured course data before any prompt composer can adapt behavior.

### What To Do

- Add `CourseProfile`, `PromptPolicy`, and supporting enum types.
- Keep types provider-agnostic.
- Export from the core package public API.

### Acceptance Criteria

- [ ] Types compile under strict TypeScript.
- [ ] Invalid profile examples fail validation if validation exists.
- [ ] Public API docs include a short example.

### Verification

- `pnpm typecheck`
- Unit tests for policy derivation if implemented.

## task-002 Implement prompt registry metadata

Status: Open
Priority: P1
Type: task
Depends On: task-001

### Context

Prompts must be versioned and auditable.

### What To Do

- Add prompt metadata shape.
- Add registry lookup by prompt ID and version.
- Include known failure modes and eval fixture references.

### Acceptance Criteria

- [ ] Registry can resolve `flashcard.generate.v1`.
- [ ] Missing prompts fail with typed errors.
- [ ] Prompt metadata is serializable.

### Verification

- `pnpm test -- prompt-registry`

## task-003 Implement prompt composer

Status: Open
Priority: P1
Type: task
Depends On: task-001, task-002

### Context

The composer combines base policy, course profile, task prompt, user state, and retrieved evidence.

### What To Do

- Implement deterministic prompt composition.
- Keep provider-specific formatting out of the composer.
- Add snapshot tests.

### Acceptance Criteria

- [ ] Same inputs produce stable output.
- [ ] Course profile changes are visible in composed prompt.
- [ ] Retrieved evidence is included in a structured section.

### Verification

- `pnpm test -- prompt-composer`
