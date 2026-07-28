#!/bin/bash
# Full local verification: lint, package tests (no simulator), app + UI tests on an
# iOS 17 iPhone simulator.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

"${REPO_ROOT}/ci/lint.sh"

log "swift test (FlashUpKit, macOS host — no simulator)"
cd "${PACKAGE_DIR}"
swift test

log "xcodebuild test (${IPHONE_SIMULATOR}, iOS ${IOS_TEST_VERSION})"
cd "${REPO_ROOT}"
xcodebuild test \
	-project "${PROJECT}" \
	-scheme "${SCHEME}" \
	-destination "platform=iOS Simulator,name=${IPHONE_SIMULATOR},OS=${IOS_TEST_VERSION}" \
	-derivedDataPath "${DERIVED_DATA}" \
	CODE_SIGNING_ALLOWED=NO

log "All checks passed"
