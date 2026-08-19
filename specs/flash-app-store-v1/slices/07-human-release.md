# Slice 07 — Human Apple-account and submission gates

## Contract unlocked

The exact tested build can be signed, processed by Apple, verified through internal
TestFlight and submitted only after every required human gate has real evidence.

## API seam and ownership

The release governor records evidence; the account holder performs Apple Developer and App
Store Connect mutations. Agents provide commands/checklists but cannot infer PASS.

## Human-run artifact

Team/App ID/bundle/container setup, development and production schema evidence, entitlement
dump, Validate App result, internal TestFlight smoke matrix, public URLs, price schedule,
metadata/screenshots and final GO/NO-GO record.

## Verification

- Personal sync passes on at least two devices using the same Apple Account, including
  offline/reconnect/convergence/relaunch and soft-delete/restore/permanent-erasure
  propagation.
- Signed archive proves Xcode/iOS SDK 26+, identifiers, production entitlements and privacy
  report.
- The exact processed TestFlight build passes the reviewer journey on iPhone/iPad, EN/IT;
  the processed iPad app also passes install/launch/core-journey and accessibility smoke on
  an Apple Silicon Mac.
- Support/privacy URLs are public HTTPS and match the build.
- Price is €2.99 with a dated €4.99 change one calendar month after actual launch.
- Any missing evidence remains `HUMAN_REQUIRED`/`UNVERIFIED` and blocks GO.

## Feedback that changes this slice

Only evidence from the account holder, Apple processing, TestFlight testers or App Review.
No repository-only approximation closes these gates.
