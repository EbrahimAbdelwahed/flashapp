# Slice 04B — Explicit profile transfer and scoped erasure

## Contract unlocked

Anonymous/Legacy content can be copied explicitly into the current identified profile
through the validated archive engine, while deletion affects only the named active profile.

## Verification

- Anonymous→account and Legacy→account are explicit copy-first operations.
- Content, media bytes, settings, schedules and logs survive; source stays unchanged.
- Failure leaves source usable and destination transactionally unchanged; retry is
  idempotent and safe for equivalent UUIDs.
- Malformed conflicts never cause destructive selection.
- Delete-all touches only active rows/media/session/cursor/scoped defaults/recovery.
- Identified deletion stays pending until successful CloudKit export; sign-out preserves
  that state. Deleting B never mutates A, Anonymous or Legacy.

## Feedback that changes this slice

Direct SQLite copy, simultaneous profile loads, automatic transfer or source deletion are
architecture violations and require a new decision.
