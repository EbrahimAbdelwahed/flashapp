#!/bin/bash
# Records one clip: reset state, roll, run the flow, cut (spec §3.3).
#
# Usage: record_clip.sh <clip_id> <flow_file> [deck slug]

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CLIP_ID="${1:?clip id required}"
FLOW="${2:?flow file required}"
SLUG="${3:-${DECK}}"

require_tool maestro "Install it with: curl -Ls \"https://get.maestro.mobile.dev\" | bash"
require_tool ffprobe "Install it with: brew install ffmpeg"

FLOW_PATH="${PIPELINE_ROOT}/flows/${FLOW}"
[[ -f "${FLOW_PATH}" ]] || fail "Flow not found: ${FLOW_PATH}"

UDID="$(cat "${PIPELINE_ROOT}/out/.recording-udid" 2>/dev/null || printf '')"
[[ -n "${UDID}" ]] || fail "No simulator. Run 'make setup' first."

OUT_DIR="${PIPELINE_ROOT}/out/clips/${SLUG}"
mkdir -p "${OUT_DIR}"
OUT="${OUT_DIR}/${CLIP_ID}.mp4"

"${PIPELINE_ROOT}/scripts/seed.sh" "${UDID}" "${SLUG}"

log "Recording ${CLIP_ID}"
rm -f "${OUT}"
xcrun simctl io "${UDID}" recordVideo --codec h264 --force "${OUT}" &
RECORDER_PID=$!

# 1.5 s of idle head, so the edit has a handle to cut into (§3.3).
sleep 1.5

FLOW_STATUS=0
MAESTRO_UDID="${UDID}" maestro --device "${UDID}" test "${FLOW_PATH}" || FLOW_STATUS=$?

# 1.5 s of idle tail.
sleep 1.5

kill -INT "${RECORDER_PID}"
wait "${RECORDER_PID}" 2>/dev/null || true

if [[ "${FLOW_STATUS}" -ne 0 ]]; then
	SHOT="${PIPELINE_ROOT}/out/failures/${CLIP_ID}.png"
	mkdir -p "$(dirname "${SHOT}")"
	xcrun simctl io "${UDID}" screenshot "${SHOT}" >/dev/null 2>&1 || true
	fail "Flow ${FLOW} failed (exit ${FLOW_STATUS}). Screen at failure: ${SHOT}"
fi

[[ -s "${OUT}" ]] || fail "Recording produced no file at ${OUT}"

read -r DURATION WIDTH HEIGHT FPS < <(
	ffprobe -v error -select_streams v:0 \
		-show_entries format=duration -show_entries stream=width,height,r_frame_rate \
		-of default=noprint_wrappers=1:nokey=1 "${OUT}" | tr '\n' ' ' |
		awk '{print $4, $1, $2, $3}'
)

printf '    %-24s %6.2fs  %sx%s  %s\n' "${CLIP_ID}" "${DURATION}" "${WIDTH}" "${HEIGHT}" "${FPS}"
