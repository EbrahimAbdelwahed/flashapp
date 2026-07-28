#!/bin/bash
# SwiftLint wrapper. Fails the build on lint errors (spec §0.4).
#
# SwiftLint is not vendored: install it with `brew install swiftlint`.
# Set STRICT_LINT=1 (CI does) to turn a missing SwiftLint into a failure instead of a
# skip, so a developer machine without it can still run the rest of the pipeline.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if ! command -v swiftlint >/dev/null 2>&1; then
	if [[ "${STRICT_LINT:-0}" == "1" ]]; then
		echo "error: swiftlint is not installed (brew install swiftlint)" >&2
		exit 1
	fi
	echo "warning: swiftlint is not installed — skipping lint (brew install swiftlint)" >&2
	exit 0
fi

log "SwiftLint"
cd "${REPO_ROOT}"
swiftlint lint --strict --config "${REPO_ROOT}/.swiftlint.yml"
