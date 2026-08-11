#!/bin/bash
# Shared configuration and helpers for the clip pipeline.
#
# Everything the pipeline knows about the app lives here, so retargeting a different
# simulator or a renamed scheme is a one-file edit.

set -euo pipefail

PIPELINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${PIPELINE_ROOT}/.." && pwd)"

XCODE_PROJECT="${REPO_ROOT}/FlashUp.xcodeproj"
SCHEME="FlashUp"
BUNDLE_ID="com.flashup.app"
DERIVED_DATA="${PIPELINE_ROOT}/out/DerivedData"

# Spec §0: latest iPhone Pro-class device, portrait. The iPad is only used by the
# sync-preview clip (§3.7).
IPHONE_SIMULATOR="${IPHONE_SIMULATOR:-iPhone 17 Pro}"
IPAD_SIMULATOR="${IPAD_SIMULATOR:-iPad Pro 13-inch (M5)}"

# Which hand-authored deck the app seeds and the import flow picks up (§1.12, §5.2).
DECK="${DECK:-anatomia}"

CLIPS_DIR="${PIPELINE_ROOT}/out/clips/${DECK}"
STILLS_DIR="${PIPELINE_ROOT}/out/clips/stills"
HERO_STILLS_DIR="${STILLS_DIR}/hero"

# Maestro is a JVM tool and Homebrew keeps its openjdk keg-only, so a plain shell has no
# `java` on PATH. Resolved here rather than in the user's shell profile: the pipeline
# should run the same way from a terminal, a Makefile or CI.
if [[ -z "${JAVA_HOME:-}" && -d "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" ]]; then
	export JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
fi

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m fail\033[0m %s\n' "$*" >&2; exit 1; }

require_tool() {
	command -v "$1" >/dev/null 2>&1 || fail "$1 is not installed. $2"
}

# Display name of a deck slug, as it should read on screen (§1.12: never `Deck 1`).
deck_display_name() {
	case "$1" in
	anatomia) printf 'Anatomia — splancnologia' ;;
	biochimica) printf 'Biochimica — ciclo di Krebs' ;;
	farmacologia) printf 'Farmacologia — antibiotici β-lattamici' ;;
	*) fail "Deck '$1' has no display name. Add one to deck_display_name() rather than letting a slug reach the screen." ;;
	esac
}

deck_csv() {
	local csv="${PIPELINE_ROOT}/assets/decks/$1.csv"
	[[ -f "${csv}" ]] || fail "Deck CSV not found: ${csv}"
	printf '%s' "${csv}"
}

# Resolves a simulator name to a udid, booting nothing.
simulator_udid() {
	local name="$1"
	local udid
	udid="$(xcrun simctl list devices available -j |
		/usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data["devices"].items():
    for device in devices:
        if device["name"] == name:
            print(device["udid"])
            raise SystemExit
' "${name}")"
	[[ -n "${udid}" ]] || fail "No available simulator named '${name}'. Run: xcrun simctl list devices available"
	printf '%s' "${udid}"
}

# The keynote status bar (§1.12). Re-applied per clip, never once per session: the
# simulator drops the override on some state changes and a 14:37 clock is a reshoot.
apply_status_bar() {
	xcrun simctl status_bar "$1" override \
		--time "9:41" \
		--batteryLevel 100 \
		--batteryState charged \
		--cellularMode active \
		--cellularBars 4 \
		--wifiMode active \
		--wifiBars 3 \
		--dataNetwork wifi
}
