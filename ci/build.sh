#!/bin/bash
# Release build wrapper.
#
# Default (no arguments): device-family build check on both simulators, which is what a
# machine without an Apple Developer team can verify.
# `ci/build.sh archive`: archives for TestFlight. Requires FLASHUP_DEVELOPMENT_TEAM to be
# set in Config/FlashUp.xcconfig (bead fu-15 / B0.5).

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:-simulators}"

case "${MODE}" in
simulators)
	for simulator in "${IPHONE_SIMULATOR}" "${IPAD_SIMULATOR}"; do
		log "Build ${simulator} (iOS ${IOS_TEST_VERSION})"
		xcodebuild build \
			-project "${PROJECT}" \
			-scheme "${SCHEME}" \
			-configuration Release \
			-destination "platform=iOS Simulator,name=${simulator},OS=${IOS_TEST_VERSION}" \
			-derivedDataPath "${DERIVED_DATA}" \
			CODE_SIGNING_ALLOWED=NO
	done
	;;
archive)
	ARCHIVE_PATH="${DERIVED_DATA}/FlashUp.xcarchive"
	log "Archive for TestFlight -> ${ARCHIVE_PATH}"
	xcodebuild archive \
		-project "${PROJECT}" \
		-scheme "${SCHEME}" \
		-configuration Release \
		-destination "generic/platform=iOS" \
		-archivePath "${ARCHIVE_PATH}" \
		-derivedDataPath "${DERIVED_DATA}"
	;;
*)
	echo "usage: ci/build.sh [simulators|archive]" >&2
	exit 2
	;;
esac

log "Build finished"
