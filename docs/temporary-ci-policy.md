# Temporary CI policy — 2026-09-27

The owner paused FlashUp work and prioritized Git/GitHub setup for Cardine and Study Agent Harness. PR CI temporarily runs full Python/Flywheel verification, SwiftLint, Swift package tests and an unsigned simulator build. It does not certify full app/UI behavior or iOS 17 fallback coverage.

The full iOS 26 and iOS 17.5 app/UI suites remain in the workflow. Run them manually with the `run_ui_tests` input enabled when app work resumes, repair any remaining failures, and restore them as required PR verification before declaring app acceptance complete. Never interpret the reduced technical green status as semantic review or permission to merge/release.

The trash recovery test now follows the existing Library entry point rather than a nonexistent Settings control. This correction remains subject to the manual UI suite. The workflow PR stays draft while that app acceptance remains incomplete.
