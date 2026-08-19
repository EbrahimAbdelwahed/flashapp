# Intake: FlashApp 1.0 App Store hardening

Date: 2026-08-19
Run ID: `flash-app-store-v1`
Owner: orchestrator
Project: `/Users/ebrahimabdelwahed/Desktop/Dev/flashapp`

## Raw Feature Request

FlashApp 1.0 App Store hardening: personal automatic iCloud sync through one Private.sqlite NSPersistentCloudKitContainer; Groups deferred; complete media backups; honest Apple-account gates

## Orchestrator Alignment Checklist

- [x] Restate the intended user outcome.
- [x] Identify product, architecture, data, UI, privacy, test and release surfaces.
- [x] List irreversible or high-cost decisions and record owner approval in ADR-006.
- [x] List safe assumptions and separate them from human Apple-account gates.
- [x] Verify volatile Apple requirements against current official sources before planning.

## Initial Questions

- First useful slice: versioned local `Private.sqlite` foundation and non-destructive
  recovery, which can proceed before Apple account activation.
- Explicit non-goals: Groups/shared store, StoreKit/IAP, accounts, tracking, external beta,
  remote publishing, and `assets/emma-avatar/`.
- Proof is defined per slice; account/schema/signing/archive/TestFlight/ASC gates remain
  `HUMAN_REQUIRED` until primary evidence exists.
