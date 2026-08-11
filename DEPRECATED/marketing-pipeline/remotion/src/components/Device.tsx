/**
 * The device layer — spec §1.5, items 1 to 3, plus the camera push of §1.6.
 *
 * A floating rounded rectangle, never a photo of a phone: clip, two shadows cast down, and
 * a one-pixel inset hairline that separates screen from background without drawing a frame
 * around it.
 *
 * Geometry comes from the recording's real dimensions, never a constant. §1.4 is explicit
 * that a hardcoded width is how a non-uniform scale creeps in, and distorting the app UI is
 * the one thing the spec forbids outright.
 */
import React from 'react';
import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from 'remotion';
import { Video } from '@remotion/media';
import { deviceRect } from '../theme';
import { EASE_INOUT, cut, push } from '../motion';

/** Points across an iPhone 17 Pro screen, used to scale the corner radius. */
const SOURCE_WIDTH_IN_POINTS = 402;

export const Device: React.FC<{
  src: string;
  sourceWidth: number;
  sourceHeight: number;
  /** Source time to display, in seconds — already speed-remapped by the caller. */
  sourceTime: number;
  fps: number;
  playbackRate: number;
  direction: 'in' | 'out';
  durationInFrames: number;
}> = ({ src, sourceWidth, sourceHeight, sourceTime, fps, playbackRate, direction, durationInFrames }) => {
  const frame = useCurrentFrame();
  const rect = deviceRect(sourceWidth, sourceHeight, SOURCE_WIDTH_IN_POINTS);

  // The push alternates between consecutive segments so the film never feels on rails.
  const [from, to] = direction === 'in' ? [push.from, push.to] : [push.to, push.from];
  const scale = interpolate(frame, [0, durationInFrames], [from, to], {
    easing: EASE_INOUT,
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // A hard cut plus a short settle on the incoming segment. No dissolves between app
  // footage, ever (§1.6).
  const settle = interpolate(frame, [0, cut.settleInFrames], [cut.settleFrom, cut.settleTo], {
    easing: Easing.out(Easing.quad),
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          borderRadius: rect.cornerRadius,
          transform: `scale(${scale * settle})`,
          transformOrigin: 'center center',
          boxShadow: '0 60px 140px rgba(0,0,0,0.55), 0 8px 24px rgba(0,0,0,0.35)',
          overflow: 'hidden',
        }}
      >
        <Video
          src={src}
          // The caller has already integrated the rate curve; this is the exact source
          // moment to show. `trimBefore` seeks by frame, so the conversion happens here.
          trimBefore={Math.max(0, Math.round(sourceTime * fps))}
          // Passed so the decoder and any audio track are hinted at the instantaneous rate.
          // It does not drive the seek position — that would compound the ramp twice over.
          playbackRate={playbackRate}
          style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
        />
        <div
          style={{
            position: 'absolute',
            inset: 0,
            borderRadius: rect.cornerRadius,
            border: '1px solid rgba(255,255,255,0.10)',
            pointerEvents: 'none',
          }}
        />
      </div>
    </AbsoluteFill>
  );
};
