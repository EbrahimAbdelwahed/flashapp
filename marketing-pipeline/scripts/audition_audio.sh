#!/bin/bash
# Builds a level-matched A/B/C audition of candidate music beds (spec §1.9).
#
# Choosing a track by opening three files in a player is not a fair test: whichever is
# mastered loudest wins, every time, regardless of whether it suits the film. So every
# candidate is normalised to the same −20 LUFS first, trimmed to the same length starting
# at its own first downbeat, and laid end to end behind numbered markers.
#
# Two files come out, because there are two different questions:
#
#   audition_mood.mp3 — clean. Which one belongs to this product?
#   audition_grid.mp3 — the same segments with a click on the computed beat grid. If the
#                       clicks drift out of the music, the BPM estimate is wrong and every
#                       cut in the film would inherit that error.
#
# Usage: audition_audio.sh <bed name> [bed name ...]
#        (bed names are the ones prepare_audio.sh produced)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_tool ffmpeg "Install it with: brew install ffmpeg"

[[ $# -ge 2 ]] || fail "Give at least two prepared beds to compare."

AUDIO_DIR="${PIPELINE_ROOT}/assets/audio"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Long enough to judge, short enough that all three fit in one sitting.
SEGMENT_SECONDS=20
MARKER_HZ=880
CLICK_HZ=1500

mood_parts=()
grid_parts=()
index=0

for name in "$@"; do
	index=$((index + 1))
	bed="${AUDIO_DIR}/${name}.mp3"
	manifest="${AUDIO_DIR}/${name}.json"
	[[ -f "${bed}" ]] || fail "No prepared bed at ${bed}. Run: make audio SRC=<file> NAME=${name}"
	[[ -f "${manifest}" ]] || fail "No manifest at ${manifest}"

	bpm="$(sed -n 's/.*"bpm" *: *\([0-9.]*\).*/\1/p' "${manifest}")"
	offset="$(sed -n 's/.*"offset" *: *\([0-9.]*\).*/\1/p' "${manifest}")"
	seconds_per_beat="$(awk -v b="${bpm}" 'BEGIN { printf "%.6f", 60.0 / b }')"

	log "${index}. ${name} — ${bpm} BPM, first downbeat ${offset}s"

	# N short beeps announce which candidate is playing, so the listener never has to
	# remember an order.
	marker="${WORK}/marker${index}.wav"
	marker_seconds="$(awk -v n="${index}" 'BEGIN { printf "%.2f", n * 0.35 + 0.5 }')"
	ffmpeg -hide_banner -loglevel error -y \
		-f lavfi -i "aevalsrc='0.25*sin(2*PI*${MARKER_HZ}*t)*lt(mod(t,0.35),0.12)':d=${marker_seconds}:s=48000:c=stereo" \
		-ac 2 "${marker}"

	# Trimmed from the first downbeat, so every candidate is judged from a musical start
	# rather than from whatever silence its file happens to open with.
	segment="${WORK}/segment${index}.wav"
	ffmpeg -hide_banner -loglevel error -y -ss "${offset}" -t "${SEGMENT_SECONDS}" \
		-i "${bed}" -ac 2 -ar 48000 "${segment}"

	# A decaying pulse on every beat of the computed grid.
	clicks="${WORK}/clicks${index}.wav"
	ffmpeg -hide_banner -loglevel error -y \
		-f lavfi -i "aevalsrc='0.35*sin(2*PI*${CLICK_HZ}*t)*exp(-45*mod(t,${seconds_per_beat}))':d=${SEGMENT_SECONDS}:s=48000:c=stereo" \
		"${clicks}"

	clicked="${WORK}/clicked${index}.wav"
	ffmpeg -hide_banner -loglevel error -y -i "${segment}" -i "${clicks}" \
		-filter_complex "[0:a][1:a]amix=inputs=2:duration=first:normalize=0[out]" \
		-map "[out]" -ac 2 -ar 48000 "${clicked}"

	mood_parts+=("${marker}" "${segment}")
	grid_parts+=("${marker}" "${clicked}")
done

concat_to() {
	local output="$1"
	shift
	local list="${WORK}/list.txt"
	: >"${list}"
	for part in "$@"; do printf "file '%s'\n" "${part}" >>"${list}"; done
	ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "${list}" \
		-ar 48000 -b:a 192k "${output}"
}

MOOD="${AUDIO_DIR}/audition_mood.mp3"
GRID="${AUDIO_DIR}/audition_grid.mp3"

concat_to "${MOOD}" "${mood_parts[@]}"
concat_to "${GRID}" "${grid_parts[@]}"

log "Mood test: ${MOOD#"${PIPELINE_ROOT}"/}"
log "Grid test: ${GRID#"${PIPELINE_ROOT}"/}"
printf '\n  All candidates at the same loudness, so the loudest master cannot win by volume.\n'
printf '  Beeps before each: 1 beep = first argument, 2 = second, and so on.\n\n'
