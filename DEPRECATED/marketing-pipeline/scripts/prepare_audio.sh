#!/bin/bash
# Prepares a music bed and writes the numbers a brief needs (spec §1.9).
#
# Three things have to be true before a brief can be written: the bed sits at −20 LUFS so
# the UI samples have room above it, the BPM is known, and the first downbeat is known.
# The beat grid is computed from the last two, and every segment boundary and overlay snaps
# to it. An edit assembled first and scored afterwards never locks in — which is why this
# runs before any timing, not after.
#
# Usage: prepare_audio.sh <source audio> <bed name>

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SOURCE="${1:?source audio file required}"
NAME="${2:?bed name required, e.g. bed_calm_01}"

require_tool ffmpeg "Install it with: brew install ffmpeg"

[[ -f "${SOURCE}" ]] || fail "No such file: ${SOURCE}"

AUDIO_DIR="${PIPELINE_ROOT}/assets/audio"
mkdir -p "${AUDIO_DIR}"
BED="${AUDIO_DIR}/${NAME}.mp3"
MANIFEST="${AUDIO_DIR}/${NAME}.json"

# §1.9 puts the bed at −20 LUFS. Two-pass loudnorm: the first pass measures, the second
# corrects using those measurements. A single pass guesses, and on a track this far from
# target it guesses badly.
log "Measuring ${SOURCE##*/}"
MEASURED="$(ffmpeg -hide_banner -nostats -i "${SOURCE}" \
	-af loudnorm=I=-20:TP=-1.5:LRA=11:print_format=json -f null /dev/null 2>&1 |
	sed -n '/^{/,/^}/p')"

read_measured() { sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" <<<"${MEASURED}"; }

INPUT_I="$(read_measured input_i)"
INPUT_TP="$(read_measured input_tp)"
INPUT_LRA="$(read_measured input_lra)"
INPUT_THRESH="$(read_measured input_thresh)"
TARGET_OFFSET="$(read_measured target_offset)"

[[ -n "${INPUT_I}" ]] || fail "loudnorm produced no measurement for ${SOURCE}"

log "Source: ${INPUT_I} LUFS, ${INPUT_TP} dBTP, LRA ${INPUT_LRA} -> normalising to −20 LUFS"
ffmpeg -hide_banner -loglevel error -y -i "${SOURCE}" \
	-af "loudnorm=I=-20:TP=-1.5:LRA=11:measured_I=${INPUT_I}:measured_TP=${INPUT_TP}:measured_LRA=${INPUT_LRA}:measured_thresh=${INPUT_THRESH}:offset=${TARGET_OFFSET}:linear=true" \
	-ar 48000 -b:a 192k "${BED}"

DURATION="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "${BED}")"

# Tempo and first downbeat, from the normalised file so the numbers describe what the
# renderer will actually play.
ANALYSIS="$(ffmpeg -v error -i "${BED}" -ac 1 -ar 8000 -f s16le - 2>/dev/null |
	python3 "${PIPELINE_ROOT}/scripts/analyse_audio.py")"
BPM="$(cut -d' ' -f1 <<<"${ANALYSIS}")"
OFFSET="$(cut -d' ' -f2 <<<"${ANALYSIS}")"

cat >"${MANIFEST}" <<JSON
{
  "src": "assets/audio/${NAME}.mp3",
  "source_file": "$(basename "${SOURCE}")",
  "duration": ${DURATION},
  "bpm": ${BPM},
  "offset": ${OFFSET},
  "snap": true,
  "measured": {
    "source_lufs": ${INPUT_I},
    "source_true_peak": ${INPUT_TP},
    "bed_target_lufs": -20
  }
}
JSON

log "Bed:      ${BED#"${PIPELINE_ROOT}"/}"
log "Manifest: ${MANIFEST#"${PIPELINE_ROOT}"/}"
printf '    %.1fs  %s BPM  first downbeat %ss\n' "${DURATION}" "${BPM}" "${OFFSET}"
printf '\n  \033[1;33mBPM and offset are estimates.\033[0m Confirm them in Remotion Studio against\n'
printf '  the waveform before timing any segment — §1.9 makes them load-bearing.\n\n'
