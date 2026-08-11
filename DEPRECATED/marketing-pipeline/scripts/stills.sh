#!/bin/bash
# Exports the PNG stills the landing page, the thumbnails and the hero breakout need
# (spec §3.4).
#
# Stills are driven by short Maestro flows rather than pulled out of the video: a frame
# extracted from an H.264 clip carries compression artefacts and whatever motion blur the
# recorder introduced, and §3.4 asks for native resolution, unscaled and uncompressed.
#
# Usage: stills.sh [deck slug]

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SLUG="${1:-${DECK}}"
UDID="$(cat "${PIPELINE_ROOT}/out/.recording-udid" 2>/dev/null || printf '')"
[[ -n "${UDID}" ]] || fail "No simulator. Run 'make setup' first."

require_tool maestro "Install it with: curl -Ls \"https://get.maestro.mobile.dev\" | bash"

mkdir -p "${STILLS_DIR}" "${HERO_STILLS_DIR}"

shopt -s nullglob
STILL_FLOWS=("${PIPELINE_ROOT}"/flows/stills/*.yaml)
if [[ ${#STILL_FLOWS[@]} -eq 0 ]]; then
	warn "No still flows in flows/stills/. Skipping."
	exit 0
fi

for flow in "${STILL_FLOWS[@]}"; do
	name="$(basename "${flow}" .yaml)"
	"${PIPELINE_ROOT}/scripts/seed.sh" "${UDID}" "${SLUG}"

	log "Still: ${name}"
	MAESTRO_UDID="${UDID}" maestro --device "${UDID}" test "${flow}" || {
		fail "Still flow ${name} failed."
	}

	# Hero plates are the element a breakout lifts (§1.14) and live apart, so the
	# compositor never has to guess which still is a clean plate.
	case "${name}" in
	hero_*) target="${HERO_STILLS_DIR}/${name#hero_}.png" ;;
	*) target="${STILLS_DIR}/${name}.png" ;;
	esac

	xcrun simctl io "${UDID}" screenshot --type png "${target}"
	printf '    %s\n' "${target#"${PIPELINE_ROOT}"/}"
done
