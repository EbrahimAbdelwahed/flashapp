/**
 * The frame around the screen — spec §1.5, items 4 and 5.
 *
 * An iPhone records about 19.5:9, taller than 9:16, so there is always canvas around the
 * device. What goes there is the film. Two heavily blurred radial blooms over an ink base,
 * a vignette, and animated grain on top of everything except text.
 *
 * The grain is not decoration. It kills the banding that large radial gradients produce in
 * an 8-bit H.264 encode, and §1.5 calls it the cheapest single upgrade in the pipeline.
 */
import React from 'react';
import { AbsoluteFill, random, useCurrentFrame } from 'remotion';
import { theme } from '../theme';

const BLOOM_RADIUS = 900;
const BLOOM_BLUR = 180;

export const Canvas: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  return (
    <AbsoluteFill style={{ backgroundColor: theme.ink800 }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(${BLOOM_RADIUS}px circle at 28% 22%, ${theme.ink600} 0%, transparent 70%)`,
          filter: `blur(${BLOOM_BLUR}px)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(${BLOOM_RADIUS}px circle at 78% 82%, ${theme.ember700} 0%, transparent 70%)`,
          filter: `blur(${BLOOM_BLUR}px)`,
        }}
      />

      {children}

      <AbsoluteFill
        style={{
          background: 'radial-gradient(circle at 50% 50%, rgba(0,0,0,0) 45%, rgba(0,0,0,0.35) 100%)',
          pointerEvents: 'none',
        }}
      />

      <Grain />
    </AbsoluteFill>
  );
};

/**
 * Animated monochrome noise.
 *
 * Drawn as a repeating SVG turbulence rather than a canvas or an image sequence, so it
 * costs nothing to render and needs no asset. The seed advances with the frame, which is
 * what makes it read as film grain instead of a static dirty overlay.
 *
 * `isolation: isolate` on the wrapper is deliberate: the research notes flag
 * `mix-blend-mode` as unverified under Remotion's headless rasteriser, where an element
 * that gets its own compositing layer can silently stop blending. An explicit isolation
 * group is the documented mitigation.
 */
const Grain: React.FC = () => {
  const frame = useCurrentFrame();
  const seed = Math.floor(random(`grain-${Math.floor(frame / 2)}`) * 1000);

  return (
    <AbsoluteFill style={{ isolation: 'isolate', pointerEvents: 'none' }}>
      <AbsoluteFill
        style={{
          opacity: 0.04,
          mixBlendMode: 'overlay',
          backgroundImage: `url("data:image/svg+xml;utf8,${encodeURIComponent(
            `<svg xmlns='http://www.w3.org/2000/svg' width='300' height='300'>
               <filter id='n'>
                 <feTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' seed='${seed}'/>
                 <feColorMatrix type='saturate' values='0'/>
               </filter>
               <rect width='300' height='300' filter='url(#n)'/>
             </svg>`,
          )}")`,
          backgroundRepeat: 'repeat',
        }}
      />
    </AbsoluteFill>
  );
};
