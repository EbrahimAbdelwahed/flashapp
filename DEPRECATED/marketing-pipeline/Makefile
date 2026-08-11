# Flash Up — marketing clip pipeline.
#
# Phase A (recording) is complete. Phase B (assembly in Remotion) is added by the
# assembly bead; its targets appear here once remotion/ exists.
#
# Every target is documented in README.md.

SHELL := /bin/bash
SCRIPTS := scripts
DECK ?= anatomia

# Flows are discovered rather than listed, so adding flows/clipN_thing.yaml is enough to
# put it in `make clips`. Clip id is the flow filename without its extension.
FLOWS := $(notdir $(wildcard flows/*.yaml))
CLIP_IDS := $(basename $(FLOWS))

.PHONY: help setup clips verify stills audio audition clean $(addprefix clip-,$(CLIP_IDS))

help:
	@printf '\nFlash Up clip pipeline — deck: $(DECK)\n\n'
	@printf '  make setup                 boot the simulator, strip screencast tells, build and install\n'
	@printf '  make clips [DECK=slug]     record every flow in flows/ plus stills\n'
	@printf '  make clip-<id> [DECK=slug] record one clip\n'
	@printf '  make stills [DECK=slug]    export the PNG stills only\n'
	@printf '  make verify [DECK=slug]    ffprobe every clip: duration, aspect, 9:41, frame pacing\n'
	@printf '  make audio SRC=f NAME=n    normalise a music bed to -20 LUFS, report BPM and offset\n'
	@printf '  make audition BEDS="a b"   level-matched A/B/C of prepared beds, plus a beat-grid check\n'
	@printf '  make clean                 remove out/ (recordings and derived data)\n\n'
	@printf 'Known clips: $(CLIP_IDS)\n\n'

setup:
	@$(SCRIPTS)/prepare_sim.sh

clips: setup
	@if [ -z "$(FLOWS)" ]; then \
		printf '\033[1;31m fail\033[0m No flows in flows/. Nothing to record.\n' >&2; exit 1; \
	fi
	@for flow in $(FLOWS); do \
		$(SCRIPTS)/record_clip.sh "$${flow%.yaml}" "$$flow" "$(DECK)" || exit 1; \
	done
	@$(MAKE) --no-print-directory stills DECK=$(DECK)

$(addprefix clip-,$(CLIP_IDS)):
	@$(SCRIPTS)/record_clip.sh "$(patsubst clip-%,%,$@)" "$(patsubst clip-%,%,$@).yaml" "$(DECK)"

stills:
	@$(SCRIPTS)/stills.sh "$(DECK)"

verify:
	@$(SCRIPTS)/verify.sh "$(DECK)"

# Music is a variant axis (§5.2) and a new track re-times every cut, so swapping one has to
# be a single command rather than a manual pass in an audio editor.
audio:
	@if [ -z "$(SRC)" ] || [ -z "$(NAME)" ]; then \
		printf 'usage: make audio SRC=<file> NAME=<bed_name>\n' >&2; exit 1; \
	fi
	@$(SCRIPTS)/prepare_audio.sh "$(SRC)" "$(NAME)"

# Level-matched A/B/C of prepared beds. Comparing candidates in a player is not a fair
# test: the loudest master wins regardless of whether it suits the film.
audition:
	@if [ -z "$(BEDS)" ]; then \
		printf 'usage: make audition BEDS="cand_a cand_b cand_c"\n' >&2; exit 1; \
	fi
	@$(SCRIPTS)/audition_audio.sh $(BEDS)

# --- Phase B: assembly (§4.4) ---

REMOTION := remotion
BRIEFS := $(notdir $(basename $(wildcard briefs/*.json)))

.PHONY: studio videos $(addprefix video-,$(BRIEFS))

studio:
	@cd $(REMOTION) && npx remotion studio src/index.ts --port=3010

videos:
	@for brief in $(BRIEFS); do $(MAKE) --no-print-directory video-$$brief || exit 1; done

# Concurrency is capped deliberately. The blooms in §1.5 are large blurred gradients and
# the shadows are wide; both rasterise on CPU under headless Chrome, and letting every core
# open a tab makes them contend rather than finish sooner.
$(addprefix video-,$(BRIEFS)):
	$(eval ID := $(patsubst video-%,%,$@))
	$(eval TAG := $(shell sed -n 's/.*"variant_tag" *: *"\([^"]*\)".*/\1/p' briefs/$(ID).json))
	@if [ -z "$(TAG)" ]; then printf 'briefs/$(ID).json has no variant_tag (§5.6)\n' >&2; exit 1; fi
	@mkdir -p out/videos
	@cd $(REMOTION) && npx remotion render src/index.ts MarketingVideo \
		../out/videos/$(TAG).mp4 --props=../briefs/$(ID).json \
		--pixel-format=yuv420p --concurrency=4 --log=error
	@$(SCRIPTS)/master_audio.sh out/videos/$(TAG).mp4
	@$(SCRIPTS)/tag_video.sh out/videos/$(TAG).mp4 "$(TAG)"

clean:
	@printf 'Removing out/ …\n'
	@rm -rf out
