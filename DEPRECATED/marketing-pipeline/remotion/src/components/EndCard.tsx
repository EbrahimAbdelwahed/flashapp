/**
 * End card — spec §1.10. An animated composition, not a PNG with a fade.
 *
 * The background keeps moving underneath: blooms and grain never freeze, because a frozen
 * canvas is exactly the static end card §1.1 lists as a failure state. It ends on a cut,
 * not a fade to black.
 */
import React from 'react';
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { fontFamily, safeArea, typography } from '../theme';
import { EASE_OUT, springs } from '../motion';

export const EndCard: React.FC<{ headline: string; cta: string }> = ({ headline, cta }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Overdamped, no overshoot: the wordmark arrives and settles, it does not bounce.
  const wordmark = spring({ frame, fps, config: springs.wordmark, durationInFrames: 20 });

  // The CTA is allowed a little overshoot, and lands after the wordmark has settled.
  const ctaSpring = spring({
    frame: frame - springs.ctaDelayInFrames,
    fps,
    config: springs.cta,
  });

  const translate = interpolate(wordmark, [0, 1], [20, 0], { easing: EASE_OUT });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        paddingLeft: safeArea.left,
        paddingRight: 1080 - safeArea.right,
      }}
    >
      <div
        style={{
          fontFamily,
          fontSize: typography.endcard_h.fontSize,
          fontWeight: typography.endcard_h.fontWeight,
          letterSpacing: typography.endcard_h.letterSpacing,
          lineHeight: typography.endcard_h.lineHeight,
          color: typography.endcard_h.color,
          textAlign: 'center',
          opacity: wordmark,
          transform: `translateY(${translate}px)`,
        }}
      >
        {headline}
      </div>

      <div
        style={{
          marginTop: 48,
          fontFamily,
          fontSize: typography.endcard_c.fontSize,
          fontWeight: typography.endcard_c.fontWeight,
          letterSpacing: typography.endcard_c.letterSpacing,
          lineHeight: typography.endcard_c.lineHeight,
          color: typography.endcard_c.color,
          textAlign: 'center',
          opacity: Math.min(1, ctaSpring),
          transform: `scale(${0.96 + ctaSpring * 0.04})`,
        }}
      >
        {cta}
      </div>
    </AbsoluteFill>
  );
};
