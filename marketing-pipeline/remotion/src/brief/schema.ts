/**
 * Brief schema — spec §4.3.
 *
 * Fields are declared in authoring order: promise, then music, then storyboard, then the
 * timeline. That order is deliberate and load-bearing. §1.13 forbids writing a brief
 * before its promise exists, and §1.9 requires the track and its BPM to be chosen before a
 * single segment is timed, because an edit assembled first and scored afterwards never
 * locks in. A schema that accepted these fields in any order would let both mistakes
 * through silently.
 *
 * Structural rules live here. Rules that need to see the whole timeline at once — overlay
 * overlap, save-CTA placement, hero count — live in `validate.ts`.
 */
import { z } from 'zod';

/** §5.6. The join key between a rendered file, a published post and a waitlist signup. */
export const VARIANT_TAG = /^fu-[A-Z]\d{1,2}-[a-z]{3,4}-[a-z]{4}-h\d{2}(-r\d+)?$/;

/**
 * §1.11: no emoji anywhere in overlay copy.
 *
 * Matches pictographic scalars rather than a hand-listed range, so a new emoji block in a
 * future Unicode revision does not quietly become legal.
 */
const EMOJI = /\p{Extended_Pictographic}/u;

/** §1.11: maximum 7 words per overlay. More than that means two overlays, or a cut. */
const MAX_WORDS_PER_OVERLAY = 7;

const copy = z
  .string()
  .min(1, 'Overlay copy cannot be empty')
  .refine((text) => !EMOJI.test(text), '§1.11: no emoji anywhere in overlay copy')
  .refine(
    (text) => text.trim().split(/\s+/).length <= MAX_WORDS_PER_OVERLAY,
    `§1.11: maximum ${MAX_WORDS_PER_OVERLAY} words per overlay — use two overlays, or cut`,
  )
  .refine(
    (text) => text !== text.toUpperCase() || !/\p{Letter}/u.test(text),
    '§1.3: sentence case only, never ALL CAPS',
  );

/**
 * A point on a segment's speed curve. `at` is a time in the *source* clip.
 *
 * §1.7 bans a flat rate outright: every segment declares a ramp, typically fast across
 * navigation and decelerating into the payoff. Rates are applied by frame remapping, not
 * `playbackRate` — which, verified against the 4.0.500 typings, only accepts a single
 * number and so cannot vary over time at all.
 */
const rampPoint = z.object({
  at: z.number().min(0),
  rate: z.number().gt(0).max(8),
});

export const segmentSchema = z.object({
  /** Clip id, matching a file in out/clips/<deck>/. */
  src: z.string().min(1),
  in: z.number().min(0),
  out: z.number().gt(0),
  ramp: z
    .array(rampPoint)
    .min(2, '§1.7: a flat speed is banned — declare a ramp with at least two points')
    .refine(
      (points) => points.every((point, index) => index === 0 || point.at > points[index - 1].at),
      'Ramp points must be strictly ascending in `at`',
    ),
  push: z.enum(['in', 'out']),
  taps: z
    .array(z.object({ t: z.number().min(0), x: z.number(), y: z.number() }))
    .optional(),
  hero: z
    .object({
      at: z.number().min(0),
      element: z.string().min(1),
      scale: z.number().gt(1),
      /** §1.14: tilt is the default; set false for a flat scale. */
      tilt: z.boolean().default(true),
      hold: z.number().gt(0),
      /**
       * The footage underneath must freeze for the duration of the breakout and resume on
       * the return frame, or the two layers desync. §4.3 rejects a hero without it, so it
       * is required rather than defaulted.
       */
      freezeUnder: z.literal(true, {
        message: '§1.14: a hero breakout requires freezeUnder — layers desync without it',
      }),
    })
    .optional(),
  /** §1.16: the sanctioned way to violate the motion system where the film asks for it. */
  overrides: z.record(z.string(), z.number()).optional(),
});

export const overlaySchema = z
  .object({
    text: copy,
    style: z.enum(['hook', 'punch', 'sub', 'save_cta', 'endcard_h', 'endcard_c']),
    anchor: z.enum(['top', 'center', 'bottom']),
    start: z.number().min(0).optional(),
    end: z.number().min(0).optional(),
    /** Negative offsets from the end of the film, for overlays that ride the outro. */
    startRelEnd: z.number().optional(),
    endRelEnd: z.number().optional(),
    overrides: z.record(z.string(), z.number()).optional(),
  })
  .refine(
    (overlay) =>
      (overlay.start !== undefined) !== (overlay.startRelEnd !== undefined),
    'Give an overlay either `start` or `startRelEnd`, not both and not neither',
  )
  .refine(
    (overlay) => (overlay.end !== undefined) !== (overlay.endRelEnd !== undefined),
    'Give an overlay either `end` or `endRelEnd`, not both and not neither',
  );

export const briefSchema = z.object({
  video_id: z.string().min(1),
  variant_tag: z
    .string()
    .regex(VARIANT_TAG, '§5.6: variant_tag must match fu-<story>-<bot>-<deck>-<hook>[-r<n>]'),

  /**
   * §1.13. One sentence, seven words maximum, stating the single thing the video claims.
   * "Da ChatGPT a flashcard pronte" is valid; "Presentazione dell'app" is not — the second
   * one names a subject instead of making a claim, and nothing can be cut against it.
   */
  promise: z
    .string()
    .min(1)
    .refine(
      (text) => text.trim().split(/\s+/).length <= 7,
      '§1.13: the promise is seven words maximum',
    ),

  /** §1.9. Filled before any segment is timed; the schema's order enforces the workflow. */
  music: z.object({
    src: z.string().min(1),
    bpm: z.number().gt(0),
    offset: z.number().min(0),
    snap: z.boolean(),
  }),

  /**
   * §1.13. One line per shot, in prose, before any JSON. Tension → transformation →
   * resolution, not a list of features.
   */
  storyboard: z
    .array(z.string().min(1))
    .min(2, '§1.13: a storyboard needs at least a tension and a resolution'),

  segments: z.array(segmentSchema).min(1),
  overlays: z.array(overlaySchema),

  endcard: z.object({
    still: z.string().min(1),
    duration: z.number().min(2.5).max(3.0),
  }),
});

export type Brief = z.infer<typeof briefSchema>;
export type Segment = z.infer<typeof segmentSchema>;
export type Overlay = z.infer<typeof overlaySchema>;
