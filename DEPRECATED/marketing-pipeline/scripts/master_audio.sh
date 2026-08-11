#!/bin/bash
# Brings a rendered video to the delivery loudness (spec §1.9).
#
# §1.9 sets two different targets and they are easy to conflate: the music bed sits at
# −20 LUFS so the UI samples have room above it, and the *finished mix* is −14 LUFS
# integrated with −1 dBTP true peak. The first is a level inside the edit, the second is a
# master. Rendering with the bed at its bed level and stopping there produces a film that is
# ten decibels quieter than everything around it in a feed — which reads as amateur before
# a single frame is judged.
#
# The video stream is copied, never re-encoded: only audio changes.
#
# Usage: master_audio.sh <video.mp4>

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

VIDEO="${1:?video path required}"
[[ -f "${VIDEO}" ]] || fail "No such video: ${VIDEO}"

TARGET_I="-14"
TARGET_TP="-1"

read_field() { sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" <<<"$2"; }

log "Measuring ${VIDEO##*/}"
MEASURED="$(ffmpeg -hide_banner -nostats -i "${VIDEO}" \
	-af "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=11:print_format=json" -f null /dev/null 2>&1 |
	sed -n '/^{/,/^}/p')"

INPUT_I="$(read_field input_i "${MEASURED}")"
[[ -n "${INPUT_I}" ]] || fail "loudnorm produced no measurement — does ${VIDEO##*/} have an audio track?"

log "Mix at ${INPUT_I} LUFS -> mastering to ${TARGET_I} LUFS / ${TARGET_TP} dBTP"

TEMP="${VIDEO%.mp4}.mastered.mp4"
ffmpeg -hide_banner -loglevel error -y -i "${VIDEO}" \
	-af "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=11:measured_I=${INPUT_I}:measured_TP=$(read_field input_tp "${MEASURED}"):measured_LRA=$(read_field input_lra "${MEASURED}"):measured_thresh=$(read_field input_thresh "${MEASURED}"):offset=$(read_field target_offset "${MEASURED}"):linear=true" \
	-c:v copy -c:a aac -b:a 192k "${TEMP}"
mv "${TEMP}" "${VIDEO}"

FINAL="$(ffmpeg -hide_banner -nostats -i "${VIDEO}" -af loudnorm=print_format=json -f null /dev/null 2>&1 |
	sed -n '/^{/,/^}/p')"
log "Master: $(read_field input_i "${FINAL}") LUFS, $(read_field input_tp "${FINAL}") dBTP"
