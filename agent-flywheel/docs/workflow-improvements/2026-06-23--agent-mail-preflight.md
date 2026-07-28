# Workflow Improvement: Agent Mail Preflight

Date: 2026-06-23
Classification: apply-now

## Problem

Agent Mail commands can fail for reasons unrelated to the target project:

- Codex sandbox denies access to `~/.local/share/mcp-agent-mail`.
- stale mailbox activity locks can block `start-session`;
- Agent Mail may require recovery after SQLite corruption;
- concurrent probes against the same storage root can leave busy locks or transient SQLite WAL sidecars;
- `am doctor check --json` can be healthy while stricter archive/DB drift checks still report detect-only P1 findings;
- descriptive `--agent-name` values are rejected;
- unquoted globs are expanded by the shell before Agent Mail receives them.

Without a preflight, agents waste time debugging target-project workflows when the mailbox itself is the failing layer.

## Change

Before using Agent Mail on a new target project, run a preflight:

```bash
PATH="$HOME/.local/bin:$PATH" am doctor locks --json
PATH="$HOME/.local/bin:$PATH" am doctor check --json
PATH="$HOME/.local/bin:$PATH" am doctor health
```

Then start sessions through `scripts/flywheel-core.py start-session` with quoted globs and no explicit `--agent-name` unless a valid generated identity is already known.

Use `scripts/flywheel-core.py agent-mail-preflight --project <target>` as the canonical wrapper. Treat its fields as:

- `functional=true`: commands can read/write enough for sessions, reservations, and messages.
- `usable=true`: the basic command path works and `am doctor check --json` reports a healthy mailbox.
- `deep_health_ok=true`: `am doctor health` exits cleanly and detect-only P1 archive/reservation drift probes find no issues.
- `robot_health=ok`: `am robot status` reports clean coordination state.
- `ready=true`: all of the above are clean enough for unattended coordination.

Do not treat `functional=true` or `usable=true` as equivalent to `ready=true`.

Run Agent Mail probes serially. Do not parallelize `am doctor`, `am robot`, reservation, or mail commands against the same storage root.

Release test or abandoned worker reservations with:

```bash
scripts/flywheel-core.py release-reservations --project <target> --agent <agent> --ids <id>
```

## Expected Effect

- Reduces false negatives caused by sandbox permissions.
- Separates mailbox health problems from target project coordination problems.
- Prevents invalid agent-name retries.
- Makes Agent Mail verification repeatable for future bootstrap runs.

## Follow-Up

If `am doctor health` reports detect-only drift, do not run `am doctor reconstruct --yes` unless the archive is explicitly accepted as authoritative. A reconstruct preview may drop DB-only messages or reservations.
