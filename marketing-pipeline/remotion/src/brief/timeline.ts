/**
 * Turns a brief's declared speed ramps into real durations.
 *
 * §1.7 requires speed ramps rather than a constant rate, and §4.1 established that
 * `playbackRate` in Remotion 4.0.500 is a single `number` — it cannot vary over time. So a
 * ramp is realised by remapping composition frames onto source frames, and that remapping
 * is the integral of the rate curve. Everything downstream — segment length, where an
 * overlay lands, whether the film fits inside 28 seconds — depends on getting this
 * integral right, so it lives in one place with its own tests.
 */
import type { Segment } from './schema';

type RampPoint = { at: number; rate: number };

/**
 * Composition seconds elapsed while playing `sourceSeconds` of source at a rate that
 * varies linearly between ramp points.
 *
 * For a linear rate r(t) = r0 + m·t, the time spent is ∫dt/r(t), which closes to
 * ln(r1/r0)/m — not (t1-t0) divided by the average rate, which is the intuitive and wrong
 * answer. At 3× decelerating to 1× the two differ by about 10%, enough to walk an overlay
 * off its beat.
 */
export const compositionDuration = (segment: Segment): number => {
  const sourceLength = segment.out - segment.in;
  if (sourceLength <= 0) return 0;

  const points = normalisedRamp(segment.ramp, sourceLength);
  let elapsed = 0;

  for (let index = 0; index < points.length - 1; index += 1) {
    const from = points[index];
    const to = points[index + 1];
    const span = to.at - from.at;
    if (span <= 0) continue;

    if (Math.abs(to.rate - from.rate) < 1e-9) {
      elapsed += span / from.rate;
    } else {
      const slope = (to.rate - from.rate) / span;
      elapsed += Math.log(to.rate / from.rate) / slope;
    }
  }

  return elapsed;
};

/**
 * Source time corresponding to a composition time inside the segment.
 *
 * The inverse of the above, solved segment by segment. Used by the renderer to pick which
 * source frame to show, and by the tap compositor to place a ripple at the moment the tap
 * actually happened rather than where the un-ramped timeline would put it.
 */
export const sourceTimeAt = (segment: Segment, compositionSeconds: number): number => {
  const sourceLength = segment.out - segment.in;
  const points = normalisedRamp(segment.ramp, sourceLength);
  let elapsed = 0;

  for (let index = 0; index < points.length - 1; index += 1) {
    const from = points[index];
    const to = points[index + 1];
    const span = to.at - from.at;
    if (span <= 0) continue;

    const isConstant = Math.abs(to.rate - from.rate) < 1e-9;
    const slope = isConstant ? 0 : (to.rate - from.rate) / span;
    const sliceDuration = isConstant
      ? span / from.rate
      : Math.log(to.rate / from.rate) / slope;

    if (compositionSeconds <= elapsed + sliceDuration) {
      const within = compositionSeconds - elapsed;
      const offset = isConstant
        ? within * from.rate
        : (from.rate * (Math.exp(slope * within) - 1)) / slope;
      return segment.in + from.at + offset;
    }

    elapsed += sliceDuration;
  }

  return segment.out;
};

/** Total composition length of the film, end card included. */
export const briefDuration = (segments: Segment[], endcardDuration: number): number =>
  segments.reduce((total, segment) => total + compositionDuration(segment), 0) + endcardDuration;

/**
 * Clamps the declared ramp to the segment and closes it at both ends.
 *
 * A brief may declare a ramp that starts after zero or stops before the end; the rate then
 * holds flat outward, which is what an editor means by "3× across the navigation, then 1×".
 */
const normalisedRamp = (ramp: RampPoint[], sourceLength: number): RampPoint[] => {
  const inside = ramp.filter((point) => point.at < sourceLength);
  const points = inside.length > 0 ? [...inside] : [{ at: 0, rate: ramp[0].rate }];

  if (points[0].at > 0) {
    points.unshift({ at: 0, rate: points[0].rate });
  }

  const last = points[points.length - 1];
  if (last.at < sourceLength) {
    points.push({ at: sourceLength, rate: last.rate });
  }

  return points;
};
