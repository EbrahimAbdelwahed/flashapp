#!/bin/bash
# Shared settings for the Flash Up CI wrappers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROJECT="${REPO_ROOT}/FlashUp.xcodeproj"
SCHEME="FlashUp"
PACKAGE_DIR="${REPO_ROOT}/Packages/FlashUpKit"

# Spec §A12: unit and UI tests run on an iOS 17 iPhone simulator.
IOS_TEST_VERSION="${IOS_TEST_VERSION:-17.4}"
IPHONE_SIMULATOR="${IPHONE_SIMULATOR:-iPhone 15}"
IPAD_SIMULATOR="${IPAD_SIMULATOR:-iPad Pro 11-inch (M4)}"

DERIVED_DATA="${DERIVED_DATA:-${REPO_ROOT}/DerivedData}"

log() {
	printf '\n\033[1m==> %s\033[0m\n' "$1"
}
