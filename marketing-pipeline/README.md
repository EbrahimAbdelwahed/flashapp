# Flash Up — marketing clip pipeline

Records the real app running real flows on an iOS Simulator, and (Phase B) assembles the
footage into 9:16 vertical videos in Remotion.

The normative document is [`../marketing-videos-spec.md`](../marketing-videos-spec.md).
This README explains how to run the thing; it does not restate the art direction. Where
this file and the spec disagree, the spec wins.

## Requirements

| Tool | Check | Install |
|---|---|---|
| Xcode + iOS Simulator | `xcrun simctl list devices` | App Store |
| ffmpeg / ffprobe | `ffprobe -version` | `brew install ffmpeg` |
| Maestro | `maestro --version` | `curl -Ls "https://get.maestro.mobile.dev" \| bash` |

Default devices: `iPhone 17 Pro` for every clip, `iPad Pro 13-inch (M5)` for the sync
preview. Override with `IPHONE_SIMULATOR=… IPAD_SIMULATOR=…`.

## Phase A — recording

```bash
make setup            # boot, de-screencast, build, install
make clips            # record every flow in flows/, then export stills
make verify           # reject anything that cannot go in an edit
```

Single clip, and a different faculty:

```bash
make clip-clip4_firstcard DECK=biochimica
```

### What `make setup` actually changes

- **`ShowSingleTouches` → 0**, and Simulator.app is restarted so it takes effect. The grey
  system touch circle is a screencast tell; taps are composited in post (spec §1.8). This
  is a preference on your machine and it stays off until you change it back.
- **Appearance → light** (§1.2). The app runs in light mode in every recording.
- **Status bar → 9:41**, full battery, full signal (§1.12), re-applied per clip because the
  override does not survive an uninstall/install cycle.

### What `make verify` enforces

Per clip: the file exists and is longer than 3 s; the frame is portrait; **the first frame
really reads 9:41** — the frame is OCR'd with Vision, not merely assumed from having run
the override; and **frame pacing** is within §1.15 (presentation-timestamp deltas with a
standard deviation ≤ 15% of the nominal frame interval, and no gap larger than two frame
intervals).

A clip that fails pacing is not fixable in the edit. Re-record it, or capture that flow on
a physical iPhone over QuickTime, which is the better source anyway — and note in
`docs/sources.md` which clips came from where.

### Measured: what the simulator actually delivers

On iPhone 17 Pro / iOS 26.4, four takes of the card flip:

| take | dropped frames | intervals measured | worst gap |
|---|---|---|---|
| 1 | 3 | 103 | 2.5x |
| 2 | 5 | 72 | 2.5x |
| 3 | 3 | 149 | 2.2x |
| control, no in-flow dwells | 4 | 90 | 2.7x |

Animations run at a clean 60 fps, with a single frame dropped in roughly 2–5% of intervals
and worst-case gaps of 2.2–2.7x nominal — over §1.15's limit of 2, consistently, across
every take. The control take rules out the flows' own `dwell.js` busy loop as the cause:
removing every dwell made it marginally *worse*.

**Owner decision, 2026-07-29: stay on the simulator and accept this floor.** The thresholds
in `scripts/analyse_clip.py` are relaxed accordingly — 3x worst gap, 50% one-sided jitter —
rather than the 2x and 15% §1.15 specifies.

The concern that decision overrides, recorded rather than lost: the money shot plays at
0.5x, and slow motion gives the eye time to register a stutter instead of concealing it, so
it is the least forgiving place in the film to accept dropped frames. Fast-ramped
navigation at 3x is the opposite case and is unaffected.

Relaxing a per-gap threshold costs sensitivity, so the real gate moved to the **rate** of
dropped frames: above 10% of intervals a clip still fails, because that is a regression
(thermal throttling, a background build, a heavier animation) rather than the simulator's
normal floor. The DROPPED column always counts frames physically missing — a gap of 2x
nominal or more — independently of the pass threshold, so moving the policy never silently
changes what the number means.

## Phase B — assembly

```bash
make studio            # live iteration in Remotion Studio
make videos            # render every brief in briefs/
make video-F1          # render one
```

Output lands in `out/videos/<variant_tag>.mp4` and the tag is written into the container
afterwards by `scripts/tag_video.sh`. That last step is not decoration: Remotion prepends
`Made with Remotion <version>; ` to any comment it writes, so passing the tag to the
renderer would produce a value that no later search of the archive matches.

A brief is validated before a single frame renders — `calculateMetadata` parses it against
the Zod schema and then runs the §4.3 cross-checks, so a second save CTA or an overlay in
the final five seconds costs a second, not a fifteen-minute encode.

**Segment durations are not declared, they are derived.** A brief gives each segment a
speed ramp, and how long that shot occupies is the integral of the rate curve
(`src/brief/timeline.ts`). For a linear ramp the answer is `ln(r1/r0)/m`, not the length
divided by the average rate — at 3x decelerating to 1x the two differ by about 10%, which
is enough to walk every overlay off its beat.

### Choosing `in` and `out`

Do not read them off the motion analysis. The pacing tool reports where the *encoder* wrote
frames, and a simulator transition that stalls halfway registers as stillness — which is
exactly how the first cut ended up opening on a half-finished navigation push with an empty
list in frame. Find the windows where the screen is genuinely settled instead:

```bash
ffmpeg -i out/clips/anatomia/<clip>.mp4 -vf "fps=4,scale=120:-1" /tmp/scan/f_%04d.png
# then compare consecutive frames and keep the runs below a small difference threshold
```

`make verify` also prints a suggested `in` per clip, which strips the recorder's head — the
recording starts rolling before Maestro has finished starting its JVM, and that idle head
is 20 seconds of a static screen.

## Music

```bash
make audio SRC=~/Downloads/track.mp3 NAME=bed_calm_01
```

Normalises the track to the **−20 LUFS** §1.9 wants for a bed, leaving headroom for the UI
samples, and writes `assets/audio/<name>.json` with duration, BPM and the first downbeat.
Those last two are what the beat grid is built from, and §1.9 requires them to exist before
a single segment is timed — an edit assembled first and scored afterwards never locks in.

BPM and offset are **estimates**. `scripts/analyse_audio.py` is dependency-free onset
autocorrelation with a log-normal tempo preference around 120 BPM; the preference is not
cosmetic, because raw autocorrelation is biased toward long lags and without it the script
reports whatever the slowest tempo in its search window happens to be. Octave ambiguity
remains real — a half-time groove may report half its tempo, which does not break the grid
but halves how many boundaries a bar offers. Confirm against the waveform in Studio.

### Choosing between candidates

```bash
make audio SRC=~/Downloads/one.mp3 NAME=cand_one     # once per candidate
make audition BEDS="cand_one cand_two cand_three"
```

Produces `audition_mood.mp3` (clean) and `audition_grid.mp3` (the same segments with a
click on each candidate's computed beat grid). Every candidate is normalised to −20 LUFS
first and trimmed from its own first downbeat, because comparing raw downloads in a player
is not a fair test — the loudest master wins on volume alone, whatever it does for the
film. The grid file answers a separate question: if the clicks drift out of the music, the
BPM estimate is wrong and every cut in the film would inherit that error.

Choosing music needs no render and no footage. §1.9 puts it first for exactly that reason.

Current bed: `bed_calm_01` (Pixabay, *A Leap Into the Future*), 66.9 s, 83.3 BPM,
first downbeat 0.040 s, measured at −20.23 LUFS.

Character, confirmed by listening: **cold rhythmic electronica, no melodic theme, no
vocal.** Chosen over the two alternatives because it breaks none of §1.9's explicit
prohibitions — not trap, not corporate uplift, no risers — and because cold and restrained
is what the Linear/Arc/Raycast reference films in §1 actually sound like. The other two
downloads were rejected: *Corporate Bright* is corporate uplift by ear as well as by name,
and *Trap in South City* is trap (139.5 BPM confirms it).

Two consequences worth carrying into the edit:

- The bed is **rhythmic, not a wash**, so the beat is audible and a cut landing off-grid is
  noticeable. Confirming BPM and offset against the waveform matters more here than it
  would under an ambient pad, not less.
- With **no melodic theme**, overlays are free to land where the story needs them rather
  than in the gaps of a tune.

## Demo state

`DEMO_MODE` is a launch-time hook in the app itself
([`AppEnvironment.swift`](../App/AppEnvironment.swift)):

```
DEMO_MODE=1  DEMO_DECK=<slug>  DEMO_DECK_NAME="<what it says on screen>"
```

`scripts/seed.sh` uninstalls the app, reinstalls it, copies
`assets/decks/<slug>.csv` into the app's `Documents/demo/`, and launches with those
variables. The app parses that CSV with the same parser the shipping import uses and seeds
a deterministic review history, so **two runs produce the same queue, the same order and
the same intervals** — an edit cut against take 2 still matches take 5.

The same CSV is the file the import flow picks up on camera. One artifact, two roles,
nothing to keep in sync.

If the deck is missing or unparseable the app seeds an **empty** library on purpose, so the
flow fails on its first assertion instead of quietly recording the wrong deck.

### Authoring a deck

`assets/decks/<slug>.csv`, columns `type,front,back,tags`. Hand-authored, never generated
(§1.12): real Italian course material, correct and readable at 1080p, card counts that are
not round numbers. Add the display name to `deck_display_name()` in `scripts/common.sh` —
the pipeline refuses a slug it has no real name for, so `anatomia` can never reach the
screen as a deck title.

`anatomia.csv` is 32 notes → **47 cards**, and
`Packages/FlashUpKit/Tests/FlashUpDataTests/DemoModeTests.swift` asserts exactly that, so a
typo that silently drops a row fails the test suite rather than the shoot.

## Not automated

Recorded by hand, per spec §3.5:

- `clip1` — the chatbot generating the cards. Phone screen recording. **Re-recorded per
  chatbot variant.**
- `clip9` — Anki desktop navigation. Mac screen recording.
- `clip8` — physical b-roll.
- Live CloudKit sync — impossible without a paid account, and not faked. See §3.7 for the
  two-simulator alternative and the overlay that must accompany it.

## Layout

```
flows/            Maestro YAML, one per clip; flows/stills/ for PNG captures
assets/decks/     hand-authored demo datasets
assets/fonts/     self-hosted .woff2
assets/audio/     music beds and the 6 UI samples
briefs/           one JSON per finished video
variants/         matrix.json and generated/ (machine-written, never hand-edited)
remotion/         Phase B
docs/             REMOTION_NOTES.md, ASSETS_LICENSING.md
out/              recordings, stills, assembled videos — not committed
```
