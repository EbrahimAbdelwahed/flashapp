#!/bin/bash
# Boots the recording simulator, strips every screencast tell from it, and installs a
# fresh build of the app (spec §3.1).
#
# Usage: prepare_sim.sh [simulator name]

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SIMULATOR="${1:-${IPHONE_SIMULATOR}}"
UDID="$(simulator_udid "${SIMULATOR}")"

log "Simulator: ${SIMULATOR} (${UDID})"

# 1. Touch indicators off. Ripples are composited in post (§1.8), and the grey system
#    circle is the single most recognisable "this is a screencast" tell. The preference is
#    read at Simulator launch, so the app is restarted below.
CURRENT_TOUCHES="$(defaults read com.apple.iphonesimulator ShowSingleTouches 2>/dev/null || printf '0')"
if [[ "${CURRENT_TOUCHES}" != "0" ]]; then
	log "Disabling ShowSingleTouches and restarting Simulator.app"
	defaults write com.apple.iphonesimulator ShowSingleTouches 0
	osascript -e 'tell application "Simulator" to quit' >/dev/null 2>&1 || true
	while pgrep -xq Simulator; do sleep 0.5; done
fi

# 2. Boot and wait for a device that actually answers, not just one marked Booted.
if ! xcrun simctl list devices | grep -q "${UDID}) (Booted)"; then
	log "Booting"
	xcrun simctl boot "${UDID}"
fi
xcrun simctl bootstatus "${UDID}" -b

open -a Simulator --args -CurrentDeviceUDID "${UDID}"

# 3. Light mode for every clip: a bright screen on a dark canvas makes the device read as
#    a light source, which §1.2 calls the single biggest lever in the whole look.
log "Appearance: light"
xcrun simctl ui "${UDID}" appearance light

# 4. Keynote status bar.
log "Status bar: 9:41, full battery, full signal"
apply_status_bar "${UDID}"

# 5. Build and install. Debug, because the recording never leaves this machine and the
#    build is an order of magnitude faster to iterate on.
log "Building ${SCHEME}"
xcodebuild build \
	-project "${XCODE_PROJECT}" \
	-scheme "${SCHEME}" \
	-configuration Debug \
	-destination "platform=iOS Simulator,id=${UDID}" \
	-derivedDataPath "${DERIVED_DATA}" \
	CODE_SIGNING_ALLOWED=NO \
	-quiet

APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
[[ -d "${APP_PATH}" ]] || fail "Build produced no app at ${APP_PATH}"

log "Installing ${APP_PATH}"
xcrun simctl install "${UDID}" "${APP_PATH}"

log "Ready. Recording device: ${UDID}"
printf '%s' "${UDID}" >"${PIPELINE_ROOT}/out/.recording-udid"
