/**
 * Brief JSON -> timeline. Spec §4.2.
 *
 * Segment durations are derived from the speed ramps rather than declared, because the
 * ramp is what actually decides how long a shot lasts (§1.7). The brief says "3x across the
 * navigation, decelerating to 1x over the payoff"; how many seconds that occupies is the
 * integral of that curve, computed in brief/timeline.ts.
 */
import React from 'react';
import { AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { Canvas } from './components/Canvas';
import { Device } from './components/Device';
import { EndCard } from './components/EndCard';
import { Overlay } from './components/Overlay';
import type { Brief, Segment } from './brief/schema';
import { compositionDuration, sourceTimeAt } from './brief/timeline';

/** Recording dimensions. Read from the file by calculateMetadata and passed in. */
export type SourceSize = { width: number; height: number };

export const MarketingVideo: React.FC<{ brief: Brief; sources: Record<string, SourceSize> }> = ({
  brief,
  sources,
}) => {
  const { fps } = useVideoConfig();

  let cursor = 0;
  const placed = brief.segments.map((segment) => {
    const start = cursor;
    const seconds = compositionDuration(segment);
    cursor += seconds;
    return { segment, startInFrames: Math.round(start * fps), durationInFrames: Math.round(seconds * fps) };
  });

  const filmEnd = cursor;
  const total = filmEnd + brief.endcard.duration;

  return (
    <Canvas>
      {placed.map(({ segment, startInFrames, durationInFrames }, index) => (
        <Sequence key={index} from={startInFrames} durationInFrames={durationInFrames}>
          <SegmentLayer segment={segment} durationInFrames={durationInFrames} sources={sources} />
        </Sequence>
      ))}

      <Sequence from={Math.round(filmEnd * fps)} durationInFrames={Math.round(brief.endcard.duration * fps)}>
        <EndCard
          headline={brief.promise}
          cta="Link in bio → lista d'attesa. Ti mando il link App Store al lancio."
        />
      </Sequence>

      {brief.overlays.map((overlay, index) => {
        const start = overlay.start ?? total + (overlay.startRelEnd ?? 0);
        const end = overlay.end ?? total + (overlay.endRelEnd ?? 0);
        return (
          <Sequence
            key={index}
            from={Math.round(start * fps)}
            durationInFrames={Math.max(1, Math.round((end - start) * fps))}
          >
            <Overlay
              text={overlay.text}
              style={overlay.style}
              anchor={overlay.anchor}
              durationInFrames={Math.max(1, Math.round((end - start) * fps))}
            />
          </Sequence>
        );
      })}

      <Audio src={staticFile(brief.music.src.replace(/^assets\/audio\//, 'audio/'))} volume={0.55} />
    </Canvas>
  );
};

/**
 * One shot.
 *
 * The composition frame is converted to a source time through the integral of the segment's
 * rate curve. `playbackRate` is handed the *instantaneous* rate purely as a decoder hint —
 * Remotion evaluates every frame independently, so letting it drive the seek would apply
 * the ramp a second time on top of the remapping.
 */
const SegmentLayer: React.FC<{
  segment: Segment;
  durationInFrames: number;
  sources: Record<string, SourceSize>;
}> = ({ segment, durationInFrames, sources }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const size = sources[segment.src] ?? { width: 1206, height: 2622 };
  const sourceTime = sourceTimeAt(segment, frame / fps);
  const rate = instantaneousRate(segment, sourceTime - segment.in);

  return (
    <AbsoluteFill>
      <Device
        src={staticFile(`clips/anatomia/${segment.src}.mp4`)}
        sourceWidth={size.width}
        sourceHeight={size.height}
        sourceTime={sourceTime}
        fps={fps}
        playbackRate={rate}
        direction={segment.push}
        durationInFrames={durationInFrames}
      />
    </AbsoluteFill>
  );
};

/** Linear interpolation of the declared rate curve at a source offset. */
const instantaneousRate = (segment: Segment, offset: number): number => {
  const points = segment.ramp;
  if (offset <= points[0].at) return points[0].rate;

  for (let index = 0; index < points.length - 1; index += 1) {
    const from = points[index];
    const to = points[index + 1];
    if (offset <= to.at) {
      const span = to.at - from.at;
      if (span <= 0) return to.rate;
      return from.rate + ((to.rate - from.rate) * (offset - from.at)) / span;
    }
  }

  return points[points.length - 1].rate;
};
