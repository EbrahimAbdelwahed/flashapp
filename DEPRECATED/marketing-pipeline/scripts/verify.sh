#!/bin/bash
# Gate between recording and editing (spec §3.6, §1.15).
#
# Every clip is checked for: existence and non-trivial length, portrait aspect ratio, the
# 9:41 status bar on the first frame, and frame pacing. A clip that judders inside an
# otherwise flawless canvas produces exactly the amateur read the art direction exists to
# avoid, and no amount of compositing hides it — so it is caught here, not in the edit.
#
# Usage: verify.sh [deck slug]

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_tool ffprobe "Install it with: brew install ffmpeg"

SLUG="${1:-${DECK}}"
CLIP_DIR="${PIPELINE_ROOT}/out/clips/${SLUG}"
[[ -d "${CLIP_DIR}" ]] || fail "No clips for deck '${SLUG}'. Run 'make clips DECK=${SLUG}' first."

# Pacing tolerances from §1.15.
MAX_JITTER_RATIO="0.15"
MAX_GAP_FRAMES="2"
MIN_DURATION="3.0"

CHECKER="${PIPELINE_ROOT}/out/StatusBarCheck"
SOURCE="${PIPELINE_ROOT}/scripts/StatusBarCheck.swift"
if [[ ! -x "${CHECKER}" || "${SOURCE}" -nt "${CHECKER}" ]]; then
	log "Compiling the status-bar checker"
	mkdir -p "$(dirname "${CHECKER}")"
	swiftc -O -o "${CHECKER}" "${SOURCE}"
fi

WAIVERS="${PIPELINE_ROOT}/assets/pacing-waivers.txt"
FRAME_DIR="${PIPELINE_ROOT}/out/clips/stills/firstframe"
mkdir -p "${FRAME_DIR}"

FAILURES=0
printf '\n  %-26s %9s %12s %7s %9s %8s\n' CLIP DURATION RESOLUTION FPS DROPPED CLOCK
printf '  %s\n' "------------------------------------------------------------------------------"

shopt -s nullglob
CLIPS=("${CLIP_DIR}"/*.mp4)
[[ ${#CLIPS[@]} -gt 0 ]] || fail "No .mp4 files in ${CLIP_DIR}"

for clip in "${CLIPS[@]}"; do
	name="$(basename "${clip}" .mp4)"
	notes=()

	# `|| true`: the piped input has no trailing newline, so `read` reports EOF with a
	# non-zero status even though it assigned every variable — and under `set -e` that
	# ends the run before a single clip is reported.
	read -r width height rate < <(
		ffprobe -v error -select_streams v:0 \
			-show_entries stream=width,height,r_frame_rate \
			-of default=noprint_wrappers=1:nokey=1 "${clip}" | tr '\n' ' '
	) || true
	duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${clip}")"
	fps="$(awk -F/ '{printf "%.2f", ($2 ? $1/$2 : $1)}' <<<"${rate}")"

	awk -v d="${duration}" -v m="${MIN_DURATION}" 'BEGIN { exit !(d+0 >= m+0) }' ||
		notes+=("shorter than ${MIN_DURATION}s")

	# Portrait only. A landscape or square clip means the wrong device or a rotated
	# simulator, and §4.2 forbids fixing it by cropping the app UI.
	awk -v w="${width}" -v h="${height}" 'BEGIN { exit !(h+0 > w+0) }' ||
		notes+=("not portrait (${width}x${height})")

	report="$(python3 "${PIPELINE_ROOT}/scripts/analyse_clip.py" "${clip}")"
	json_field() { sed -n "s/.*\"$1\": *\([0-9.]*\).*/\1/p" <<<"${report}"; }

	jitter_ratio="$(json_field worst_jitter_ratio)"
	motion_fps="$(json_field motion_fps)"
	suggested_in="$(json_field suggested_in)"
	late_frames="$(json_field late_frames)"
	measured="$(json_field measured_intervals)"

	pacing="$(awk -v j="${jitter_ratio:-0}" 'BEGIN { printf "%.0f%%", j * 100 }')"

	# The analyser reports the problems; this loop only presents them. Keeping the §1.15
	# thresholds in one place stops the shell and the Python drifting apart.
	#
	# `|| true` matters: with `set -e`, a grep that matches nothing exits non-zero and
	# takes the whole script with it — which would abort the run on a clip with no
	# problems at all, the one case that must not fail.
	problems="$(sed -n 's/.*"problems": \[\(.*\)\].*/\1/p' <<<"${report}" |
		grep -o '"[^"]*"' | sed 's/^"//;s/"$//' || true)"

	while IFS= read -r problem; do
		[[ -z "${problem}" ]] || notes+=("${problem}")
	done <<<"${problems}"

	frame="${FRAME_DIR}/${name}.png"
	ffmpeg -v error -y -i "${clip}" -vf "select=eq(n\,0)" -vframes 1 "${frame}" 2>/dev/null
	if clock_reading="$("${CHECKER}" "${frame}" 2>&1)"; then
		clock="9:41"
	else
		clock="wrong"
		notes+=("status bar: ${clock_reading}")
	fi

	waiver="$(sed -n "s/^${name}: *//p" "${WAIVERS}" 2>/dev/null || true)"

	if [[ ${#notes[@]} -eq 0 ]]; then
		status_colour='\033[0;32m'
	elif [[ -n "${waiver}" ]]; then
		# Waived, not passed. The measurements are still printed above; what the waiver
		# changes is only whether the run fails.
		status_colour='\033[0;33m'
	else
		status_colour='\033[0;31m'
		FAILURES=$((FAILURES + 1))
	fi

	printf "  ${status_colour}%-26s\033[0m %8.2fs %12s %7s %9s %8s\n" \
		"${name}" "${duration}" "${width}x${height}" "${motion_fps:-?}" \
		"${late_frames:-?}/${measured:-?}" "${clock}"

	for note in ${notes[@]+"${notes[@]}"}; do
		printf '      \033[0;31m·\033[0m %s\n' "${note}"
	done

	[[ -n "${waiver}" ]] && printf '      \033[0;33mwaived:\033[0m %s\n' "${waiver}"

	# The recorder rolls before the flow starts driving, and Maestro's own start-up sits
	# inside that window. Rather than trim the file — which would re-encode footage the
	# renderer is about to re-encode anyway — report where the action begins so the brief
	# can use it as the segment's `in` (§4.3).
	[[ -n "${suggested_in}" ]] && printf '      suggested brief "in": %ss\n' "${suggested_in}"
done

printf '\n'
if [[ "${FAILURES}" -gt 0 ]]; then
	fail "${FAILURES} clip(s) rejected. Re-record them, or fall back to a physical device (§1.15)."
fi
log "All clips passed."
