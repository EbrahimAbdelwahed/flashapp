# Remotion research notes

Researched 2026-07-29 against live docs. Stable release at time of writing: **`remotion@4.0.500`** (npm `dist-tags.latest`). Remotion 5.0 is **not released** — the migration page exists but says so explicitly ([5-0-migration](https://www.remotion.dev/docs/5-0-migration)). Pin 4.0.500.

Some claims below are verified by reading the published package source rather than the docs; those are marked **[source-verified]** and are more reliable than the prose docs.

---

## 1. LICENSING — BLOCKING

> **VERDICT: A solo indie developer building marketing videos for their own unreleased iOS app qualifies for the FREE licence. No payment required. Two conditions must hold: (a) the entity operating Remotion is an individual or a for-profit organisation with ≤3 employees, and (b) nobody else's headcount gets aggregated onto yours (no agency, no freelancer, no consulting studio touching the Remotion codebase). If the owner later hires so the company reaches 4 people, or hands the Remotion repo to a contractor/agency, a paid Company Licence becomes mandatory retroactively for continued use.**

Verbatim from [`LICENSE.md`](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md) (Copyright © 2026 Remotion), the free-licence eligibility list:

- "an individual"
- "a for-profit organization with up to 3 employees"
- "a non-profit or not-for-profit organization"
- evaluating Remotion and "not yet using it in a commercial way"

Those eligible "can use the software non-commercially **or commercially** for the purpose of creating videos and images". So commercial marketing output is explicitly in scope for the free tier — commerciality is **not** the trigger; headcount is.

| Question | Answer | Source |
|---|---|---|
| Is Remotion unconditionally free? | No. Free licence is conditional on entity type/size. | [license](https://www.remotion.dev/docs/license) |
| Threshold for a paid Company Licence | **4 or more** personnel in a for-profit org | [license FAQ](https://www.remotion.dev/docs/license-pricing-compliance/faq) |
| Solo dev, own product, commercial output | **Free licence applies** | LICENSE.md + FAQ |
| Unreleased app | Irrelevant to the licence. Release status changes nothing; even if it were "evaluation", that is also free. | LICENSE.md |
| Aggregation — client work | If the client owns/operates the Remotion codebase, **both** headcounts sum toward 4 | FAQ |
| Aggregation — subcontractors | Bringing in "another studio, freelancers, or a consulting agency" to operate Remotion — "their headcount aggregates with yours" | FAQ |
| Agency delivering finished videos only | Only the agency's headcount counts (client never touches the code) | FAQ |
| Paid plans if you cross the line | Creators $25/seat/mo; Automators $0.01/render, $100/mo min; Enterprise from $500/mo | [remotion.pro/license](https://www.remotion.pro/license) |

**Residual ambiguity — owner must decide, do not treat as settled:**
1. "Employees" vs. contractors/co-founders is not defined numerically in LICENSE.md. If the owner ever has even one part-time collaborator running renders, count conservatively.
2. The rendered output carries a Remotion watermark in metadata by default (`comment = Made with Remotion <version>`, see §12). Not a licence obligation, but it is a disclosure.
3. If the marketing pipeline is ever run **for** someone else (an agency engagement, a client's app), the free licence likely ends. Re-read the FAQ at that point.

---

## 2. Installation, scaffolding, Node, Makefile

**System requirements** ([docs/](https://www.remotion.dev/docs/)): "you need at least **Node 16 or Bun 1.0.3**. 🍎 macOS 15 (Sequoia) or later is required." Host has Node v22.19.0 and Darwin 25.5 → fine. `remotion@4.0.500`'s `package.json` has **no `engines` field** at all **[source-verified]**, so npm will not police the version.

Scaffold:

```bash
npx create-video@latest --yes --blank marketing-pipeline/remotion
cd marketing-pipeline/remotion && npm i
```

Makefile (tabs, not spaces):

```makefile
REMOTION_DIR := marketing-pipeline/remotion
COMP         ?= HeroVertical
BRIEF        ?= briefs/hero.json
OUT          ?= out/$(COMP).mp4

.PHONY: studio render

studio:
	cd $(REMOTION_DIR) && npx remotion studio --port=3010 --no-open

render:
	cd $(REMOTION_DIR) && npx remotion render $(COMP) $(OUT) \
	  --props=$(BRIEF) \
	  --codec=h264 \
	  --pixel-format=yuv420p \
	  --crf=18 \
	  --audio-codec=aac \
	  --concurrency=50% \
	  --log=info
```

`remotion studio` flags ([cli/studio](https://www.remotion.dev/docs/cli/studio)): `--port`, `--no-open`, `--public-dir`, `--browser`, `--browser-args`, `--props`, `--log`. Entry point argument is optional.

---

## 3. `<OffthreadVideo>` vs `<Video>` vs `@remotion/media`

There are now **three** video components. The `Video` exported from `remotion` is an alias of `Html5Video` **[source-verified: `remotion/dist/cjs/index.d.ts` exports `Html5Video, OffthreadVideo, Video` from `./video/index.js`]** — that is the old, worst one.

| Component | Import | Engine | Frame-perfect | Verdict for local .mp4 |
|---|---|---|---|---|
| `<Video>` / `<Audio>` | `@remotion/media` | Mediabunny + WebCodecs | yes | **Use this** |
| `<OffthreadVideo>` | `remotion` | Rust + FFmpeg | yes | Fallback for exotic codecs |
| `<Html5Video>` (a.k.a. `Video` from `remotion`) | `remotion` | HTML5 `<video>` | "Not guaranteed" | Do not use |

Docs say plainly: "For new code, use `<Video />` from `@remotion/media`." ([video-vs-offthreadvideo](https://www.remotion.dev/docs/video-vs-offthreadvideo)). It is the fastest, supports `loop`, and does partial asset downloads. `<OffthreadVideo>` is still fine and has broader codec support but **no `loop`** and is not supported in client-side rendering.

```tsx
import {AbsoluteFill, staticFile} from 'remotion';
import {Video} from '@remotion/media';

export const Clip: React.FC = () => (
  <AbsoluteFill>
    <Video src={staticFile('clips/study-loop.mp4')} objectFit="cover" />
  </AbsoluteFill>
);
```

`@remotion/media` ships at the same version as `remotion` (`4.0.500`) — install `@remotion/media@4.0.500`. It auto-falls-back to `<OffthreadVideo>` unless you set `disallowFallbackToOffthreadVideo` **[source-verified]**.

---

## 4. `staticFile()` and the `public/` folder

[Docs](https://www.remotion.dev/docs/staticfile).

```tsx
import {staticFile} from 'remotion';
const clip = staticFile('clips/study-loop.mp4'); // -> /clips/study-loop.mp4
```

Rules:

- The `public/` folder must live **"in the same folder as your `package.json` that contains the remotion dependency"**, even if your components live elsewhere. So: `marketing-pipeline/remotion/public/`.
- Never write a bare string path (`src="/clips/x.mp4"`) and never `import` a media file — `staticFile()` exists so the bundle works when served from a subdirectory and so filenames can't collide with composition IDs.
- Since v4.0, `staticFile()` runs `encodeURIComponent` **for you**. Do not pre-encode: `staticFile('my#file.png')` → `/my%23file.png`.
- Related: `getStaticFiles()`, `watchStaticFile()`.
- Override the directory with `--public-dir=./assets` on both `studio` and `render`.

Suggested layout:

```
marketing-pipeline/remotion/public/
  clips/*.mp4
  audio/bed.mp3
  sfx/{tap,whoosh,flip,success,sting,sub_drop}.wav
  fonts/*.woff2
```

---

## 5. `calculateMetadata()` + reading real clip duration/dimensions

`calculateMetadata` ([docs](https://www.remotion.dev/docs/calculate-metadata)) runs **once per render**, independently of concurrency, inside a browser context, and may be `async`. It receives `{props, defaultProps, abortSignal, compositionId, isRendering}` and returns any of `durationInFrames`, `fps`, `width`, `height`, `props`, plus per-composition codec/pixel-format defaults.

**Do not use `getVideoMetadata()` from `@remotion/media-utils`.** It is flagged deprecated in the shipped 4.0.500 typings **[source-verified]**:

```
@deprecated Use Mediabunny instead: https://www.remotion.dev/docs/mediabunny/metadata
```

and the docs add that it "Does not support H.265 videos on Linux and also fails on some other formats". `getMediaMetadata` does **not** exist in `@remotion/media-utils@4.0.500` **[source-verified — the package exports only `getAudioData, getAudioDuration, getAudioDurationInSeconds, getImageDimensions, getVideoMetadata, getWaveformPortion, useAudioData, useWindowedAudioData, visualizeAudio, visualizeAudioWaveform, createSmoothSvgPath, audioBufferToDataUrl`]**. Use Mediabunny directly.

```bash
npm i mediabunny
```

```tsx
// src/media-metadata.ts — from https://www.remotion.dev/docs/mediabunny/metadata
import {Input, ALL_FORMATS, UrlSource} from 'mediabunny';

const commonFpsValues = [24000 / 1001, 24, 25, 30000 / 1001, 30, 50, 60000 / 1001, 60];
const snapToCommonFps = (fps: number) =>
  commonFpsValues.find((c) => Math.abs(fps - c) < 0.01) ?? fps;

export const getMediaMetadata = async (src: string) => {
  const input = new Input({
    formats: ALL_FORMATS,
    source: new UrlSource(src, {getRetryDelay: () => null}),
  });
  const durationInSeconds = await input.computeDuration();
  const videoTrack = await input.getPrimaryVideoTrack();
  const dimensions = videoTrack
    ? {width: await videoTrack.getDisplayWidth(), height: await videoTrack.getDisplayHeight()}
    : null;
  const packetStats = await videoTrack?.computePacketStats(50);
  const fps = packetStats ? snapToCommonFps(packetStats.averagePacketRate) : null;
  return {durationInSeconds, dimensions, fps};
};
```

Wired into a composition:

```tsx
import {Composition, staticFile, CalculateMetadataFunction} from 'remotion';
import {getMediaMetadata} from './media-metadata';

type Props = {clip: string};

const calc: CalculateMetadataFunction<Props> = async ({props}) => {
  const {durationInSeconds, dimensions} = await getMediaMetadata(staticFile(props.clip));
  const fps = 30;
  return {
    fps,
    durationInFrames: Math.floor(durationInSeconds * fps),
    width: dimensions?.width ?? 1080,
    height: dimensions?.height ?? 1920,
  };
};

<Composition
  id="HeroVertical"
  component={Hero}
  fps={30}
  width={1080}
  height={1920}
  durationInFrames={1}
  defaultProps={{clip: 'clips/study-loop.mp4'}}
  calculateMetadata={calc}
/>;
```

**AMBIGUOUS:** the docs never state whether `UrlSource` accepts a `staticFile()` path during a headless render (it is a relative URL against the bundle origin). It should, because `calculateMetadata` runs in the browser, but verify with one render before relying on it. If it fails, run Mediabunny in Node inside the Makefile and pass duration/dimensions in via `--props`.

---

## 6. Input props, `defaultProps`, Zod, `--props`

[passing-props](https://www.remotion.dev/docs/passing-props) · [schemas](https://www.remotion.dev/docs/schemas)

```bash
npx remotion add @remotion/zod-types zod
```

```tsx
import {z} from 'zod';
import {zColor} from '@remotion/zod-types';
import {Composition} from 'remotion';

export const briefSchema = z.object({
  headline: z.string(),
  clip: z.string(),
  accent: zColor(),
  bpm: z.number().int().positive(),
});

export const Hero: React.FC<z.infer<typeof briefSchema>> = ({headline}) => <div>{headline}</div>;

<Composition
  id="HeroVertical"
  component={Hero}
  schema={briefSchema}
  defaultProps={{headline: 'Learn faster', clip: 'clips/a.mp4', accent: '#5B8DEF', bpm: 96}}
  fps={30}
  width={1080}
  height={1920}
  durationInFrames={600}
/>;
```

`defaultProps` must satisfy `schema` or TypeScript errors. Props resolution order: `defaultProps` → input props (override) → `calculateMetadata()` post-processing → component.

Passing the brief JSON:

```bash
npx remotion render HeroVertical out/hero.mp4 --props=./briefs/hero.json   # file path
npx remotion render HeroVertical out/hero.mp4 --props='{"headline":"Hi"}'  # inline
```

Use the **file** form in the Makefile — inline JSON quoting differs per shell and breaks on Windows. `getInputProps()` reads them in `Root.tsx` if you need them outside a composition.

---

## 7. Animation primitives — current signatures

`useCurrentFrame(): number`. `useVideoConfig()` returns `{width, height, fps, durationInFrames, id, defaultProps, props, defaultCodec, defaultSampleRate}` — inside a `<Sequence>`, `width`/`height`/`durationInFrames` are the **sequence's**, not the composition's ([use-video-config](https://www.remotion.dev/docs/use-video-config)).

```tsx
spring({
  frame, fps,
  from?: 0, to?: 1,
  config?: {mass?: 1, damping?: 10, stiffness?: 100, overshootClamping?: false},
  durationInFrames?: number,
  durationRestThreshold?: number,
  delay?: number,
  reverse?: false,
})
```
Order of operations: duration stretch → reverse → delay ([spring](https://www.remotion.dev/docs/spring)).

```tsx
interpolate(input, inputRange, outputRange, {
  easing?: EasingFunction | EasingFunction[],
  extrapolateLeft?: 'extend' | 'clamp' | 'wrap' | 'identity',   // default 'extend'
  extrapolateRight?: 'extend' | 'clamp' | 'wrap' | 'identity',  // default 'extend'
  output?: 'linear' | 'perceptual-scale',
  posterize?: number,
})
```
Ranges must be the same length. Defaults are `extend`, which will happily send opacity to 3.7 — **always pass `clamp` on both ends** unless you mean otherwise. `output: 'perceptual-scale'` is the right choice for scale animations ([interpolate](https://www.remotion.dev/docs/interpolate)).

```tsx
import {Easing, interpolate, useCurrentFrame, useVideoConfig, spring} from 'remotion';

const frame = useCurrentFrame();
const {fps} = useVideoConfig();

const opacity = interpolate(frame, [0, 12], [0, 1], {
  easing: Easing.bezier(0.16, 1, 0.3, 1),
  extrapolateLeft: 'clamp',
  extrapolateRight: 'clamp',
});

const pop = spring({frame, fps, config: {damping: 14, stiffness: 180}, durationInFrames: 24});
```

`Easing` provides `back, bounce, ease, elastic, linear, quad, cubic, poly(n), bezier(x1,y1,x2,y2), circle, sin, exp, step0, step1` plus the `in/out/inOut` modifiers ([easing](https://www.remotion.dev/docs/easing)).

---

## 8. SPEED RAMPING — variable playback rate

### Confirmed: `playbackRate` is a scalar and CANNOT be a function of frame

**[source-verified]** in `@remotion/media@4.0.500` typings, both `<Video>` and `<Audio>` declare `playbackRate?: number`. `volume` is `VolumeProp` (may be `(frame) => number`); `playbackRate` is not. The internal `getTimeInSeconds`, `extractFrameAndAudio` and `MediaPlayer` constructor all take `playbackRate: number`. Same for `<OffthreadVideo>`.

Worse, naively animating it is **silently wrong**, not just static. From [Change the speed of a video over time](https://www.remotion.dev/docs/miscellaneous/snippets/accelerated-video):

> "Remotion will evaluate each frame independently from the other frames. If frame is 100, the `playbackRate` evaluates as 5 and Remotion will render the 500th frame of the video, which is undesired because it does not take into account that the speed has been building up to 5 until now."

So you must remap composition frame → source frame yourself, by integrating the rate curve.

### Official pattern (verbatim from the docs page)

```tsx
import React from 'react';
import {interpolate, Sequence, useCurrentFrame, OffthreadVideo} from 'remotion';

const remapSpeed = (frame: number, speed: (fr: number) => number) => {
  let framesPassed = 0;
  for (let i = 0; i <= frame; i++) {
    framesPassed += speed(i);
  }
  return framesPassed;
};

export const AcceleratedVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const speedFunction = (f: number) => interpolate(f, [0, 500], [1, 5]);
  const remappedFrame = remapSpeed(frame, speedFunction);

  return (
    <Sequence from={frame}>
      <OffthreadVideo
        trimBefore={Math.round(remappedFrame)}
        playbackRate={speedFunction(frame)}
        src="https://remotion.media/BigBuckBunny.mp4#disable"
      />
    </Sequence>
  );
};
```

Why the two odd bits:

- `<Sequence from={frame}>` makes the child's local `useCurrentFrame()` equal `0` on every composition frame, so the video shows exactly `trimBefore + 0` — i.e. the remapped source frame, with no drift.
- `playbackRate={speedFunction(frame)}` is still passed so the **audio** is resampled at the instantaneous rate and so motion blur/decoder hinting matches. It does not drive the seek position.

### Production version (recommended over the doc snippet)

The doc's `remapSpeed` is O(frame) per frame → O(n²) per render, re-evaluated in every one of the parallel render tabs. For a 900-frame comp that is ~400k `interpolate` calls per tab. Precompute a prefix-sum table once at module scope:

```tsx
// src/speed-ramp.ts
export type SpeedFn = (frame: number) => number;

/** Prefix-sum of the rate curve: table[f] = source frames consumed by composition frame f. */
export const buildRamp = (durationInFrames: number, speed: SpeedFn): Float64Array => {
  const table = new Float64Array(durationInFrames + 1);
  let acc = 0;
  for (let i = 0; i <= durationInFrames; i++) {
    acc += speed(i);
    table[i] = acc;
  }
  return table;
};

/** Closed form for a LINEAR ramp r0 -> r1 over [0, n]; matches the loop to <1 frame. */
export const linearRampSourceFrame = (frame: number, n: number, r0: number, r1: number) => {
  const f = Math.min(Math.max(frame, 0), n);
  return r0 * (f + 1) + ((r1 - r0) * f * (f + 1)) / (2 * n);
};
```

```tsx
// src/SpeedRamp.tsx
import React, {useMemo} from 'react';
import {Sequence, useCurrentFrame, useVideoConfig, interpolate, Easing, staticFile} from 'remotion';
import {Video} from '@remotion/media';
import {buildRamp, SpeedFn} from './speed-ramp';

export const SpeedRamp: React.FC<{src: string; speed: SpeedFn}> = ({src, speed}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();

  // Built once per tab, not once per frame.
  const table = useMemo(() => buildRamp(durationInFrames, speed), [durationInFrames, speed]);

  const sourceFrame = Math.round(table[Math.min(frame, durationInFrames)]);

  return (
    <Sequence from={frame}>
      <Video src={src} trimBefore={sourceFrame} playbackRate={speed(frame)} />
    </Sequence>
  );
};

// Example: hold 1x for 20f, ease up to 2.4x by frame 60, hold.
const rampSpeed: SpeedFn = (f) =>
  interpolate(f, [0, 20, 60], [1, 1, 2.4], {
    easing: Easing.bezier(0.65, 0, 0.35, 1),
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

export const Hero = () => <SpeedRamp src={staticFile('clips/study-loop.mp4')} speed={rampSpeed} />;
```

### Caveats you will hit

| Caveat | Detail |
|---|---|
| Source must be long enough | `table[durationInFrames]` is the last source frame consumed. If it exceeds the clip length the video freezes on its last frame (`<OffthreadVideo>` does not loop). Assert this in `calculateMetadata`. |
| fps mismatch | `trimBefore` is expressed in **composition** frames, not source frames. If the clip is 60fps and the comp is 30fps, scale the table by `sourceFps / compFps`. |
| Rounding | `Math.round` on a fractional source frame can duplicate/skip a frame at slow rates (<1x). For slow-motion, prefer `@remotion/motion-blur`'s `<CameraMotionBlur>` or optical-flow interpolation upstream in ffmpeg. |
| Audio | The ramp desyncs any audio inside the same `<Video>`. Mute the clip (`muted`) and drive audio from a separate `<Audio>` track. |
| **AMBIGUOUS** | The docs demonstrate this pattern **only** with `<OffthreadVideo>`. `<Video>` from `@remotion/media` has the same `trimBefore` + `playbackRate` props and the same seek semantics per its internals, but Remotion has not documented the combination. Render a 3-second test and eyeball frame continuity before committing. If it stutters, fall back to `<OffthreadVideo>` — the doc-blessed path. |

---

## 9. Assembling segments

`<Sequence>` props: `from`, `durationInFrames`, `layout` (`'absolute-fill'` default | `'none'`), `premountFor`, `postmountFor`. Children see a shifted `useCurrentFrame()`.

`<Series>` ([docs](https://www.remotion.dev/docs/series)) — sequential scenes, built on `<Sequence>` since v4.0.443:

```tsx
import {Series} from 'remotion';

<Series>
  <Series.Sequence durationInFrames={40}><SceneA /></Series.Sequence>
  <Series.Sequence durationInFrames={20} offset={-6}><SceneB /></Series.Sequence>
  <Series.Sequence durationInFrames={70}><SceneC /></Series.Sequence>
</Series>;
```
`offset` positive = gap, negative = overlap.

`@remotion/transitions` ([transitioning](https://www.remotion.dev/docs/transitioning)):

```tsx
import {TransitionSeries, linearTiming, springTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {slide} from '@remotion/transitions/slide';
import {AbsoluteFill} from 'remotion';

<TransitionSeries>
  <TransitionSeries.Sequence durationInFrames={40}>
    <AbsoluteFill style={{backgroundColor: 'blue'}}>Scene A</AbsoluteFill>
  </TransitionSeries.Sequence>
  <TransitionSeries.Transition
    presentation={slide()}
    timing={linearTiming({durationInFrames: 30})}
  />
  <TransitionSeries.Sequence durationInFrames={60}>
    <AbsoluteFill style={{backgroundColor: 'pink'}}>Scene B</AbsoluteFill>
  </TransitionSeries.Sequence>
</TransitionSeries>;
```

**Duration maths — the trap:** during a transition both scenes render simultaneously, so the transition duration is subtracted. `40 + 60 - 30 = 70`, not 100. Any `durationInFrames` you compute in `calculateMetadata` must subtract every transition length. Presentations available: `fade`, `slide`, `wipe`, `flip`, `clockWipe`, `none`. Timings: `linearTiming({durationInFrames})`, `springTiming({config, durationInFrames})`.

---

## 10. Audio, volume curves, ducking

Use `<Audio>` from `@remotion/media` for new code; `remotion`'s `Audio` is now the HTML5 one (also exported as `Html5Audio`) **[source-verified: `remotion` exports both `Audio` and `Html5Audio` from `./audio/index.js`]**. Docs: [audio](https://www.remotion.dev/docs/audio).

Props: `src`, `volume`, `trimBefore`/`trimAfter` (in frames), `loop`, `muted`, `playbackRate`, `toneFrequency`, `audioStreamIndex`, `loopVolumeCurveBehavior`.

```tsx
import {Audio} from '@remotion/media';
import {interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

const BED_GAIN = 0.55;
const DUCK_GAIN = 0.18;

export const Bed: React.FC<{duckWindows: [number, number][]}> = ({duckWindows}) => {
  const {durationInFrames, fps} = useVideoConfig();
  const rampF = Math.round(0.12 * fps); // 120ms duck ramp

  const volume = (f: number) => {
    // fade in / fade out
    const env = interpolate(
      f,
      [0, fps * 0.5, durationInFrames - fps * 0.8, durationInFrames],
      [0, 1, 1, 0],
      {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
    );
    // duck under any VO / sting window
    const duck = duckWindows.reduce((g, [start, end]) => {
      const d = interpolate(
        f,
        [start - rampF, start, end, end + rampF],
        [1, DUCK_GAIN / BED_GAIN, DUCK_GAIN / BED_GAIN, 1],
        {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
      );
      return Math.min(g, d);
    }, 1);
    return BED_GAIN * env * duck;
  };

  return <Audio src={staticFile('audio/bed.mp3')} volume={volume} />;
};
```

Notes:
- `volume` receives the **sequence-relative** frame, not the composition frame. Inside a `<Sequence from={90}>` the first call is `f === 0`.
- Default range is 0–1. Values >1 need `useWebAudioApi` (and CORS) — do not gain-up here, normalise the file offline instead.
- `muted` can itself be frame-dependent: `muted={frame < 30}`.

**Durations:** `getAudioDurationInSeconds(src)` from `@remotion/media-utils` returns `Promise<number>` and accepts `staticFile(...)`, imports and remote URLs. It is **`@deprecated`** in the shipped typings in favour of Mediabunny **[source-verified]** — but unlike `getVideoMetadata` it still works fine for mp3/wav. For consistency, prefer the same Mediabunny `input.computeDuration()` helper from §5 and use it inside `calculateMetadata` to set the composition length from the music bed.

---

## 11. Self-hosted `.woff2` and guaranteeing load before frame 0

[fonts](https://www.remotion.dev/docs/fonts). Put the files in `public/fonts/`. Two options; **use `@remotion/fonts`** — it wires `delayRender`/`continueRender` for you.

```tsx
// src/load-fonts.ts — import this from Root.tsx, at module scope
import {loadFont} from '@remotion/fonts';
import {staticFile} from 'remotion';

export const FONT_FAMILY = 'Marketing Sans';

export const fontsReady = Promise.all([
  loadFont({family: FONT_FAMILY, url: staticFile('fonts/Sans-Medium.woff2'), weight: '500'}),
  loadFont({family: FONT_FAMILY, url: staticFile('fonts/Sans-SemiBold.woff2'), weight: '600'}),
]);
```

Manual equivalent, if you need the raw handle:

```tsx
import {continueRender, delayRender, staticFile} from 'remotion';

const handle = delayRender('load font');
const font = new FontFace('Marketing Sans', `url('${staticFile('fonts/Sans-Medium.woff2')}') format('woff2')`);
font
  .load()
  .then(() => {
    document.fonts.add(font);
    continueRender(handle);
  })
  .catch((err) => {
    console.log('Error loading font', err);
    continueRender(handle); // otherwise the render hangs until timeout
  });
```

Hard requirements:
- Call it at **module scope** (import side effect), not inside a component body — every one of the parallel render tabs must block before painting frame 0. The [flickering](https://www.remotion.dev/docs/flickering) page lists "Ensure you correctly wait for fonts to load" as a named cause of render/preview divergence.
- Any text-measurement call (`measureText`, `@remotion/layout-utils`) must `await fontsReady` first, or you will measure in the fallback face and get different line breaks in preview vs render.
- Always `continueRender` in the `catch`, or a missing file becomes a `delayRender` timeout instead of a clear error.

---

## 12. Render flags, H.264, and mp4 metadata

```bash
npx remotion render HeroVertical out/hero.mp4 \
  --codec=h264 \
  --pixel-format=yuv420p \
  --crf=18 \
  --audio-codec=aac \
  --concurrency=50% \
  --metadata comment="flashup-hero-v3" \
  --log=info
```

| Flag | Values / default | Notes |
|---|---|---|
| `--codec` | `h264` (default), `h265`, `av1`, `vp8`, `vp9`, `prores`, `h264-mkv`, `h264-ts`, `gif`, `mp3`/`aac`/`wav` | |
| `--crf` | h264 default **18**, valid range **1–51** **[source-verified: `renderer/dist/crf.js`]** | Mutually exclusive with `--video-bitrate` |
| `--pixel-format` | `yuv420p` (default), `yuv420p10le`, `yuv422p`, `yuv444p`, `yuva420p`, `yuva444p10le` **[source-verified]** | Keep `yuv420p` — required for Safari / iOS / most social players |
| `--audio-codec` | h264 default **`aac`**; `pcm-16` is the lossless option **[source-verified: `renderer/dist/options/audio-codec.js`]** | h264 accepts `aac`, `pcm-16`, `mp3` |
| `--concurrency` | number, `"50%"`, or unset → **half of available CPU threads** | |
| `--x264-preset` | `veryfast`…`veryslow` | Slower = smaller file, same CRF |
| `--scale` | `>0` to `≤16`, default `1` | |
| `--jpeg-quality` | 0–100 | Ignored for PNG frames |
| `--muted`, `--enforce-audio-track` | | `--enforce-audio-track` writes a silent track if none exists — set it, some platforms reject audio-less mp4 |
| `--gl` | local default `null`; `angle`, `angle-egl`, `egl`, `swangle`, `swiftshader`, `vulkan` | See §13 |
| `--chrome-mode` | `chrome-headless-shell` (default) or `chrome-for-testing` | See §13 |
| `--log` | `error`, `warn`, `info` (default), `verbose` | |

**Custom raw ffmpeg output args were removed in v4.0** — there is no escape hatch. Everything must go through a flag.

### mp4 metadata — read this before designing the tag

Format: `--metadata key=value`, repeatable ([metadata](https://www.remotion.dev/docs/metadata)). Accepted mp4/mov keys: `title, artist, album_artist, composer, album, date, comment, genre, copyright, grouping, lyrics, description, synopsis, show, network, keywords` plus numeric `episode_sort, season_number, media_type, hd_video, gapless_playback, compilation`. Keys are case-insensitive. `.webm`/`.mkv` accept arbitrary keys.

Two **[source-verified]** gotchas from `@remotion/renderer@4.0.500`:

1. **Remotion prepends its own comment.** `dist/make-metadata-args.js`:
   ```js
   const defaultComment = `Made with Remotion ${VERSION}`;
   if (lowercaseKey === 'comment') {
     newMetadata[lowercaseKey] = `${defaultComment}; ${metadata[key]}`;
   }
   ```
   So `--metadata comment="flashup-hero-v3"` writes `comment=Made with Remotion 4.0.500; flashup-hero-v3`. **Any parser reading the tag back must split on `"; "` and take the tail.** If the tag must be byte-exact, use `description` or `keywords` instead of `comment`.

2. **The value cannot contain `=`.** `dist/options/metadata.js` does `a.split('=')` and throws if the result is not exactly 2 parts:
   ```
   "metadata" must be in the format of key=value, but got ...
   ```
   So `--metadata comment="v=3"` **fails the render**. Design the tag with `:` or `-` separators only. JSON blobs and base64 (which can contain `=` padding) are out — strip padding or use hex.

---

## 13. Rendering pitfalls: blur, `mix-blend-mode`, 3D transforms, huge `box-shadow`

The root cause for three of the four: **the render path is not the preview path.** Preview runs in your GPU-accelerated desktop Chrome; the render runs in Chrome Headless Shell where "the GPU is disabled in headless mode" ([gpu](https://www.remotion.dev/docs/gpu)) and rasterisation falls to software. Remotion's own GPU page names the affected properties explicitly:

> GPU-accelerated: WebGL, video decoding, `box-shadow`, `text-shadow`, `linear-gradient()`, `radial-gradient()`, `blur()`, `drop-shadow()`, `transform`, 2D canvas.

Every one of those is on your list.

| Feature | What actually breaks | Mitigation |
|---|---|---|
| **CSS blur** (`filter: blur()`, `backdrop-filter: blur()`) | Confirmed divergence: [remotion#5126](https://github.com/remotion-dev/remotion/issues/5126) — `backdrop-filter: blur(20px)` renders with **weaker blur toward the edges of the blurred region** in the output than in preview; corners are visibly under-blurred. Also [#9052](https://github.com/remotion-dev/remotion/issues/9052): large CSS blur rasterises differently per chunk, producing **visible seams at chunk boundaries** when a render is split. | Prefer `filter: blur()` on an element over `backdrop-filter` (the backdrop variant is the one with the reported edge bug). Keep radii modest (<24px). Add padding/overdraw around the blurred element so the wrong edges fall outside frame. If a render is chunked, do not blur across the seam. Verify with `npx remotion still` at three frames rather than trusting the Studio. |
| **`mix-blend-mode`** | **AMBIGUOUS — no Remotion doc and no filed issue exists.** I searched the Remotion issue tracker and found nothing about `mix-blend-mode` correctness. What is documented is that blend compositing is a rasteriser feature, and the rasteriser differs between preview and render. The realistic failure modes are (a) blend applying against a different backdrop because the software compositor promotes layers differently, and (b) blend silently becoming a no-op when the element gets its own compositing layer via `transform`/`filter`/`will-change`. Treat as unverified risk. | Make the blend group explicit: wrap the blended element and its backdrop in a parent with `isolation: isolate`, and do not put `transform`/`filter`/`opacity < 1` on that parent. Render a still on frame 0 and diff it against the Studio screenshot before building the design on it. |
| **`perspective` / 3D transforms** | Runs, but is a known source of layout weirdness inside Remotion's own tooling ([remotion#8290](https://github.com/remotion-dev/remotion/issues/8290): "`perspective` messes with Studio outline"). The broader risk is the same rasteriser divergence: sub-pixel positioning and edge antialiasing of 3D-transformed layers differ under software rasterisation, and `transform-style: preserve-3d` interacts badly with `overflow`, `filter` and `mix-blend-mode` (any of those on an ancestor flattens the 3D context — this is standard CSS, not a Remotion bug, but it bites hardest when preview and render disagree about layer promotion). | Keep 3D shallow: one `perspective` parent, one transformed child. Never combine `preserve-3d` with `filter`, `overflow: hidden`, `mask` or `mix-blend-mode` on the same subtree. Prefer 2D `scale`+`skew` fakes for card flips where possible. |
| **Very large `box-shadow`** | The pure performance one. `box-shadow` is on Remotion's GPU-accelerated list; under software rasterisation a large blur radius over a large area is rasterised on CPU **every frame, in every concurrent tab**. Expect multi-second per-frame times and, on `--gl=angle`, memory pressure — Remotion warns that angle "has known memory leak issues; split large renders into multiple parts" ([gl-options](https://www.remotion.dev/docs/gl-options)). Correctness is generally preserved; throughput is not. | Bake large soft shadows into a PNG/WebP asset and place it with `<Img>`. If it must be live, cap the radius and spread, and drop `--concurrency` so tabs do not contend for CPU. Measure with `--log=verbose`. |

Cross-cutting mitigations:

- **Verify with stills, not the Studio.** `npx remotion still <comp> out/f0.png --frame=0` uses the render pipeline.
- **`--chrome-mode=chrome-for-testing`** switches to a Chrome build "optimized for GPU-accelerated rendering" ([chrome-headless-shell](https://www.remotion.dev/docs/miscellaneous/chrome-headless-shell)). Costs more resources; not available on Lambda/Cloud Run. Worth trying if blur output looks wrong.
- **`--gl`**: local default is `null`. Only reach for `angle` if you add WebGL; it is faster with a GPU but leaks memory and fails outright on CI runners without a GPU. `swangle` is the safe software option.
- **Flickering ≠ these bugs.** The [flickering](https://www.remotion.dev/docs/flickering) page covers a different failure: state that is not a pure function of `useCurrentFrame()`, because each of the parallel tabs starts cold. Also: avoid `background-image` and `mask-image` (named there as not awaited), and use Remotion's asset components rather than raw tags.

---

## Version pin summary

```
remotion              4.0.500
@remotion/cli         4.0.500
@remotion/bundler     4.0.500
@remotion/renderer    4.0.500
@remotion/media       4.0.500
@remotion/transitions 4.0.500
@remotion/fonts       4.0.500
@remotion/zod-types   4.0.500
zod                   (whatever @remotion/zod-types resolves)
mediabunny            latest
```
Do **not** use `@remotion/media-parser` or `@remotion/webcodecs` — both are slated for deprecation in favour of Mediabunny ([5-0-migration](https://www.remotion.dev/docs/5-0-migration)).
