/**
 * Type on the canvas — spec §1.3, §1.4, §1.6.
 *
 * Entrances are 20 frames with opacity, translate, scale and blur moving together, and
 * multi-line blocks stagger by four frames per line. Exits are shorter, because leaving is
 * not an event.
 *
 * No outlines and no drop shadows, ever: §1.3 solves contrast with a scrim or by moving the
 * text, never with a stroke. Text is anchored strictly inside x 108–972 / y 280–1500.
 */
import React from 'react';
import { interpolate, useCurrentFrame } from 'remotion';
import { fontFamily, safeArea, theme, typography, type TextStyle } from '../theme';
import { EASE_IN, EASE_OUT, textIn, textOut } from '../motion';

export const Overlay: React.FC<{
  text: string;
  style: TextStyle;
  anchor: 'top' | 'center' | 'bottom';
  durationInFrames: number;
}> = ({ text, style, anchor, durationInFrames }) => {
  const frame = useCurrentFrame();
  const scale = typography[style];
  const lines = text.split('\n');
  const isPill = style === 'save_cta';

  const outStart = durationInFrames - textOut.durationInFrames;

  return (
    <div
      style={{
        position: 'absolute',
        left: safeArea.left,
        width: safeArea.contentWidth,
        ...anchorStyle(anchor),
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        pointerEvents: 'none',
      }}
    >
      {/*
        A scrim, only where text sits over the device: a gradient anchored to the text's
        edge, never a solid box behind it (§1.5 item 6). The save CTA carries its own pill
        instead, so it does not get one.
      */}
      {!isPill && anchor !== 'center' ? <Scrim anchor={anchor} /> : null}

      <div style={isPill ? pillStyle : undefined}>
        {lines.map((line, index) => {
          const delay = index * textIn.staggerPerLine;
          const enter = frame - delay;

          const opacity =
            interpolate(enter, [0, textIn.opacityInFrames], [0, 1], {
              easing: EASE_OUT,
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            }) *
            interpolate(frame, [outStart, durationInFrames], [1, 0], {
              easing: EASE_IN,
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            });

          const translateY =
            interpolate(enter, [0, textIn.durationInFrames], [textIn.translateY, 0], {
              easing: EASE_OUT,
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            }) +
            interpolate(frame, [outStart, durationInFrames], [0, textOut.translateY], {
              easing: EASE_IN,
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            });

          const scaleIn = interpolate(enter, [0, textIn.durationInFrames], [textIn.scaleFrom, 1], {
            easing: EASE_OUT,
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          });

          const blur =
            interpolate(enter, [0, textIn.durationInFrames], [textIn.blur, 0], {
              easing: EASE_OUT,
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            }) +
            interpolate(frame, [outStart, durationInFrames], [0, textOut.blur], {
              easing: EASE_IN,
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            });

          return (
            <div
              key={index}
              style={{
                fontFamily,
                fontSize: scale.fontSize,
                fontWeight: scale.fontWeight,
                letterSpacing: scale.letterSpacing,
                lineHeight: scale.lineHeight,
                color: scale.color,
                textAlign: 'center',
                opacity,
                filter: blur > 0.05 ? `blur(${blur}px)` : undefined,
                transform: `translateY(${translateY}px) scale(${scaleIn})`,
              }}
            >
              {line}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const anchorStyle = (anchor: 'top' | 'center' | 'bottom'): React.CSSProperties => {
  switch (anchor) {
    case 'top':
      return { top: safeArea.top };
    case 'center':
      return { top: (safeArea.top + safeArea.bottom) / 2, transform: 'translateY(-50%)' };
    case 'bottom':
      // §1.11 anchors the save CTA at y 1360, comfortably inside the text box.
      return { top: 1360 };
  }
};

const pillStyle: React.CSSProperties = {
  backgroundColor: 'rgba(255,255,255,0.10)',
  borderRadius: 999,
  padding: '18px 32px',
  backdropFilter: 'blur(20px)',
};

const Scrim: React.FC<{ anchor: 'top' | 'bottom' }> = ({ anchor }) => (
  <div
    style={{
      position: 'absolute',
      left: -safeArea.left,
      width: 1080,
      height: 520,
      [anchor === 'top' ? 'top' : 'bottom']: -120,
      background:
        anchor === 'top'
          ? `linear-gradient(to bottom, ${hexToRgba(theme.ink900, 0.75)}, transparent)`
          : `linear-gradient(to top, ${hexToRgba(theme.ink900, 0.75)}, transparent)`,
      pointerEvents: 'none',
    }}
  />
);

const hexToRgba = (hex: string, alpha: number) => {
  const value = parseInt(hex.slice(1), 16);
  return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`;
};
