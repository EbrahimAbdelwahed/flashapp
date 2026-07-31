# Assets & licensing

Researched 2026-07-29. Scope: self-hosted webfont, a ~30s music bed, and 6 UI SFX — all for **commercial social-media marketing video ads** plus a landing page, with **no on-screen attribution**.

---

## A. Font

### Verdict

> **Use Instrument Sans (SIL OFL 1.1). Do NOT self-host General Sans.**
>
> General Sans's licence forbids the exact thing we want to do — serving the font file from our own server. The video render itself would be fine; the landing page would not. Rather than run two different typefaces (or run the landing page off Fontshare's CDN while the video uses a local file, which is a maintenance trap and violates the "never a CDN" constraint), switch both to Instrument Sans, which is unambiguously free to self-host.

### General Sans — what the licence actually says

- Licence: **ITF Free Font License / "Free Font — End User License Agreement (FF EULA)"**, last updated 22 March 2021, Copyright 2021 Indian Type Foundry. Confirmed via the Fontshare API: `general-sans` has `"license_type": "itf_ffl"`. Full text ships as `GeneralSans_Complete/License/FFL.txt` inside the download.
- Commercial use is **granted**, generously: clause 01 — *"for your personal or commercial use for an unlimited period of time for free of charge. You may use the font Software in any media (including Print, Web, Mobile, Digital, Apps, ePub, **Broadcasting** and OEM) at any scale, at any location worldwide."*
- Attribution is **not required**: *"You may but are not required to identify Indian Type Foundry Fonts in your work credits."*
- **The blocker is clause 02:**
  > *"The Fonts may not — beyond the permitted copies and the uses defined herein — be distributed, duplicated, loaned, resold or licensed in any way ... This includes ... **uploading them in a public server** or making the fonts available on peer-to-peer networks."*
  >
  > *"You are **not allowed to transmit the Font Software over the Internet in font serving or for font replacement** by means of technologies such as but not limited to EOT, Cufon, sIFR or similar technologies that may be developed in the future without the prior written consent of the Licensor."*

  Self-hosting `.woff2` on our landing page *is* uploading the font to a public server and transmitting it over the internet for font serving. That is what the clause prohibits. ITF's intended web path is their own API/CDN (`api.fontshare.com`), which the EULA explicitly contemplates.

- **AMBIGUOUS, but not in our favour:** the download kit *does* ship a `Fonts/WEB/` folder with `.woff2` files and a `README.md` titled "Installing Webfonts" that walks you through `@font-face` self-hosting — which reads like permission, and directly contradicts clause 02. Fontshare's public FAQ also markets an "offline kit for self-hosting". A README is not a licence amendment; the EULA governs. **This is a real conflict and only ITF can resolve it** — the only clean route to using General Sans on the web is written consent from ITF or using their CDN.
- **Video-only use would be fine.** Rendering text to pixels produces a "Derivative Work" (clause 05: *"the pictorial representation of the font created by the Font Software"*), permitted for commercial use, and "Broadcasting" is a named permitted medium. Nothing about the *video* is a problem. Only the *landing page* is.

Download (for reference / desktop use only, not for serving):

| Item | URL |
|---|---|
| Complete kit (ZIP, 2.27 MB, `GeneralSans_Complete.zip`) | `https://api.fontshare.com/v2/fonts/download/general-sans` |
| Licence text inside | `GeneralSans_Complete/License/FFL.txt` |
| CDN CSS (the sanctioned web path) | `https://api.fontshare.com/v2/css?f[]=general-sans@500,600&display=swap` |
| Weight 500 woff2 (CDN) | `https://cdn.fontshare.com/wf/3RZHWSNONLLWJK3RLPEKUZOMM56GO4LJ/BPDRY7AHVI3MCDXXVXTQQ76H3UXA63S3/SB2OEB6IKZPRR6JT4GFJ2TFT6HBB6AZN.woff2` |
| Weight 600 woff2 (CDN) | `https://cdn.fontshare.com/wf/K46YRH762FH3QJ25IQM3VAXAKCHEXXW4/ISLWQPUZHZF33LRIOTBMFOJL57GBGQ4B/3ZLMEXZEQPLTEPMHTQDAUXP5ZZXCZAEN.woff2` |

### Instrument Sans — the recommendation

| Field | Value |
|---|---|
| Licence | **SIL Open Font License 1.1** |
| Self-host `.woff2` | Yes, explicitly. OFL permits redistribution of the font files themselves. |
| Commercial use | Yes, no fee, no restriction |
| Use in video / ads | Yes |
| Attribution | Not required in the product. OFL only requires that the **copyright + licence notice travel with the font files** — so ship `OFL.txt` next to the `.woff2` in `public/fonts/`. Nothing appears on screen or on the page. |
| Only real restriction | You may not sell the font files on their own, and a modified version may not use the Reserved Font Name "Instrument Sans". |
| Designer / origin | Rodrigo Fuenzalida for Instrument, 2022. Variable, 4 weights + italics, 389 languages. |
| Google Fonts | https://fonts.google.com/specimen/Instrument+Sans |
| Upstream repo | https://github.com/Instrument/instrument-sans (branch `master`) |

Exact download URLs for the two weights we want:

| Weight | File | URL |
|---|---|---|
| 500 | `InstrumentSans-Medium.woff2` | `https://raw.githubusercontent.com/Instrument/instrument-sans/master/fonts/webfonts/InstrumentSans-Medium.woff2` |
| 600 | `InstrumentSans-SemiBold.woff2` | `https://raw.githubusercontent.com/Instrument/instrument-sans/master/fonts/webfonts/InstrumentSans-SemiBold.woff2` |
| — | Licence (ship alongside) | `https://raw.githubusercontent.com/Instrument/instrument-sans/master/OFL.txt` |

Alternative source — Google's own woff2 (subsetted, smaller, but weights 500 and 600 resolve to the **same variable file**, so one download covers both):

```
https://fonts.gstatic.com/s/instrumentsans/v4/pxiTypc9vsFDm051Uf6KVwgkfoSxQ0GsQv8ToedPibnr0SZe1ZuWi3g.woff2   # latin
```
Fetch once at setup time and commit it; never link `fonts.googleapis.com` at render time.

Fetch script:

```bash
mkdir -p marketing-pipeline/remotion/public/fonts
BASE=https://raw.githubusercontent.com/Instrument/instrument-sans/master
curl -sL "$BASE/fonts/webfonts/InstrumentSans-Medium.woff2"   -o marketing-pipeline/remotion/public/fonts/InstrumentSans-Medium.woff2
curl -sL "$BASE/fonts/webfonts/InstrumentSans-SemiBold.woff2" -o marketing-pipeline/remotion/public/fonts/InstrumentSans-SemiBold.woff2
curl -sL "$BASE/OFL.txt"                                      -o marketing-pipeline/remotion/public/fonts/OFL.txt
```

### If the owner insists on General Sans

Two lawful options, both worse:
1. Landing page loads from `api.fontshare.com` (CDN, sanctioned by the EULA) while the Remotion render uses a local copy on the build machine (device use, not serving — permitted). Violates the "never a CDN" rule and makes the page depend on ITF's uptime.
2. Email ITF for written consent to self-host (clause 02 allows it "without the prior written consent of the Licensor" — i.e. with consent it's fine). Contact route is Fontshare/ITF; expect no SLA.

---

## B. Music bed

### Verdict

> **Use Pixabay Music.** It is the only source in this list whose free licence permits commercial use *and* paid advertising *and* requires no attribution at all — not on screen, not in a text file, not anywhere. Free Music Archive (CC BY subset) is the credible backup when you want a named human artist and can live with a line in a credits file.

### Source-by-source

| Source | Exact licence | Attribution required? | On screen? | Commercial ads allowed? | Verdict |
|---|---|---|---|---|---|
| **Pixabay Music** | Pixabay Content License | **No** — *"Attribution of the photographer, videographer, musician or Pixabay is not required but is always appreciated."* | No | **Yes.** Grant is *"an irrevocable, worldwide, non-exclusive and royalty free right to use, download, copy, modify or adapt the Content for commercial or non-commercial purposes."* No advertising carve-out. | ✅ **Use** |
| **Free Music Archive** — CC0 subset | CC0 1.0 | No | No | Yes | ✅ Good, but the CC0 pool is small |
| **Free Music Archive** — CC BY subset | CC BY 4.0 | **Yes** | No — CC BY requires credit "in any reasonable manner for the medium"; a credits file / post description is the accepted norm | Yes | ✅ Acceptable backup |
| **Uppbeat** free tier | Uppbeat free licence | **Yes** — must paste an "Uppbeat Credit" in the description | Not on screen, but mandatory | ❌ **NO.** *"Free users are not permitted to use content in Paid Advertising, unless they hold a Paid Subscription to Uppbeat Pro."* Digital ads and client work are Pro-only ($27.99/mo). | 🚩 **FLAG — free tier secretly forbids advertising. Do not use.** |
| **Bensound** free tier | Bensound Free License | **Yes**, single-use attribution string in the description | Not on screen, but mandatory | ❌ **NO.** Free licence covers *"an online video or live video streaming that is published AND accessible free of charge, OR ... educational purpose only and does not generate revenue."* A product ad is neither. Missing/incorrect attribution reportedly triggers copyright claims even on the free tier. | 🚩 **FLAG — free tier excludes commercial ads. Do not use.** |
| **ccMixter** | Per-track CC; heavily weighted to **CC BY-NC** and CC BY-SA | Yes (all CC BY variants) | No | Only for the CC BY / CC BY-SA tracks. **Any `-NC` track is disqualified** for a product ad. | ⚠️ Usable but you must check every track; high mis-pick risk |
| **Incompetech / Kevin MacLeod** | CC BY 4.0 (paid "Standard License" removes attribution) | **Yes** | No — *"a person who wants to know where the music came from should have no difficulty in finding it"*; a credits file qualifies | Yes under CC BY. Incompetech itself sells a paid licence specifically *"for projects where attribution is not wanted or is impossible (radio/TV ads, corporate presentations...)"* — a hint that ad platforms make CC BY awkward. | ⚠️ Works, but stylistically wrong for us (library/cue music, little minimal piano or ambient electronica) |

### Concrete candidates

All Pixabay unless noted. Pixabay does **not publish BPM** on track pages (verified — the metadata shown is genre / mood / movement / theme, no tempo field), so BPM is listed as unpublished; measure locally (see below). Durations are the full track; we need ~30s, so pick a section and top-and-tail it.

| # | Track | Artist | URL | Length | Genre tags | Fit |
|---|---|---|---|---|---|---|
| 1 | **Moment of Peace** | MickeysCat | https://pixabay.com/music/solo-piano-moment-of-peace-mickeyscat-554494/ | 2:32 | Solo Piano, Ambient; mood Peaceful/Uplifting; movement Medium | **Top pick.** Actual solo piano, no drums, no riser. Editor's Choice. |
| 2 | **Ambient Piano and Strings** | — | https://pixabay.com/music/beautiful-plays-ambient-piano-and-strings-10711/ | 3:37 | Beautiful Plays / Ambient | Piano + pad. Watch for a swell around the midpoint — take the first 40s. |
| 3 | **Caves of Dawn** | — | https://pixabay.com/music/ambient-caves-of-dawn-10376/ | 3:22 | Ambient | Ambient-electronica texture, no percussion. Good under a speed ramp. |
| 4 | **Midnight Forest** | Syouki_Takahashi | https://pixabay.com/music/ambient-midnight-forest-184304/ | 2:48 | Ambient | Darker, sparse. Good if the cut is moody rather than warm. |
| 5 | **Reflected Light** | — | https://pixabay.com/music/beautiful-plays-reflected-light-147979/ | 3:44 | Beautiful Plays | Minimal piano/pad hybrid. |

Non-Pixabay backup, if you want a credited human artist (CC BY 4.0, verified on the track page):

| Track | Artist | URL | Licence |
|---|---|---|---|
| **Away** (album *Ambient*) | Meydän | https://freemusicarchive.org/music/Meydan/Ambient_1860/Away_1569/ | CC BY 4.0 |
| **Elk** (album *Ambient*) | Meydän | https://freemusicarchive.org/music/Meydan/Ambient_1860/Elk/ | CC BY 4.0 |
| **Freezing but warm** (album *Ambient*) | Meydän | https://freemusicarchive.org/music/Meydan/Ambient_1860/Freezing_but_warm/ | CC BY 4.0 |

### Two things to check before locking a track

1. **YouTube Content ID.** Pixabay track pages carry a "Content ID Registered" badge (observed on *Moment of Peace*). The Pixabay licence still permits the use, but a Content-ID-registered track can trigger an automated claim on YouTube/Meta and, worse, can get *someone else's* ad muted or demonetised. **Check the badge on every candidate** and prefer non-registered tracks for paid social. Keep the download page URL + a screenshot of the licence banner in `marketing-pipeline/assets/audio/LICENSE.md` as proof.
2. **The one Pixabay prohibition that could apply.** You may not *"sell or distribute Content ... without adding any additional elements or otherwise adding value."* Using a bed under a video is obviously additive; re-uploading the mp3 is not. We are fine.

### Measuring BPM locally

```bash
# rough tempo estimate, no extra deps beyond ffmpeg + python
pip install librosa soundfile
python3 - <<'PY'
import librosa
y, sr = librosa.load('marketing-pipeline/remotion/public/audio/bed.mp3', sr=22050, duration=60)
tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
print('BPM ~', float(tempo))
PY
```

### Preparing the 30s bed

```bash
ffmpeg -y -i raw-bed.mp3 -ss 00:00:18 -t 32 \
  -af "afade=t=in:st=0:d=1.2,afade=t=out:st=30.5:d=1.5,loudnorm=I=-18:TP=-1.5:LRA=11" \
  -ar 48000 -ac 2 -c:a libmp3lame -q:a 2 \
  marketing-pipeline/remotion/public/audio/bed.mp3
```
`-18 LUFS` leaves headroom for the SFX layer and matches a bed that will be ducked to ~0.18 gain under a sting (see REMOTION_NOTES §10).

---

## C. UI sound samples

### Verdict

> **Synthesise all six with ffmpeg.** Do not source them.

Reasons, in order of weight:
1. **Spec precision.** "tap (~12ms click)" is a tolerance no stock library hits. Every command below produces exactly the requested length.
2. **Zero licence surface.** A synthesised waveform has no provenance to document, no CC0 claim to verify, no Freesound account to gate the build. Freesound's CC0 filter is genuinely CC0, but downloads require a logged-in account — that breaks a reproducible `make assets`.
3. **Reproducibility.** The commands live in the repo; the `.wav` files are regenerable and don't need to be committed as binaries.
4. **Coherence.** Six sounds derived from the same synthesis primitives sound like one design system. Six stock samples from six uploaders do not.

CC0 fallback sources, if a synthesised sound doesn't land:

| Source | Licence | Notes |
|---|---|---|
| freesound.org with the **CC0** filter | CC0 1.0 — no attribution, commercial OK | Best quality. Requires a free account to download → not CI-friendly. |
| Pixabay **Sound Effects** | Pixabay Content License — no attribution, commercial + ads OK | Same licence as the music above. Easiest drop-in. |
| Mixkit SFX free | Mixkit License — free commercial, no attribution | Check the per-asset terms; some categories differ. |

### The six commands (all verified to run on ffmpeg 8.0, macOS arm64)

Output: 48 kHz mono `pcm_s16le` WAV into `marketing-pipeline/remotion/public/sfx/`.

```bash
SFX=marketing-pipeline/remotion/public/sfx
mkdir -p "$SFX"

# 1. tap — 12 ms filtered click
ffmpeg -y -f lavfi -i "anoisesrc=c=white:r=48000:a=0.9:d=0.012" \
  -af "highpass=f=1200,lowpass=f=7000,afade=t=out:st=0.002:d=0.010:curve=exp,volume=1.6" \
  -c:a pcm_s16le "$SFX/tap.wav"

# 2. whoosh — 450 ms band-passed pink noise, slow in / fast out
ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=48000:a=1:d=0.45" \
  -af "bandpass=f=900:width_type=o:w=2,afade=t=in:st=0:d=0.18:curve=qua,afade=t=out:st=0.18:d=0.27:curve=exp,volume=2.0" \
  -c:a pcm_s16le "$SFX/whoosh.wav"

# 3. flip — 130 ms bright transient with a 22 ms slap (card-turn)
ffmpeg -y -f lavfi -i "anoisesrc=c=white:r=48000:a=0.7:d=0.13" \
  -af "bandpass=f=2200:width_type=o:w=1.5,afade=t=out:st=0.01:d=0.12:curve=exp,aecho=0.8:0.6:22:0.35,volume=1.4" \
  -c:a pcm_s16le "$SFX/flip.wav"

# 4. success — A5 -> E6 two-note chime, second note delayed 90 ms
ffmpeg -y \
  -f lavfi -i "sine=f=880:r=48000:d=0.42" \
  -f lavfi -i "sine=f=1318.51:r=48000:d=0.42" \
  -filter_complex "[0:a]afade=t=out:st=0:d=0.30:curve=exp,adelay=0|0[a];\
[1:a]afade=t=out:st=0:d=0.42:curve=exp,adelay=90|90[b];\
[a][b]amix=inputs=2:normalize=0,volume=0.7,aformat=channel_layouts=mono" \
  -c:a pcm_s16le "$SFX/success.wav"

# 5. sting — C5/G5/C6 stab with a two-tap tail
ffmpeg -y \
  -f lavfi -i "sine=f=523.25:r=48000:d=0.9" \
  -f lavfi -i "sine=f=784:r=48000:d=0.9" \
  -f lavfi -i "sine=f=1046.5:r=48000:d=0.9" \
  -filter_complex "[0:a][1:a][2:a]amix=inputs=3:normalize=0,\
afade=t=out:st=0.02:d=0.85:curve=exp,aecho=0.9:0.8:180|340:0.35|0.18,\
volume=0.55,aformat=channel_layouts=mono" \
  -c:a pcm_s16le "$SFX/sting.wav"

# 6. sub_drop — 90 Hz -> 28 Hz linear chirp over 700 ms
ffmpeg -y -f lavfi \
  -i "aevalsrc='0.9*sin(2*PI*(90*t - (90-28)*t*t/(2*0.7)))':s=48000:d=0.7" \
  -af "lowpass=f=200,afade=t=in:st=0:d=0.02,afade=t=out:st=0.35:d=0.35:curve=exp" \
  -c:a pcm_s16le "$SFX/sub_drop.wav"
```

Measured output (ffprobe / `volumedetect`, all 48 kHz mono):

| File | Duration | Peak | Mean |
|---|---|---|---|
| `tap.wav` | 0.012 s | −1.3 dB | −15.8 dB |
| `whoosh.wav` | 0.450 s | −8.9 dB | −26.5 dB |
| `flip.wav` | 0.152 s | −10.5 dB | −28.5 dB |
| `success.wav` | 0.510 s | −21.0 dB | −36.3 dB |
| `sting.wav` | 1.240 s | −17.3 dB | −37.0 dB |
| `sub_drop.wav` | 0.700 s | −0.9 dB | −7.0 dB |

Note `flip` and `sting` come out longer than their source duration because `aecho` appends the tail — that is intended.

**Levels are not consistent** (−0.9 dB to −21 dB peak), so normalise as a second pass before shipping:

```bash
for f in "$SFX"/*.wav; do
  ffmpeg -y -i "$f" -af "loudnorm=I=-16:TP=-1.5:LRA=7" -ar 48000 -c:a pcm_s16le "${f%.wav}.norm.wav" \
    && mv "${f%.wav}.norm.wav" "$f"
done
```
Skip `tap.wav` in that loop — `loudnorm` needs more than 12 ms to measure; peak-normalise it instead with `-af "volume=-1.5dB:precision=fixed"` after measuring, or just leave it (it already peaks at −1.3 dB).

Tuning knobs: `bandpass f=` sets the whoosh's perceived size (lower = heavier); `aecho` delay ms sets the flip's "thickness"; the `90`/`28` in `sub_drop` are the start/end frequencies of the chirp — do not go below ~25 Hz, phone speakers won't reproduce it and it just eats headroom.
