/**
 * Cross-field brief validation — spec §4.3, §1.11, §1.14, §3.7.
 *
 * The schema checks each field in isolation. These are the rules that need the whole
 * timeline in view at once, and they are the ones that actually protect the film: a second
 * save CTA, two overlays on screen together, a hero that never returns, or sync footage
 * without its overlay are all mistakes you cannot see in a JSON file and can see instantly
 * in a render — after fifteen minutes of encoding.
 *
 * Every one of these is a hard failure. None is a warning.
 */
import { safeArea, typography } from '../theme';
import type { Brief, Overlay } from './schema';
import { briefDuration, compositionDuration } from './timeline';

export class BriefInvalid extends Error {
  constructor(public readonly problems: string[]) {
    super(`Brief rejected:\n  · ${problems.join('\n  · ')}`);
    this.name = 'BriefInvalid';
  }
}

type Window = { start: number; end: number };

/** §1.11. Exactly one save CTA per video, and it sits mid-film. */
const SAVE_CTA_MIN_SECONDS = 2.5;
const SAVE_CTA_MAX_SECONDS = 3.5;
const SAVE_CTA_TAIL_EXCLUSION_SECONDS = 5;

/** §1.14. A second hero is allowed only in a long film, and only far from the first. */
const HERO_SECOND_MIN_FILM_SECONDS = 24;
const HERO_MIN_SEPARATION_SECONDS = 8;

/** §3.7. The promise the sync footage is not allowed to make on its own. */
const SYNC_OVERLAY_TEXT = 'Sincronizzazione automatica — inclusa al lancio';

export const validateBrief = (brief: Brief): void => {
  const problems: string[] = [];

  const segmentStarts: number[] = [];
  let cursor = 0;
  for (const segment of brief.segments) {
    segmentStarts.push(cursor);
    cursor += compositionDuration(segment);
  }
  const filmEnd = cursor;
  const total = briefDuration(brief.segments, brief.endcard.duration);

  const windows = brief.overlays.map((overlay) => resolveWindow(overlay, total));

  // §4.3: total duration over 60 s.
  if (total > 60) {
    problems.push(`Total duration ${total.toFixed(1)}s exceeds the 60s hard ceiling (§1.7)`);
  }

  // §4.3: two overlays overlapping in time. One idea on screen at a time (§1.11).
  for (let a = 0; a < windows.length; a += 1) {
    for (let b = a + 1; b < windows.length; b += 1) {
      if (overlaps(windows[a], windows[b])) {
        problems.push(
          `Overlays "${brief.overlays[a].text}" and "${brief.overlays[b].text}" are on screen ` +
            `together (${fmt(windows[a])} vs ${fmt(windows[b])}) — §1.11 allows one at a time`,
        );
      }
    }
  }

  // §4.3: zero or multiple save_cta overlays.
  const saveIndices = brief.overlays
    .map((overlay, index) => (overlay.style === 'save_cta' ? index : -1))
    .filter((index) => index >= 0);

  if (saveIndices.length !== 1) {
    problems.push(
      `Found ${saveIndices.length} save_cta overlays — §1.11 requires exactly one per video`,
    );
  }

  for (const index of saveIndices) {
    const window = windows[index];
    const length = window.end - window.start;

    if (length < SAVE_CTA_MIN_SECONDS || length > SAVE_CTA_MAX_SECONDS) {
      problems.push(
        `save_cta is on screen ${length.toFixed(1)}s — §1.11 wants ` +
          `${SAVE_CTA_MIN_SECONDS}–${SAVE_CTA_MAX_SECONDS}s`,
      );
    }
    if (window.end > total - SAVE_CTA_TAIL_EXCLUSION_SECONDS) {
      problems.push(
        `save_cta ends at ${window.end.toFixed(1)}s, inside the final ` +
          `${SAVE_CTA_TAIL_EXCLUSION_SECONDS}s — §1.11 forbids it`,
      );
    }
    if (window.end > filmEnd) {
      problems.push('save_cta runs into the end card — §1.11 forbids them sharing the screen');
    }
  }

  // §4.3: more than one hero per video, two only under §1.14's conditions.
  const heroTimes = brief.segments
    .map((segment, index) =>
      segment.hero ? segmentStarts[index] + segment.hero.at : undefined,
    )
    .filter((time): time is number => time !== undefined);

  if (heroTimes.length > 2) {
    problems.push(`${heroTimes.length} hero breakouts — §1.14 allows at most two`);
  } else if (heroTimes.length === 2) {
    if (total <= HERO_SECOND_MIN_FILM_SECONDS) {
      problems.push(
        `Two hero breakouts in a ${total.toFixed(1)}s film — §1.14 allows a second only ` +
          `beyond ${HERO_SECOND_MIN_FILM_SECONDS}s`,
      );
    }
    if (Math.abs(heroTimes[1] - heroTimes[0]) < HERO_MIN_SEPARATION_SECONDS) {
      problems.push(
        `Hero breakouts are ${Math.abs(heroTimes[1] - heroTimes[0]).toFixed(1)}s apart — ` +
          `§1.14 requires at least ${HERO_MIN_SEPARATION_SECONDS}s`,
      );
    }
  }

  // §3.7 / §4.3: any clip7_* segment without its sync overlay covering the full segment.
  brief.segments.forEach((segment, index) => {
    if (!segment.src.startsWith('clip7_')) return;

    const start = segmentStarts[index];
    const end = start + compositionDuration(segment);
    const covered = brief.overlays.some((overlay, overlayIndex) => {
      if (!overlay.text.includes(SYNC_OVERLAY_TEXT)) return false;
      const window = windows[overlayIndex];
      return window.start <= start + 1e-6 && window.end >= end - 1e-6;
    });

    if (!covered) {
      problems.push(
        `Segment "${segment.src}" (${start.toFixed(1)}–${end.toFixed(1)}s) has no sync overlay ` +
          'covering its full duration — §3.7 forbids showing the two devices without it',
      );
    }
  });

  // §4.3: any overlay whose rendered bounds fall outside the safe area.
  brief.overlays.forEach((overlay, index) => {
    const problem = boundsProblem(overlay);
    if (problem) problems.push(`Overlay "${overlay.text}" (${index}): ${problem}`);
  });

  if (problems.length > 0) throw new BriefInvalid(problems);
};

const resolveWindow = (overlay: Overlay, total: number): Window => ({
  start: overlay.start ?? total + (overlay.startRelEnd ?? 0),
  end: overlay.end ?? total + (overlay.endRelEnd ?? 0),
});

const overlaps = (a: Window, b: Window): boolean => a.start < b.end && b.start < a.end;

const fmt = (window: Window) => `${window.start.toFixed(1)}–${window.end.toFixed(1)}s`;

/**
 * Checks the block a style can produce at its declared maximum against §1.4's text box.
 *
 * Measuring the real glyph run needs a laid-out DOM, which does not exist at validation
 * time. The style table is the contract instead: a style declares its maximum line count,
 * and if that many lines at that size cannot fit the anchor, no string ever will. Copy
 * shorter than the maximum is checked again at render, where the DOM does exist.
 */
const boundsProblem = (overlay: Overlay): string | undefined => {
  const style = typography[overlay.style];
  const height = style.fontSize * style.lineHeight * style.maxLines;
  const available = safeArea.bottom - safeArea.top;

  if (height > available) {
    return `${style.maxLines} lines at ${style.fontSize}px is ${Math.round(height)}px tall, ` +
      `taller than the ${available}px text box (§1.4)`;
  }

  const words = overlay.text.trim().split(/\s+/).length;
  if (words > style.maxWords) {
    return `${words} words exceeds the ${style.maxWords} the "${overlay.style}" style allows (§1.3)`;
  }

  return undefined;
};
