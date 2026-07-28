# Worker Profile: <worker-name>

## Reuse Trigger

Use this worker when <recurring task shape, technology, or quality concern>.

## Mandate

<Primary responsibility and success definition.>

## Scope

In scope:

- <Work this worker may perform>

Out of scope:

- <Work this worker must not perform>

## Required Context

Read first:

- `<path or doc>`

Current-doc research:

- <Required when a framework, tool, library, platform, or best practice may have changed; otherwise write "not needed".>

## Allowed Files

May edit:

- `<path>`

May inspect:

- `<path>`

Do not edit:

- `<path>`

## Forbidden Decisions

Stop and report back before deciding:

- <Architecture, product, prompt-policy, data-model, dependency, migration, or ownership decision>

## Quality Gates

- <Correctness gate>
- <Maintainability gate>
- <Domain or source-grounding gate>
- <Test or verification gate>

## Verification

Run:

```bash
<command>
```

If verification cannot run, report the reason and the narrowest manual check completed.

## Report Format

Return:

- files changed;
- behavior implemented;
- verification results;
- profile constraints followed;
- unresolved questions;
- recommended next worker or review step.
