#!/bin/bash
# Writes the variant tag into the mp4 container (spec §5.6, place 3 of five).
#
# Remotion prepends "Made with Remotion <version>; " to any comment it writes, so the tag
# cannot simply be passed to the renderer — a later `grep` over the archive would not match
# it. This rewrites the comment atom afterwards, without re-encoding a single frame.
#
# Platforms strip container metadata on upload. This is for the internal archive: a file
# found on disk months later must still say which variant it is.
#
# Usage: tag_video.sh <video.mp4> <variant_tag>

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

VIDEO="${1:?video path required}"
TAG="${2:?variant tag required}"

[[ -f "${VIDEO}" ]] || fail "No such video: ${VIDEO}"

# §5.6's regex, enforced here as well as in the brief schema: the tag is the join key
# between a rendered file, a published post and a waitlist signup, and a malformed one
# silently breaks the whole measurement system.
[[ "${TAG}" =~ ^fu-[A-Z][0-9]{1,2}-[a-z]{3,4}-[a-z]{4}-h[0-9]{2}(-r[0-9]+)?$ ]] ||
	fail "Tag '${TAG}' does not match the §5.6 pattern"

# Remotion's own note: the comment value may not contain '='.
[[ "${TAG}" != *"="* ]] || fail "A variant tag may not contain '=' — ffmpeg metadata rejects it"

TEMP="${VIDEO%.mp4}.tagged.mp4"
ffmpeg -hide_banner -loglevel error -y -i "${VIDEO}" -c copy -movflags use_metadata_tags \
	-metadata comment="${TAG}" "${TEMP}"
mv "${TEMP}" "${VIDEO}"

WRITTEN="$(ffprobe -v error -show_entries format_tags=comment -of default=nw=1:nk=1 "${VIDEO}")"
[[ "${WRITTEN}" == "${TAG}" ]] || fail "Tag did not survive the rewrite: got '${WRITTEN}'"

log "Tagged ${VIDEO##*/} as ${TAG}"
