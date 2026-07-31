#!/bin/bash
# Puts a known library in front of the camera (spec §3.2).
#
# Wipes the app, reinstalls it, copies the hand-authored deck into the app's Documents
# container and launches with DEMO_MODE. The same CSV is then also the file the import
# flow picks up on camera, so the two never drift apart.
#
# Usage: seed.sh [udid] [deck slug]

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

UDID="${1:-$(cat "${PIPELINE_ROOT}/out/.recording-udid" 2>/dev/null || printf '')}"
[[ -n "${UDID}" ]] || fail "No simulator. Run 'make setup' first."
SLUG="${2:-${DECK}}"

CSV="$(deck_csv "${SLUG}")"
DISPLAY_NAME="$(deck_display_name "${SLUG}")"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
[[ -d "${APP_PATH}" ]] || fail "No built app at ${APP_PATH}. Run 'make setup' first."

# A flow that starts from whatever the previous flow left behind is not reproducible.
# Uninstall wipes the container outright; that is cheaper and more certain than trying to
# reset state from inside the app.
log "Resetting app state"
xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
xcrun simctl install "${UDID}" "${APP_PATH}"

CONTAINER="$(xcrun simctl get_app_container "${UDID}" "${BUNDLE_ID}" data)"
DEMO_DIR="${CONTAINER}/Documents/demo"
mkdir -p "${DEMO_DIR}"
cp "${CSV}" "${DEMO_DIR}/${SLUG}.csv"
log "Deck in place: Documents/demo/${SLUG}.csv"

# The status bar override does not survive an uninstall/install cycle.
apply_status_bar "${UDID}"

# simctl passes environment through SIMCTL_CHILD_-prefixed variables; there is no
# --setenv flag on `simctl launch`.
log "Launching in demo mode: ${DISPLAY_NAME}"
SIMCTL_CHILD_DEMO_MODE=1 \
	SIMCTL_CHILD_DEMO_DECK="${SLUG}" \
	SIMCTL_CHILD_DEMO_DECK_NAME="${DISPLAY_NAME}" \
	xcrun simctl launch "${UDID}" "${BUNDLE_ID}" >/dev/null

# The seed is synchronous but the first frame is not: give the interface time to lay out
# before anything starts recording it.
sleep 2
