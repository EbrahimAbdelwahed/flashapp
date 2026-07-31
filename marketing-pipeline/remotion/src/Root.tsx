/**
 * Composition registry.
 *
 * The brief arrives through `--props`; validation runs in `calculateMetadata`, so a brief
 * that breaks §4.3 fails before a single frame is rendered rather than after fifteen
 * minutes of encoding.
 */
import React from 'react';
import { Composition, getStaticFiles, staticFile } from 'remotion';
import { parseMedia } from '@remotion/media-parser';
import { canvas } from './theme';
import { briefSchema, type Brief } from './brief/schema';
import { validateBrief } from './brief/validate';
import { briefDuration } from './brief/timeline';
import { MarketingVideo, type SourceSize } from './Video';
import defaultBrief from '../../briefs/F1.json';

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="MarketingVideo"
      component={MarketingVideo}
      // No `schema` prop: it constrains the composition's props to the schema's own shape,
      // and this component takes the brief alongside the source dimensions read from disk.
      // Validation is not lost — `calculateMetadata` parses and validates before returning,
      // so a brief that breaks §4.3 still fails before the first frame.
      width={canvas.width}
      height={canvas.height}
      fps={canvas.fps}
      durationInFrames={600}
      defaultProps={{ brief: defaultBrief as unknown as Brief, sources: {} }}
      calculateMetadata={async ({ props }) => {
        const brief = briefSchema.parse(props.brief);
        validateBrief(brief);

        // Source dimensions are read from the files, never assumed. §1.4 requires the
        // device rect to be derived from the real recording, and a wrong constant shows up
        // as a non-uniform scale — the one thing the spec forbids outright.
        const sources: Record<string, SourceSize> = {};
        for (const segment of brief.segments) {
          if (sources[segment.src]) continue;
          const { dimensions } = await parseMedia({
            src: staticFile(`clips/anatomia/${segment.src}.mp4`),
            fields: { dimensions: true },
            // Free-licence eligibility was established in docs/REMOTION_NOTES.md §1.
            acknowledgeRemotionLicense: true,
          });
          if (dimensions) {
            sources[segment.src] = { width: dimensions.width, height: dimensions.height };
          }
        }

        const seconds = briefDuration(brief.segments, brief.endcard.duration);
        return {
          durationInFrames: Math.round(seconds * canvas.fps),
          props: { brief, sources },
        };
      }}
    />
  );
};

/** Kept so an empty public/ fails loudly rather than rendering a black film. */
export const assertClipsPresent = () => {
  const files = getStaticFiles();
  if (files.length === 0) {
    throw new Error('public/ is empty — is public/clips still symlinked to ../out/clips?');
  }
};
