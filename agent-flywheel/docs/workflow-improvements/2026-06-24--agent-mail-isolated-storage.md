# Workflow Improvement: Agent Mail Isolated Storage

Date: 2026-06-24
Classification: apply-now

## Problem

Agent Mail's default global storage can retain historical DB/archive drift from test runs. This can make a new target project look unhealthy even when the flywheel wrappers, beads, and worker flow are correct.

Testing with Agent Mail `0.3.13` also showed that isolated CLI-created sessions, reservations, and messages can work functionally while strict archive durability checks still report detect-only P1 drift:

- message DB rows without canonical archive message files;
- file reservation DB rows without stable archive artifacts;
- `am robot status` reporting `health=degraded` even when basic commands succeed.

## Change

Use `flywheel-core.py` Agent Mail commands with `--mailbox-storage-root` for repeatable bootstrap and smoke tests. The wrapper now:

- sets `STORAGE_ROOT`;
- initializes the storage root as a git repo;
- sets `DATABASE_URL` to the storage-local SQLite file unless explicitly overridden;
- preserves strict preflight output so `usable=true` and `ready=true` remain distinct.

Keep isolated mailbox roots under ignored `sandbox/agent-mail-*` paths.

## Expected Effect

- Prevents global mailbox history from contaminating new flywheel validation.
- Makes Agent Mail smoke tests reproducible.
- Keeps durable coordination anchored in `br`, `bv`, task beads, worker briefs, decision requests, logs, and handoffs until Agent Mail archive repair is reliable.

## Follow-Up

Track upstream Agent Mail behavior. If a future version adds a safe DB-to-archive repair path or fixes CLI archive materialization, tighten `ready=true` back into the normal required gate for unattended coordination.
