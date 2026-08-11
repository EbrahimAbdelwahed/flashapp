/**
 * Colour tokens — spec §1.2. Single source of truth.
 *
 * No brand identity exists yet. Warm accent on deep ink, chosen because the study-app
 * category is saturated with blue and violet. Changing the brand later must stay a
 * one-file edit, so nothing anywhere else in this project may write a hex value.
 */
export const theme = {
  ink900: '#070910', // deepest background
  ink800: '#0A0D14', // canvas base
  ink600: '#16203A', // cool bloom
  ember700: '#3A1F12', // warm bloom
  ember500: '#FF8A3D', // primary accent — CTA, ripple, key words
  ember300: '#FFB784', // accent, secondary
  paper: '#F7F4EF', // primary text — NOT pure white, warm off-white
  muted: '#9AA3B2', // secondary text
} as const;

/**
 * Canvas geometry — §1.4. 1080×1920 at 60 fps.
 */
export const canvas = {
  width: 1080,
  height: 1920,
  fps: 60,
} as const;

/**
 * Text is anchored inside this box. No exceptions: §4.3 rejects a brief whose rendered
 * overlay bounds fall outside it.
 *
 * Above `top` sits the platform UI; below `bottom` sit the TikTok/Instagram caption and
 * button rail. Both are dead zones, not margins to be borrowed from.
 */
export const safeArea = {
  left: 108,
  right: 972,
  top: 280,
  bottom: 1500,
  get contentWidth() {
    return this.right - this.left;
  },
} as const;

/**
 * Device layer placement — §1.4, §1.5.
 *
 * The recording is composited as a floating rounded rectangle, never as a photo of a
 * phone. An iPhone records about 19.5:9, taller than 9:16, so there is always canvas
 * around it; what goes there is the film.
 */
export const device = {
  height: 1560,
  top: 200,
  /** Corner radius in device points, scaled to the recording at render time. */
  cornerRadiusInPoints: 55,
} as const;

/**
 * Derives the device rect from the recording's real dimensions.
 *
 * Never hardcode a width: §1.4 requires computing from `getVideoMetadata`, and a wrong
 * constant shows up as a non-uniform scale, which is the one thing the spec forbids
 * outright. If the numbers do not work, change the height — never the aspect ratio.
 */
export const deviceRect = (
  sourceWidth: number,
  sourceHeight: number,
  sourceWidthInPoints: number,
) => {
  const width = device.height * (sourceWidth / sourceHeight);
  return {
    width,
    height: device.height,
    top: device.top,
    left: (canvas.width - width) / 2,
    cornerRadius: device.cornerRadiusInPoints * (width / sourceWidthInPoints),
  };
};

/**
 * Type scale — §1.3. Sentence case only, never ALL CAPS, never Title Case.
 *
 * Negative tracking above 60px is what separates typeset from typed. No outlines and no
 * drop shadows: insufficient contrast is solved with a scrim or by moving the text.
 */
export const typography = {
  hook: {
    fontSize: 76,
    fontWeight: 600,
    letterSpacing: '-0.025em',
    lineHeight: 1.08,
    color: theme.paper,
    maxLines: 2,
    maxWords: 7,
  },
  punch: {
    fontSize: 96,
    fontWeight: 600,
    letterSpacing: '-0.030em',
    lineHeight: 1.05,
    color: theme.paper,
    maxLines: 1,
    maxWords: 4,
  },
  sub: {
    fontSize: 44,
    fontWeight: 500,
    letterSpacing: '-0.010em',
    lineHeight: 1.25,
    color: theme.muted,
    maxLines: 1,
    maxWords: 7,
  },
  save_cta: {
    fontSize: 38,
    fontWeight: 500,
    letterSpacing: '0',
    lineHeight: 1.2,
    color: theme.paper,
    maxLines: 1,
    maxWords: 7,
  },
  endcard_h: {
    fontSize: 88,
    fontWeight: 600,
    letterSpacing: '-0.030em',
    lineHeight: 1.05,
    color: theme.paper,
    maxLines: 2,
    maxWords: 7,
  },
  endcard_c: {
    fontSize: 40,
    fontWeight: 500,
    letterSpacing: '-0.005em',
    lineHeight: 1.3,
    color: theme.muted,
    maxLines: 2,
    maxWords: 7,
  },
} as const;

export type TextStyle = keyof typeof typography;

/**
 * Instrument Sans, not General Sans.
 *
 * The .woff2 files are not in assets/fonts/ yet, so the stack falls through to Helvetica
 * for now. That is a placeholder, not a choice: an unresolved family previously fell all
 * the way to a serif, which §1.3 rules out. Self-host the two weights before any render is
 * judged on its typography.
 *
 * General Sans's ITF licence forbids "uploading them in a public server" and transmitting
 * the font "in font serving" — which is exactly self-hosting a .woff2. §1.3 names
 * Instrument Sans (SIL OFL) as the fallback for precisely this case. Ship OFL.txt next to
 * the font files; nothing appears on screen. See docs/ASSETS_LICENSING.md.
 */
export const fontFamily =
  "'Instrument Sans', 'Helvetica Neue', Helvetica, Arial, sans-serif";
