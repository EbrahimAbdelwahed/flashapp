/**
 * Motion system — spec §1.6. Single source of truth.
 *
 * Everything moves. A static frame reads as a recording; a moving frame reads as
 * direction. Linear is forbidden except for the camera push and the grain.
 *
 * This file is a floor, not a cage (§1.16): roughly 5% of moments should deviate
 * deliberately, and the brief's per-segment `overrides` object is how they do it. A film
 * where every entrance is exactly 20 frames feels mechanical even when nothing looks
 * wrong.
 */
import { Easing } from 'remotion';

export const EASE_OUT = Easing.bezier(0.22, 1.0, 0.36, 1.0); // entrances
export const EASE_INOUT = Easing.bezier(0.65, 0.0, 0.35, 1.0); // moves
export const EASE_IN = Easing.bezier(0.55, 0.0, 1.0, 0.45); // exits

/** Text entrance — 20 frames (333 ms at 60 fps), all properties simultaneous. */
export const textIn = {
  durationInFrames: 20,
  /** Opacity resolves in the first half; the rest keeps travelling. */
  opacityInFrames: 10,
  translateY: 28,
  scaleFrom: 0.97,
  blur: 8,
  /** Multi-line blocks stagger by this much per line. */
  staggerPerLine: 4,
} as const;

/** Text exit — 12 frames. Shorter than the entrance on purpose: leaving is not an event. */
export const textOut = {
  durationInFrames: 12,
  translateY: -12,
  blur: 6,
} as const;

/**
 * Camera push — the device layer scales across each segment.
 *
 * Direction alternates between consecutive segments so the film never feels on rails; the
 * brief declares `"push": "in" | "out"` per segment.
 */
export const push = {
  from: 1.0,
  to: 1.045,
} as const;

/**
 * Cut transition — a hard cut plus a short settle on the incoming segment.
 * No dissolves between app footage. No wipes, ever.
 */
export const cut = {
  settleInFrames: 6,
  settleFrom: 1.02,
  settleTo: 1.0,
} as const;

/** Springs, end card only (§1.10). */
export const springs = {
  /** Wordmark: overdamped, no overshoot. */
  wordmark: { damping: 200, stiffness: 100, mass: 0.6 },
  /** CTA line: slight overshoot, delayed. */
  cta: { damping: 26, stiffness: 180, mass: 0.7 },
  ctaDelayInFrames: 12,
} as const;

/**
 * Tap ripple — §1.8.
 *
 * The simulator's grey `ShowSingleTouches` circle is a screencast tell and is switched off
 * at capture; this is what replaces it. Diameter is expressed in the source recording's
 * coordinate space and scales with the device layer.
 */
export const ripple = {
  durationInFrames: 24,
  diameterInSourcePixels: 120,
  scaleFrom: 0,
  scaleTo: 1.6,
  opacityFrom: 0.55,
  opacityTo: 0,
} as const;

/**
 * Hero breakout — §1.14. A UI element leaves the screen plane, crosses the device rect,
 * holds, and returns exactly to its origin.
 *
 * The recede on the supporting layers is what sells it: without it the move reads as a
 * zoom rather than as depth.
 */
export const hero = {
  lift: {
    durationInFrames: 24,
    overshootScale: 1.05,
    rotateX: -10,
  },
  hold: {
    durationInFrames: 60,
    driftFrom: 1.8,
    driftTo: 1.83,
  },
  return: {
    durationInFrames: 33,
  },
  /** The rest of the device, same curve. */
  recede: {
    opacityTo: 0.35,
    blurTo: 6,
    scaleTo: 0.97,
  },
  perspective: 1600,
} as const;

/**
 * The money shot — §1.7. The card flip plays at half speed and holds for a full two
 * seconds. It is the only moment that slows down, and the thing viewers must remember.
 */
export const moneyShot = {
  rate: 0.5,
  holdInSeconds: 2.0,
} as const;

/** Total length target — §1.7. 60 s is a technical ceiling, not a goal. */
export const duration = {
  targetMinInSeconds: 18,
  targetMaxInSeconds: 28,
  hardCeilingInSeconds: 60,
} as const;

/**
 * Beat grid — §1.9.
 *
 * The track and its BPM are the first fields filled in a brief, before a single segment is
 * timed. Every segment boundary and overlay in/out snaps to this grid. An edit assembled
 * first and scored afterwards will never lock in.
 */
export const beatGrid = (bpm: number, offsetInSeconds: number, fps: number) => {
  const secondsPerBeat = 60 / bpm;
  return {
    secondsPerBeat,
    framesPerBeat: secondsPerBeat * fps,
    /** Nearest beat boundary to a time in seconds. */
    snap: (seconds: number) => {
      const beats = Math.round((seconds - offsetInSeconds) / secondsPerBeat);
      return offsetInSeconds + beats * secondsPerBeat;
    },
  };
};
