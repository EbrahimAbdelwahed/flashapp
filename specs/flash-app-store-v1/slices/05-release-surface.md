# Slice 05 — Honest 1.0 product surface

## Contract unlocked

The release build exposes only complete personal features and teaches the user without an
empty first run or false sync/privacy claim.

## API seam and ownership

`RootTabView` owns Today/Library/Settings navigation. `TutorialState` owns first-run state;
a demo installer calls the real repository idempotently. Settings consumes real sync,
backup and reminder contracts. No feature view owns persistence details.

## Human-visible artifact

Production-route screenshots and flows for fresh install/skip, Today→Statistics,
Library→Import, Settings sync/backup/reminder denial, in EN/IT on iPhone/iPad.

## Verification

- Exactly three tabs; Groups route/copy/tutorial and simulated sync state are absent.
- Completing or skipping onboarding installs original generalist demo content once.
- Reminder permission starts at the toggle; denial offers localized iOS Settings guidance.
- Privacy/support copy matches automatic private iCloud, complete backup and no tracking.
- Dynamic Type, VoiceOver, contrast, reduced motion, keyboard and iPad layout pass.
- Capture pre/post production-route screenshots and prove frames changed where intended.
- Run the `screenshot-critique` skill unprimed as the final visual check before acceptance.
  Use `compare-screenshots` only where a prior/reference frame exists, judging the changed
  variable rather than demanding pixel identity.

## Human checkpoint

Open final shots with `preview-shots`, allow a short non-blocking owner review window, then
record the evidence-based call and proceed if no response arrives.

## Feedback that changes this slice

Only a change to information architecture, onboarding promise or public privacy wording;
visual polish stays within `docs/ux-principles.md`.

