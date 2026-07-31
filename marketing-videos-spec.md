# SPEC — Flash Up marketing clip pipeline

Single source of truth. Supersedes all earlier drafts (the original pipeline spec and
the separate art-direction appendix are merged here).

**Reading order is normative.** §1 (art direction) governs §3 and §4. Where an
implementation detail conflicts with §1, §1 wins. If a value you need is not specified,
stop and ask — do not invent visual decisions.

> **Note for publishing and analytics agents — how variants are treated.** Every
> published video is a variant and carries a `variant_tag` (§5.6); a render without a
> valid tag is invalid and must not be published. Variants are experiments, not filler:
> publish **one per slot**, never the full set at once, and only ever change **one axis**
> between two videos you intend to compare — otherwise the result is uninterpretable and
> the data is discarded. Judge nothing before **72 hours and 1,000 views**. Rank on
> 3-second retention first, saves per 1,000 views second, waitlist signups last — but
> **kill on signups**: a variant with strong retention and zero signups across two posts
> is entertainment, not marketing. Winners are promoted to the base brief and their axis
> value is locked; losers are retired and never re-posted unchanged. Full rules in
> §5.6–§5.7.

---

## §0 — Purpose, audience, constraints

**Goal.** A fully scripted macOS pipeline that (A) boots an iOS Simulator, seeds a
curated demo state, drives the real app UI with Maestro flows and records each marketing
clip as a named `.mp4`, reproducibly, with one command; and (B) assembles finished 9:16
vertical videos (1080×1920) from those clips plus a JSON brief per video, rendered in
Remotion.

**Audience.** Italian university students, 20–25, iPhone users, visually literate, high
tolerance for restraint and very low tolerance for anything that looks like a screencast
or a growth-hack ad.

**Hard constraints.**

- **Only real app UI running real flows.** No synthesised or distorted interface.
  Simulator (or physical device) screen recordings satisfy this; generative video does not.
- **No Apple Developer account.** Everything works with free provisioning / plain
  simulator builds. **Do not implement or record any CloudKit sync flow** — it cannot
  work without a paid account and must not be faked. See §3.7 for the honest alternative.
- Never invent app features. Drive only screens that exist. If a flow step can't find an
  element, fail loudly with a screenshot — do not improvise an alternative path.
- Ask before any destructive action outside `marketing-pipeline/`.
- Everything reruns from scratch with `make clips` after an app change.

**Environment.** macOS with Xcode; the Flash Up project builds and runs on the iOS
Simulator. Project path: `<PROJECT_PATH>` (ask if unclear). Install Maestro
(`curl -Ls "https://get.maestro.mobile.dev" | bash`) if absent; verify `maestro --version`.
Target simulator: latest iPhone Pro-class device (e.g. iPhone 16 Pro), portrait.

---

# §1 — ART DIRECTION

The reference points are Apple product films and Linear/Arc/Raycast launch videos: calm,
confident, generous negative space, one idea per shot, motion that decelerates rather
than bounces.

## 1.1 Non-goals (failure states, not stylistic options)

- Black bars above/below the app screen.
- Hard black text outlines or drop shadows on type.
- The system touch indicator (grey circle).
- Constant-speed timelapse of navigation.
- A static PNG end card with a fade.
- Emoji in overlay copy.
- More than one idea on screen at a time.
- Placeholder or unconvincing content inside the app (`Test deck`, `Mazzo 1`, empty lists).
- A feature tour: shots sequenced because the feature exists, not because the story needs them.
- Mechanically uniform motion with zero deviation (§1.16).

**Half of this section is about the frame around the screen. The other half — §1.12 to
§1.16 — is about what happens inside it, and it matters just as much. A perfect canvas
around a screen full of dummy data is still a tutorial.**

## 1.2 Colour tokens (provisional — single source of truth)

No brand identity exists yet. The palette below is a deliberate starting point: warm
accent on deep ink, chosen because the study-app category is saturated with blue and
violet. Define these as exported constants in **one** file and reference them everywhere.
Changing the brand later must be a one-file edit.

```ts
// remotion/src/theme.ts
export const theme = {
  ink900:   '#070910',  // deepest background
  ink800:   '#0A0D14',  // canvas base
  ink600:   '#16203A',  // cool bloom
  ember700: '#3A1F12',  // warm bloom
  ember500: '#FF8A3D',  // primary accent — CTA, ripple, key words
  ember300: '#FFB784',  // accent, secondary
  paper:    '#F7F4EF',  // primary text — NOT pure white, warm off-white
  muted:    '#9AA3B2',  // secondary text
} as const;
```

**The app UI runs in light mode** for all recordings. A bright screen against a dark
canvas makes the device read as a light source. This is the single biggest lever in the
whole look.

## 1.3 Typography

Font: **General Sans** (Fontshare), weights 500 and 600 only. Fallback if licensing is
unclear: **Instrument Sans** (SIL OFL). The research sub-agent (§4.1) confirms the licence
and the correct self-hosting method before use. `.woff2` files live in `assets/fonts/`
and are self-hosted — never loaded from a remote CDN at render time.

Scale, on the 1080×1920 canvas:

| Style        | Size  | Weight | Tracking | Line-height | Colour | Max |
|--------------|-------|--------|----------|-------------|--------|-----|
| `hook`       | 76px  | 600    | -0.025em | 1.08        | paper  | 2 lines / 7 words |
| `punch`      | 96px  | 600    | -0.030em | 1.05        | paper  | 1 line / 4 words |
| `sub`        | 44px  | 500    | -0.010em | 1.25        | muted  | 1 line |
| `save_cta`   | 38px  | 500    | 0        | 1.20        | paper  | 1 line |
| `endcard_h`  | 88px  | 600    | -0.030em | 1.05        | paper  | 2 lines |
| `endcard_c`  | 40px  | 500    | -0.005em | 1.30        | muted  | 2 lines |

- **Sentence case only.** Never ALL CAPS, never Title Case.
- Negative tracking on every size above 60px. This is what separates typeset from typed.
- **No outlines, no drop shadows on text.** Insufficient contrast is solved with a scrim
  (§1.5) or by moving the text — never with a stroke.
- One accent word per overlay maximum may use `ember500`. Usually zero.

## 1.4 Canvas geometry and safe areas

Canvas: **1080 × 1920, 60 fps**, H.264, yuv420p.

```
x: 0 ............................................... 1080
   |  108 |<------ content column: 864px ------>| 972 |

y: 0
   | 0–280       DEAD ZONE (platform UI, no text)
   | 280–1500    text may live here
   | 1500–1920   DEAD ZONE (TikTok/IG caption + buttons)
```

All text is anchored inside `x: 108–972` and `y: 280–1500`. No exceptions.

Device placement (full-bleed, §1.5):

```
deviceHeight = 1560
deviceTop    = 200
deviceWidth  = 1560 * (sourceWidth / sourceHeight)        // 718 for iPhone 16 Pro
deviceLeft   = (1080 - deviceWidth) / 2
cornerRadius = 55 * (deviceWidth / sourceWidthInPoints)   // ≈ 98px for iPhone 16 Pro
```

Compute from the actual recording dimensions at render time (`getVideoMetadata`). Never
hardcode 718. **Never scale non-uniformly** — if the numbers don't work, change the
height, never the aspect ratio.

## 1.5 The device layer — full-bleed, no phone chrome

The recording is composited as a floating rounded rectangle, not as a photo of a phone.
An iPhone records ~19.5:9, taller than 9:16, so there is always canvas around it: what
goes there *is* the film.

1. **Clip** the video to a rounded rect at `cornerRadius`.
2. **Shadow**, two layers, cast down: `0 60px 140px rgba(0,0,0,0.55)` and
   `0 8px 24px rgba(0,0,0,0.35)`.
3. **Hairline**: 1px inset border `rgba(255,255,255,0.10)` — separates screen from
   background without a visible frame.
4. **Background**: `ink800` base, two heavily blurred radial blooms — `ink600` at
   (28%, 22%) and `ember700` at (78%, 82%), each ~900px radius, 180px blur — plus a
   vignette (radial black, 0 → 0.35 at the corners).
5. **Grain**: animated monochrome noise, `opacity 0.04`, `mix-blend-mode: overlay`, full
   canvas, above everything except text. Kills gradient banding; cheapest single upgrade
   in the pipeline. Do not skip it.
6. **Scrim** (only when text sits over the device): linear gradient from
   `rgba(7,9,16,0.75)` to transparent, 520px tall, anchored to the text's edge. Never a
   solid box behind text.

## 1.6 Motion system

Everything moves. A static frame reads as a recording; a moving frame reads as direction.

```ts
// remotion/src/motion.ts
export const EASE_OUT   = Easing.bezier(0.22, 1.00, 0.36, 1.00); // entrances
export const EASE_INOUT = Easing.bezier(0.65, 0.00, 0.35, 1.00); // moves
export const EASE_IN    = Easing.bezier(0.55, 0.00, 1.00, 0.45); // exits
```

Linear is forbidden except for the camera push and the grain.

- **Text in** — 20 frames (333 ms), `EASE_OUT`, simultaneous: `opacity 0→1` (first 10
  frames), `translateY 28px→0`, `scale 0.97→1`, `blur 8px→0`. Stagger multi-line blocks
  by **4 frames per line**.
- **Text out** — 12 frames, `EASE_IN`: `opacity 1→0`, `translateY 0→-12px`, `blur 0→6px`.
- **Camera push** — the device layer scales `1.000 → 1.045` across each segment with
  `EASE_INOUT`. Alternate direction between consecutive segments so the film never feels
  on rails.
- **Cut transition** — hard cut plus a 6-frame `scale 1.02 → 1.00` settle on the incoming
  segment. No dissolves between app footage. No wipes, ever.
- **Spring** (end card only): wordmark `{ damping: 200, stiffness: 100, mass: 0.6 }`
  (no overshoot); CTA line `{ damping: 26, stiffness: 180, mass: 0.7 }`, delayed 12 frames.

## 1.7 Editing and rhythm

- **Never show navigation.** Cut on the moment of change. Footage of a user hunting for
  a button does not appear in the final video.
- **Speed ramps, not constant speed.** A flat `"speed": 2.0` is banned. Every segment
  declares a ramp (e.g. 3.0× across navigation, decelerating to 1.0× over 20 frames
  before the payoff). Implement as frame remapping, not `playbackRate` (§4.1, item 8).
- **The card flip is the money shot.** Recorded in three takes; plays at **0.5×** and
  holds for a full 2 seconds. It is the only moment that slows down, and the thing
  viewers must remember.
- **First frame** — never a splash screen, never an empty list, never a static UI. The
  video opens already in motion on the most visually distinctive screen in the app. This
  frame decides whether anyone watches the second one.
- **Loop** — the last frame before the end card compositionally rhymes with the first, so
  autoplay replay feels intentional.
- **Total length target: 18–28 s.** 60 s is a technical ceiling, not a goal.
- Cut on the musical beat; segment boundaries snap to the grid (§1.9).

## 1.8 Touch feedback

The simulator's grey `ShowSingleTouches` circle is a screencast tell. Turn it **off** and
composite a custom ripple in post:

- circle, fill `ember500` at `opacity 0.55`, no stroke;
- `scale 0 → 1.6`, `opacity 0.55 → 0`, 24 frames, `EASE_OUT`;
- diameter at scale 1: 120px in the source recording's coordinate space.

Tap timestamps come from the Maestro flow log, or are declared per segment in the brief
as `taps: [{ t, x, y }]`.

## 1.9 Sound — chosen first, not added last

Silence halves perceived production value. A soundless export is not a deliverable.

**The track and its BPM are the first fields filled in a brief**, before a single segment
is timed. The beat grid is computed from `bpm` + `offset`, and every segment boundary and
overlay in/out **snaps to that grid**. An edit assembled first and scored afterwards will
never lock in. This ordering is enforced by the schema (§4.3).

- **Music bed** — licensed (Epidemic Sound / Artlist). Minimal piano or ambient
  electronica. No trap, no corporate uplift, no risers. Bed at **−20 LUFS**.
- **UI sound design**, 6 reusable samples in `assets/audio/`: `tap.wav` (−26 LUFS, ~12 ms),
  `whoosh.wav` (−22, filtered, on segment cuts), `flip.wav` (−18, the money shot),
  `success.wav` (−22, on a correct grade), `sting.wav` (−16, end card),
  `sub_drop.wav` (−20, optional, on the first cut).
- Mix target: **−14 LUFS integrated, −1 dBTP true peak**. Music ducks 3 dB under `flip`
  and `sting`.

## 1.10 End card

Animated composition, **not** a PNG with a fade. 2.5–3.0 s:

1. Background continues — blooms and grain still moving. Never freeze the canvas.
2. Wordmark: fades up + `translateY 20px→0`, overdamped spring, frames 0–20.
3. Product still: the best frame from the film, full-bleed treatment, `scale 0.94→1.0`,
   frames 6–30.
4. CTA line — `"Link in bio → lista d'attesa. Ti mando il link App Store al lancio."` —
   springs in at frame 12 with slight overshoot.
5. Hold 60 frames. **Cut**, do not fade to black.

## 1.11 Copy rules

- Italian, sentence case, **no emoji anywhere**.
- Maximum 7 words per overlay. More than that means two overlays, or a cut.
- One overlay on screen at a time. Never two text blocks simultaneously.
- **Save CTA** — keep the mechanic, drop the vocabulary. Use **`"Salvalo per dopo"`**,
  typeset in the `save_cta` style (pill `rgba(255,255,255,0.10)`, radius 999px, padding
  18px/32px, backdrop blur 20px), anchored at `y: 1360`. Exactly one per video, 2.5–3.5 s,
  mid-video after the payoff, **never in the last 5 s**, never simultaneous with the end
  card. Assembly hard-fails otherwise.
- The sync overlay (§3.7) `"Sincronizzazione automatica — inclusa al lancio"` uses the
  `sub` style and must be present for the **entire** duration of any `clip7_*` segment.

## 1.12 Set-dressing: what is actually on the screen

The fastest way to look amateur is not bad compositing — it's unconvincing content inside
the app. Every screen that appears in a shot is *dressed* before recording.

**Demo dataset** (`assets/decks/<subject>.csv`, loaded by `DEMO_MODE=1`) is authored by
hand, never generated:

- Real Italian university material: `Anatomia — splancnologia`,
  `Biochimica — ciclo di Krebs`, `Farmacologia — antibiotici β-lattamici`. Never `Test`,
  `Deck 1`, `Prova`, `Lorem ipsum`, `asdf`.
- Card fronts and backs are genuinely correct and readable at 1080p. A viewer who pauses
  must find real content, not filler.
- Plausible numbers: card counts that aren't round (47, not 50), a streak that isn't
  suspiciously perfect, intervals that look like real spaced repetition (`fra 4 giorni`,
  `fra 3 settimane`), a deck list populated but not overflowing.
- **No empty states in any shot.** An empty list on camera is a bug report, not a demo.

**Simulator hygiene**, verified before *every* take:

```bash
xcrun simctl status_bar booted override --time "9:41" \
  --batteryLevel 100 --batteryState charged --cellularBars 4 --wifiBars 3
```

9:41, full battery, full signal — the keynote convention, two seconds of work. Also: Do
Not Disturb on, no notification banners, no update badges, no autocorrect suggestion bar
unless typing is the subject. `make verify` fails any clip whose first frame is not 9:41.

## 1.13 Story before system

A brief may not be written until its **promise** exists: one sentence, seven words
maximum, stating the single thing the video claims. `"Da ChatGPT a flashcard pronte"` is
a valid promise. `"Presentazione dell'app"` is not.

Then a **one-line storyboard per shot**, in prose, before any JSON:

```
1. Il problema: appunti caotici, nessun modo di ripassarli.
2. Il gesto: incolla, importa, il mazzo esiste.
3. Il payoff: la carta si gira, l'intervallo appare.
4. La promessa, scritta.
```

Tension → transformation → resolution, not a list of features. **Every shot serves the
promise or is cut.** Failing here costs minutes; failing after fifteen renders costs days.
`promise` and `storyboard` are required fields and validation rejects a brief without them.

## 1.14 Hero breakout (element lift & return)

A single UI element detaches from the screen plane, scales past any size it could have in
the app, **crosses the boundary of the device rect** and overlaps the canvas, holds, and
returns precisely to its origin. Used to force attention onto the one element the shot is
about.

**Implementation.** This cannot be done on flat video. The hero is a **separate layer**
composited above the recording: either (a) the element rebuilt in React/CSS inside
Remotion and aligned pixel-perfectly to its on-screen counterpart, or (b) a masked crop of
a still. (a) is preferred — infinite resolution, and the element can flip, tilt and
re-typeset. The underlying footage **freezes** on the departure frame for the duration of
the breakout and resumes on the return frame, so the layers never desync.

| Phase  | Duration       | Easing | Transform |
|--------|----------------|--------|-----------|
| Lift   | 24 fr (400 ms) | `EASE_OUT`, overshoot to 1.05× of target | `scale 1 → 1.8`, translate to canvas centre, `rotateX 0 → -10deg` |
| Hold   | 60 fr (1000 ms)| —      | `scale 1.8`, slow drift `1.80 → 1.83` |
| Return | 33 fr (550 ms) | `EASE_INOUT`, no overshoot | back to origin exactly |

Supporting layers, same curve:

- Rest of the device: `opacity 1 → 0.35`, `blur 0 → 6px`, `scale 1 → 0.97`. **This is what
  sells it** — without the recede it reads as a zoom, not as depth.
- Hero shadow grows with the lift: `0 20px 40px rgba(0,0,0,.35)` → `0 80px 160px rgba(0,0,0,.6)`.
- 3D: `perspective: 1600px` on the container. **Tilt is the default**; set `"tilt": false`
  in the brief for a flat scale.

**Rules.** Maximum one hero breakout per video (two only if the film exceeds 24 s and they
are at least 8 s apart). **It must return** — a breakout that cuts away mid-hold reads as
an edit and wastes the effect. Never on a decorative element; only on the element the
promise depends on. Primary candidate for this product: **the flashcard during the flip** —
it lifts, turns in mid-air showing the back, and settles.

## 1.15 Frame pacing

Simulator recordings frequently drop frames. At 60 fps inside an otherwise flawless canvas
the stutter is very visible and no compositing hides it — an app that judders inside a
perfect frame produces exactly the amateur read this document exists to avoid.

`make verify` checks **frame pacing**: extract per-frame presentation timestamps
(`ffprobe -show_entries frame=pkt_pts_time`), compute deltas, and **fail any clip whose
delta standard deviation exceeds 15% of the nominal frame interval, or that contains a gap
larger than 2 frame intervals.**

If the simulator can't produce clean pacing for a flow, fall back to recording on a
**physical iPhone via QuickTime** (Movie Recording, device as camera source). Real-device
capture is the better source anyway; the simulator is a convenience, not a requirement.
Document which clips came from which source.

## 1.16 Calibrated imperfection and iteration

§1.6 is a floor, not a cage. A film where every entrance is exactly 20 frames and every
push exactly 1.045 *feels* mechanical even when nothing looks wrong. Roughly **5% of
moments should deviate deliberately**: a hold three frames longer before the money shot,
an overlay entering a beat early, an asymmetric push. The brief supports a per-segment and
per-overlay `overrides` object that bypasses system values, and the final pass is done by
hand in Remotion Studio, where the system is knowingly violated where the film asks for it.

**Iteration is the process, not evidence of failure.** Budget **10–15 renders** per video,
each watched on a real iPhone, at arm's length, in a normal room — never on a desktop
monitor. At least one round goes to people who don't know the product (§6).

---

# §2 — Repository layout

```
marketing-pipeline/
  Makefile
  README.md
  flows/                    # Maestro YAML, one per clip
  scripts/                  # prepare_sim.sh, record_clip.sh, seed.sh, verify.sh
  assets/
    decks/<subject>.csv      # hand-authored demo datasets (§1.12)
    fonts/                   # self-hosted .woff2
    audio/                   # music beds + 6 UI samples (§1.9)
  briefs/                   # one JSON per finished video
  variants/
    matrix.json              # variant axes and constraints (§5)
    generated/               # expanded briefs — machine-written, never hand-edited
  remotion/
    src/
      Root.tsx               # composition registry
      theme.ts               # §1.2 tokens — single source of truth
      motion.ts              # §1.6 easings, durations, springs
      components/
        Canvas.tsx           # blooms + vignette + grain
        Device.tsx           # clip, radius, shadow, hairline, push
        Overlay.tsx          # text styles, in/out animation, scrim
        Ripple.tsx           # §1.8
        HeroBreakout.tsx     # §1.14
        EndCard.tsx          # §1.10
      Video.tsx              # brief JSON -> timeline
    public/                  # symlink to ../out/clips
  docs/REMOTION_NOTES.md     # written by the research sub-agent (§4.1)
  out/
    clips/<subject>/         # raw clips, per demo dataset
    clips/stills/            # PNG stills
    clips/stills/hero/       # clean hero-element plates (§1.14)
    videos/                  # assembled videos
```

Commit the pipeline to git with a README documenting every target.

---

# §3 — PHASE A: clip recording

## 3.1 Simulator preparation (`scripts/prepare_sim.sh`)

1. Boot the chosen simulator (`xcrun simctl boot`), wait until booted.
2. Clean status bar (§1.12), re-applied and verified per clip, not per session.
3. **Touch indicators OFF**: `defaults write com.apple.iphonesimulator ShowSingleTouches 0`
   (restart the Simulator app after setting). Ripples are composited in post (§1.8).
4. Appearance: **light mode** for every clip (§1.2).
5. Do Not Disturb on; no banners, badges, or update prompts in any frame.
6. Build and install (`xcodebuild -scheme <SCHEME> -destination …`, then `xcrun simctl install`).

## 3.2 Deterministic demo state

- Launch with `xcrun simctl launch <udid> <BUNDLE_ID> --setenv DEMO_MODE=1 --setenv DEMO_DECK=<subject>`.
  Inspect the codebase and add a seeding hook if none exists: when `DEMO_MODE` is set,
  load the bundled deck named by `DEMO_DECK` from `assets/decks/<subject>.csv` and reset
  all review history. `DEMO_DECK` is what makes the subject axis in §5 nearly free.
- The same CSV is the import artifact in the import flows: push it into the app's
  Documents container via `xcrun simctl get_app_container` + `cp`, or drive the Files
  picker in the flow — choose whichever is reliable and document the choice.
- Every flow starts from a known state: wipe app data (uninstall + install) at the start
  of each clip run so recordings are reproducible frame-for-frame.
- The dataset is hand-authored per §1.12 and reviewed before any recording session. No
  flow may traverse an empty state.

## 3.3 Recording wrapper (`scripts/record_clip.sh <clip_id> <flow_file>`)

1. Reset app state (§3.2).
2. Start `xcrun simctl io <udid> recordVideo --codec h264 out/clips/<subject>/<clip_id>.mp4` in background.
3. Run `maestro test flows/<flow_file>`.
4. Stop recording (SIGINT), verify the file exists and exceeds the flow's minimum duration.
5. Print duration, resolution, fps (ffprobe).

Every clip is recorded with **1.5 s of idle head and tail** for editing handles.

## 3.4 Clips to produce (one Maestro flow each)

Insert explicit waits so pacing looks human (300–700 ms between taps). Each flow holds the
final screen ~2 s. Note that human pacing is correct for *capture*; the edit then ramps it
(§1.7).

| ID | Flow | Target | Acceptance |
|---|---|---|---|
| `clip3_import` | Open app → import → pick `<subject>.csv` → preview → confirm → deck visible | 20–35 s | CSV preview and confirmation visible; deck card-count visible at end |
| `clip4_firstcard` | Open seeded deck → card front → tap to flip → back shown | 8–12 s | Flip fully captured. **Record 3 takes** (`_take1/2/3`) — money shot |
| `clip5_review` | Review session → 6 cards, mixed grades → interval indicator visible ≥2× | 25–40 s | Interval/scheduling UI clearly readable |
| `clip6_deck` | Deck list → open deck → card counter and stats | 6–10 s | Counter readable |
| `clip5b_review_long` | As clip5 but 12 cards, calm pacing | 60–90 s | For the "study with me" video (O3) |
| `clip3b_import_fast` | As clip3 with minimal waits | 12–18 s | For timer/split-screen videos (F1, P3) |
| `clip7_syncpreview` | See §3.7 — dual-simulator | 10–15 s ×2 | Both devices on the same card |

Also export, per clip, 3 clean PNG stills (`xcrun simctl io screenshot`) at key moments
(import preview, card front, interval indicator) into `out/clips/stills/` — needed for the
landing page and thumbnails. Native resolution, unscaled, uncompressed. Any element
intended for a hero breakout is additionally captured as a **clean, centred, unobstructed
still** into `out/clips/stills/hero/`.

## 3.5 Out of scope for automation (recorded manually)

- ChatGPT/Gemini/Claude generating the cards (`clip1`) — phone screen recording. **Note:**
  this clip is the one that must be re-recorded per chatbot variant (§5).
- Anki desktop navigation (`clip9`) — Mac screen recording.
- Physical b-roll (`clip8`).
- Live CloudKit sync footage — impossible without a paid account; see §3.7.

## 3.6 Makefile targets (Phase A)

- `make setup` — install Maestro if missing, prepare simulator, build app.
- `make clips [DECK=<subject>]` — run all flows, produce all clips + stills.
- `make clip-<id> [DECK=<subject>]` — single clip.
- `make verify` — ffprobe every clip; print a table (name, duration, resolution, fps);
  check the 9:41 status bar on frame 0; check frame pacing (§1.15). Fail on any missing
  file, short clip, mismatched aspect ratio, or stutter.

## 3.7 Sync preview (`clip7_syncpreview`) — honest mockup rules

Real CloudKit sync cannot run without a paid account. The feature is planned for launch, so
it is shown — under these rules:

1. Boot **two** simulators simultaneously: one iPhone (portrait) and one iPad. Install on
   both; seed both with the identical demo deck (`DEMO_MODE=1`).
2. Record each separately (`simctl io <udid> recordVideo`), with a Maestro flow on each
   that opens the same deck and lands on the same card. 10–15 s each.
3. Deliverable: two raw clips, `clip7_iphone.mp4` and `clip7_ipad.mp4`. Phase B composes
   them side by side on the 1080×1920 canvas.
4. **Overlay** `"Sincronizzazione automatica — inclusa al lancio"`, and **keep a copy of
   each clip without the overlay**. Phase B hard-fails assembly of any brief using
   `clip7_*` without this overlay present for the full segment duration.
5. **Forbidden:** any choreography simulating live propagation between devices (editing or
   answering on one device and cutting to the other "updating"). The two devices show the
   same static deck state; the overlay carries the promise. Do not implement fake sync
   animations, toasts, or spinners in the app for this purpose.

---

# §4 — PHASE B: assembly in Remotion

ffmpeg + ASS subtitles cannot produce the motion in §1.6 — no springs, no per-line stagger,
no blur, no easing curves. Phase B is implemented in **Remotion** (React): programmable,
versionable and reviewable exactly as intended, with live preview. ffmpeg remains only for
final encode flags Remotion's renderer doesn't cover.

The 3-hour timebox and the CapCut fallback from the original draft are **void**: with
Remotion, iteration is cheap and a fallback would only license settling.

## 4.1 MANDATORY: Remotion research sub-agent

**Before writing a single line of Remotion code**, dispatch a dedicated research sub-agent.
It consults the current official documentation (training data on Remotion is likely
outdated) and produces `docs/REMOTION_NOTES.md` answering the following, each with a
working snippet:

1. **Licensing.** Remotion is not unconditionally free. Determine current terms, which
   entities need a paid company licence, and whether this project qualifies. Report at the
   top of the notes. **This is a blocking question.**
2. Installation and scaffolding; required Node version; invoking `remotion studio` and
   `remotion render` from a Makefile.
3. `<OffthreadVideo>` vs `<Video>` — which for local `.mp4` and why.
4. `staticFile()` and correct asset location.
5. `calculateMetadata()` + `getVideoMetadata()` (`@remotion/media-utils`) to derive
   composition duration and source dimensions dynamically from clip files.
6. Input props: `defaultProps`, Zod schema typing, passing a brief JSON via `--props`.
7. `spring()`, `interpolate()`, `Easing`, `useCurrentFrame`, `useVideoConfig`.
8. **Speed ramping**: applying a *variable* rate to a video source. Confirm whether
   `playbackRate` supports non-constant values; if not, document the frame-remapping
   pattern (composition frames → source frames via the integral of the rate curve) with code.
9. `<Sequence>`, `<Series>`, `@remotion/transitions` for segment assembly.
10. Audio: `<Audio>`, volume as a function of frame, ducking, durations via `@remotion/media-utils`.
11. Self-hosted `.woff2` fonts and guaranteeing load before the first rendered frame
    (`delayRender`/`continueRender` or `@remotion/fonts`).
12. Render flags: H.264, yuv420p, CRF, audio codec, `--concurrency`.
13. Known pitfalls with blur filters, `mix-blend-mode`, `perspective`/3D transforms and
    large `box-shadow` values during rendering — all four are load-bearing here (§1.5, §1.14).

The sub-agent writes the notes and stops. Implementation begins only once they exist and
item 1 has a definite answer.

## 4.2 Rendering requirements

- Scale to 1080×1920 per §1.4; centre; never crop app UI; never distort.
- Speed via frame remapping (§4.1, item 8), following the `ramp` curve.
- Text via React components using `theme.ts` and `motion.ts`. No ASS, no drawtext.
- End card animated per §1.10.
- Output: H.264, yuv420p, AAC, ≤ 28 s target (60 s hard ceiling), 1080×1920, playable on
  iPhone (verify with ffprobe and by opening one manually).

## 4.3 Brief schema

Fields appear in authoring order — promise, then music, then storyboard, then timeline. The
schema is deliberately ordered so a brief cannot be written out of sequence (§1.9, §1.13).

```json
{
  "video_id": "F1",
  "variant_tag": "fu-F1-cgpt-anat-h01",
  "promise": "Da ChatGPT a flashcard pronte",
  "music": { "src": "assets/audio/bed_calm_01.mp3", "bpm": 92, "offset": 0.12, "snap": true },
  "storyboard": [
    "Il problema: appunti caotici, nessun modo di ripassarli.",
    "Il gesto: incolla, importa, il mazzo esiste.",
    "Il payoff: la carta si gira, l'intervallo appare.",
    "La promessa, scritta."
  ],
  "segments": [
    {
      "src": "clip3b_import_fast",
      "in": 1.5, "out": 9.0,
      "ramp": [ { "at": 0.0, "rate": 3.0 }, { "at": 5.5, "rate": 3.0 }, { "at": 6.5, "rate": 1.0 } ],
      "push": "in",
      "taps": [ { "t": 0.4, "x": 620, "y": 1480 } ]
    },
    {
      "src": "clip4_firstcard_take2",
      "in": 0.8, "out": 6.2,
      "ramp": [ { "at": 0.0, "rate": 1.0 }, { "at": 2.0, "rate": 0.5 } ],
      "push": "out",
      "hero": { "at": 2.4, "element": "card", "scale": 1.8, "tilt": true, "hold": 1.0, "freezeUnder": true },
      "overrides": { "holdExtraFrames": 3 }
    }
  ],
  "overlays": [
    { "text": "Da ChatGPT a flashcard pronte.", "style": "hook",     "anchor": "top",    "start": 0.3,  "end": 3.0 },
    { "text": "Salvalo per dopo",              "style": "save_cta", "anchor": "bottom", "start": 11.0, "end": 14.0 },
    { "text": "Trenta secondi. Davvero.",      "style": "punch",    "anchor": "center", "startRelEnd": -4.0, "endRelEnd": -2.0 }
  ],
  "endcard": { "still": "out/clips/stills/clip4_front.png", "duration": 2.8 }
}
```

**Validation** (Zod). Assembly hard-fails on: missing `promise` or `storyboard`; zero or
multiple `save_cta` overlays; a `save_cta` overlapping the end card or in the final 5 s;
two overlays overlapping in time; more than one `hero` per video (two only under §1.14's
conditions); a `hero` without `freezeUnder`; any `clip7_*` segment without its sync overlay
covering the full segment; any overlay whose rendered bounds fall outside `x: 108–972` /
`y: 280–1500`; total duration over 60 s; a missing `variant_tag`, one that fails the
regex in §5.6, or one already present on a previously rendered output.

## 4.4 Makefile targets (Phase B)

- `make studio` — open Remotion Studio for live iteration.
- `make videos` — render every brief in `briefs/`.
- `make video-<id>` — render one.

---

# §5 — VARIANT SYSTEM

## 5.1 Principle: vary the content, never the form

Variants multiply the chances of intercepting the right person. But **palette, typography,
motion system, device treatment, ripple, sound signature and end card are identical in
every video, forever.** That is where recognition accumulates: by the third video a
scroller should recognise the brand before reading a word. Vary the form and you don't have
40 videos, you have 40 debuts.

**Variants are a testing instrument, not a content calendar.** Five chatbots × five
subjects × four hooks is 100 videos nobody watches and from which nothing is learned. Vary
**two axes at a time**, measure, kill the losers.

## 5.2 Axes

| Axis | Cost to produce | What it targets | Notes |
|---|---|---|---|
| **Subject / faculty** (`DEMO_DECK`) | Low — `make clips DECK=<subject>` regenerates everything | Faculty targeting. The strongest axis | Only axis that changes pixels *inside* the screen. Requires a hand-authored CSV per subject (§1.12) |
| **Chatbot referenced** | Low if overlay-only; **high if `clip1` is shown** (manual re-record, §3.5) | Identity and search intent | Copy must be nominative only — see §5.5 |
| **Hook copy** (first overlay) | Trivial — one string | Retention at second 1. The real performance lever | Cheapest and most informative axis. Always include it |
| **Opening shot** (first frame) | Medium — reorder segments | Retention at second 0 | Highest-variance axis; test rarely, learn a lot |
| **Music track** | Medium — new BPM changes the beat grid, so all cuts re-time | Mood, audience age read | Never swap a track without re-snapping (§1.9) |
| **Length** (18 s vs 26 s) | Medium — requires a real cut | Platform behaviour | Not achieved by speeding up; achieved by removing a shot |
| **Save CTA wording** | Trivial | Save rate | Keep within §1.11 |
| **End-card headline** | Trivial | Waitlist conversion | The CTA line itself stays fixed |

**Frozen — never varied:** everything in §1.2, §1.3, §1.5, §1.6, §1.8, §1.10, and the
money shot.

## 5.3 Axes are not independent

Swapping the subject forces the hook to follow (`"Da ChatGPT ad anatomia in 30 secondi"`).
Swapping the track re-times every cut. The matrix therefore supports **linked fields** and
**constraints**; generating a variant that violates one is a hard failure, not a warning.

```json
// variants/matrix.json
{
  "base_brief": "briefs/F1.json",
  "axes": {
    "bot":     [ { "id": "cgpt", "label": "ChatGPT", "clip1": "clip1_chatgpt.mp4" },
                 { "id": "gem",  "label": "Gemini",  "clip1": "clip1_gemini.mp4" },
                 { "id": "cla",  "label": "Claude",  "clip1": "clip1_claude.mp4" } ],
    "deck":    [ { "id": "anat", "label": "anatomia",   "csv": "assets/decks/anatomia.csv" },
                 { "id": "bioc", "label": "biochimica", "csv": "assets/decks/biochimica.csv" } ],
    "hook":    [ { "id": "h01", "text": "Da {bot} a {deck} in 30 secondi." },
                 { "id": "h02", "text": "I tuoi appunti, pronti da ripassare." } ]
  },
  "linked": [ "hook.text uses {bot} and {deck}", "deck implies clips/<deck>/" ],
  "constraints": {
    "max_variants": 12,
    "require_recorded_clip1_per_bot": true,
    "forbid": [ { "bot": "cla", "deck": "bioc" } ]
  }
}
```

## 5.4 Generation and discipline

- `make matrix-dryrun` — expands the matrix, prints the resulting variant IDs and the
  total count, renders nothing. **Fails if the count exceeds `max_variants`.** This guard
  is the whole point: it forces a choice instead of a combinatorial dump.
- `make variants` — writes expanded briefs into `variants/generated/` and renders them.
  Generated briefs are machine-written and never hand-edited; edits go to the base brief
  or the matrix.
- **ID scheme:** every generated variant receives a `variant_tag` per §5.6. A video whose
  performance can't be attributed to a tag taught you nothing.
- **Publishing:** never post the full set at once — simultaneous near-identical uploads read
  as a spam farm and suppress reach. One variant per posting slot, alternate axes across
  slots, and hold at least one variant back as a control.
- Every variant still passes the full §6 checklist individually. A variant is a video, not
  a derivative.

## 5.5 Naming other products

References to ChatGPT, Gemini or Claude are **nominative**: name the product in text, don't
imply endorsement, partnership, or affiliation, and don't use their logos or wordmarks in
the end card or as design elements. Showing their real UI in `clip1` is footage of the
user's own screen and is normal comparative practice, but keep it brief and factual. If a
variant's copy starts sounding like a co-marketing announcement, rewrite it.

## 5.6 The variant tag (mandatory)

Every variant carries a tag. It is the join key between a rendered file, a published post,
and a waitlist signup. Without it the whole variant system is theatre.

```
fu-<story>-<bot>-<deck>-<hook>[-r<n>]        e.g.  fu-F1-cgpt-anat-h01
regex: ^fu-[A-Z]\d{1,2}-[a-z]{3,4}-[a-z]{4}-h\d{2}(-r\d+)?$
```

The tag must appear in **five** places, and the pipeline enforces the first three:

1. `variant_tag` in the brief (§4.3). **Render fails without it**, or if it fails the regex.
2. The output filename: `out/videos/fu-F1-cgpt-anat-h01.mp4`.
3. The mp4 container metadata: `-metadata comment="fu-F1-cgpt-anat-h01"`. Platforms strip
   this on upload — it is for the internal archive, so a file found later is identifiable.
4. **The bio link.** A per-variant short link resolving to the waitlist with the tag as a
   parameter (`?v=fu-F1-cgpt-anat-h01`). This is the **only** mechanism that connects a
   signup back to a specific video. A variant published against a generic link cannot be
   measured and should not be published.
5. The tracking sheet row, together with platform, publish timestamp, and slot.

**Hard rules.** The tag is never visible on screen and never appears in the public caption
— it is internal. Two different renders never share a tag: any change to footage, copy,
music, or timing produces a new tag (bump the hook ID, or append `-r2` for a pure
re-render). Re-using a tag corrupts the dataset retroactively, which is worse than having
no dataset.

## 5.7 Monitoring, promotion and kill rules

**Baseline.** For roughly the first 10 posts there is no baseline: record everything, kill
nothing except on the absolute floors below. After that, all relative thresholds are
computed against the **account's running median** for the same platform — not against
numbers from this document, and not against other people's benchmarks.

**Comparison hygiene.** A comparison is valid only if: exactly one axis differs; both
variants were published in comparable slots (same weekday band and time window); both used
the same caption template; and both are on the same platform. If any of these is violated,
discard the *data* — not the video.

**Window.** Primary judgement at **72 hours and ≥1,000 views**, whichever comes later. A
secondary check at **14 days** catches late distribution: a video that revives after a week
is not a loser, and must be logged as such rather than quietly forgotten.

**Metric ladder**, in judging order:

| # | Metric | What it actually tests | Absolute floor |
|---|---|---|---|
| 1 | 3-second retention | First frame + hook (§1.7) | 50% |
| 2 | Average watch % / completion | The edit, the pacing, the length | — |
| 3 | Saves per 1,000 views | Perceived value; the `save_cta` (§1.11) | 5 |
| 4 | Profile visits → link clicks → **waitlist signups per 1,000 views** | The only commercially meaningful number | — |

**Read the retention curve, not just the number.** Where viewers leave is diagnostic and
should be written into the tracking sheet as a one-line note: a drop before 2 s indicts the
first frame; a drop mid-video means the payoff arrives too late; a drop just before the end
card means the film is too long, not that the CTA is wrong.

**Decisions.**

- **Kill** — below an absolute floor; or bottom quartile against the median across the
  ladder after the full window; or **zero waitlist signups across two posts** that each
  cleared the view baseline. Retire the tag; never re-post the file unchanged.
- **Hold** — within ±20% of the median. Inconclusive: it needs another slot before it means
  anything. Do not draw a conclusion from one post.
- **Promote** — the top variant on signups per 1,000 views, provided it is not below the
  retention floor, becomes the new `base_brief`. Its winning axis value is **locked** and
  removed from the matrix for the next generation, freeing the budget for a new axis.
- **Kill the axis, not just the video.** If every value of an axis performs within noise of
  every other, that axis is not a lever for this product: stop varying it and move the
  effort to hook copy or opening shot, which historically carry the most variance.

**Qualitative signal counts.** Comments asking what the app is called, or people tagging
friends, outrank saves as an early indicator and should be logged verbatim. Ten such
comments on a 4,000-view post is a stronger result than 40,000 views in silence.

Every variant still passes §6 individually before publication. The measurement system
decides what to keep; it never decides what is good enough to ship.

---

# §6 — Acceptance checklist

A video ships only if **all** pass.

- [ ] Watched on an actual iPhone, at arm's length, **with sound off** — still legible.
- [ ] Watched with sound on — cuts land on the beat.
- [ ] Frame 0 is in motion, and is not a splash screen, empty state, or static list.
- [ ] Someone unfamiliar with the app understands what it does within 3 seconds.
- [ ] Zero black bars, zero text outlines, zero system touch circles, zero emoji.
- [ ] App UI never stretched, squashed, or cropped.
- [ ] Exactly one `save_cta`, never on screen with the end-card CTA.
- [ ] Any `clip7_*` footage carries its sync overlay for the full segment.
- [ ] Last frame rhymes with the first (loop test: play twice, watch the seam).
- [ ] −14 LUFS integrated, −1 dBTP, 1080×1920, H.264, yuv420p, ≤ 28 s.
- [ ] Every shot serves the stated promise. Any shot that doesn't has been cut.
- [ ] Paused on any frame: no placeholder text, no empty state, no round-number fakery.
- [ ] Status bar reads 9:41, full battery, full signal, wherever visible.
- [ ] Frame pacing check passed (§1.15) — no visible judder.
- [ ] At most one hero breakout, and it returns cleanly to origin.
- [ ] At least one deliberate deviation from the motion system exists and is intentional.
- [ ] **Peer test — the one that counts:** shown to 5 people aged 20–25 who don't know the
      product. At least 4 understood what it does within 3 seconds, **and at least 2 asked
      for the link unprompted.** If the second number is 0, it's a good-looking video that
      sells nothing — go back to §1.13.