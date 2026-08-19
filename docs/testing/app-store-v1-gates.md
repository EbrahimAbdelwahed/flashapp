# FlashApp 1.0 App Store gate ledger

Allowed states: `PASS`, `FAIL`, `UNVERIFIED`, `HUMAN_REQUIRED`, `N/A`.

Rules:

- `UNVERIFIED` blocks release when the gate is required.
- `HUMAN_REQUIRED` is not a softer PASS; it blocks release until the account holder records
  primary evidence.
- `N/A` requires evidence that the capability/feature is absent from the exact build.
- Repository tests cannot close an archive, CloudKit production, TestFlight or App Store
  Connect gate.

| Gate | State | Evidence / unblocker |
| --- | --- | --- |
| Persistent relaunch | UNVERIFIED | sas-01/sas-02 on-disk evidence |
| Migration/recovery preserves store | PASS | sas-01 staged success/failure, digest, retention and lifecycle fixtures; independent security review |
| Offline personal journey | UNVERIFIED | sas-02/sas-05 matrix |
| Complete backup with media | UNVERIFIED | sas-04 round trip |
| Three-tab release surface | UNVERIFIED | sas-05 UI evidence |
| EN/IT completeness | UNVERIFIED | sas-05/sas-06 |
| VoiceOver/Dynamic Type/reduced motion | UNVERIFIED | sas-05/sas-06 |
| iPhone/iPad iOS 17/current | UNVERIFIED | sas-06 matrix |
| Apple Silicon Mac iPad-app smoke | UNVERIFIED | install, launch, core journey, keyboard/accessibility evidence |
| Dependency/license audit | UNVERIFIED | sas-06 inventory |
| Required Reason API/privacy report | HUMAN_REQUIRED | exact signed archive |
| Apple Developer membership/team | HUMAN_REQUIRED | owner activates account |
| Final App ID/bundle/container | HUMAN_REQUIRED | owner freezes identifiers |
| CloudKit development/production schema | HUMAN_REQUIRED | real container evidence |
| Same-account multi-device CloudKit E2E | HUMAN_REQUIRED | two-device checklist incl. offline/reconnect/delete/restore/erase |
| Legal identity/support/privacy URLs | HUMAN_REQUIRED | final public values/HTTPS pages |
| Signing/profile/entitlements | HUMAN_REQUIRED | signed archive dump |
| Validate App | HUMAN_REQUIRED | Xcode/App Store Connect result |
| Internal TestFlight processed build | HUMAN_REQUIRED | Apple processing + smoke matrix |
| Price €2.99 → €4.99 schedule | HUMAN_REQUIRED | actual launch date + ASC schedule |
| App Store submission | HUMAN_REQUIRED | explicit owner authorization |
