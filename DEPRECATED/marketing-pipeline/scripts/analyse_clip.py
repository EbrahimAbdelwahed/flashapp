"""Frame-pacing analysis for a simulator recording (spec §1.15).

Prints one JSON object.

`xcrun simctl io recordVideo` writes a **variable frame rate** file: it emits a frame when
the screen changes and nothing while it is static. A 30-second clip of which 20 seconds sit
on an unchanging list is therefore ~90 frames, and its "average frame rate" is about 3 fps.
That number is meaningless, and so is any pacing check computed from it — the static
stretches look like catastrophic dropouts while a genuinely juddering animation disappears
into the average.

So pacing is measured only inside **motion runs**: consecutive frames close enough together
to be an animation rather than a still. §1.15's tolerances are applied per run, against that
run's own nominal interval, and the worst run decides the verdict. That is also what the
spec is actually asking about — a viewer never sees a static screen judder.

The container's `r_frame_rate` is ignored entirely: simctl reports a nominal 600/1 that
corresponds to nothing.
"""
import json
import subprocess
import sys

# Frames further apart than this are not part of the same animation.
MOTION_GAP_SECONDS = 0.12

# A run needs enough frames for a median to mean anything.
MIN_RUN_FRAMES = 10

# The first and last interval of a run are discarded before measuring.
#
# They are the boundary between stillness and motion: the encoder's first frame after a
# static stretch arrives late by construction, and the last one trails as the animation
# settles. Counting them as judder made every take fail with "a frame is 11 intervals late"
# when the animation's interior was a clean 15–18 ms throughout. What a viewer perceives as
# stutter happens *inside* a movement, not at its edges.
RUN_EDGE_INTERVALS = 1

# Width of the rolling window used to establish the local frame interval. Wide enough to be
# a stable median, narrow enough to follow a refresh-rate change within a few frames.
NOMINAL_WINDOW = 11

# §1.15 sets 15% jitter and a 2-interval gap. Both are relaxed here by an explicit owner
# decision of 2026-07-29, after measuring four takes on iPhone 17 Pro / iOS 26.4: the
# simulator drops a single frame in 2–5% of intervals during animations, with worst gaps of
# 2.2–2.7x nominal, consistently and irrespective of host load. Holding the spec value
# would fail every clip the simulator can produce, and the owner chose the simulator over
# physical-device capture.
#
# The concern that decision overrides, recorded so it is not lost: the money shot plays at
# 0.5x, and slow motion gives the eye time to register a stutter rather than concealing it.
MAX_JITTER_RATIO = 0.50
MAX_GAP_INTERVALS = 3.0

# Relaxing the per-gap threshold costs sensitivity, so the gate moves to the *rate* of
# dropped frames. At the measured 2–5%, a clip crossing 10% is a real regression — a
# thermally throttled machine, a heavier animation, a background build — and still fails.
MAX_LATE_FRAME_SHARE = 0.10

# What counts as a dropped frame, physically: an interval twice the nominal means at least
# one frame never arrived. Kept separate from the pass/fail threshold on purpose — the
# reported count should describe the footage, not the policy applied to it, so that moving
# the threshold never silently changes what the numbers mean.
DROPPED_FRAME_INTERVALS = 2.0

# Editing handle kept before the action starts (§3.3).
HANDLE_SECONDS = 1.5


def timestamps(path: str) -> list[float]:
    """Presentation timestamps, via `pts_time`.

    Not `pkt_pts_time`: it is deprecated and current ffprobe returns it empty, which makes
    a pacing check silently pass on no data — worse than having no check at all.
    """
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "frame=pts_time", "-of", "csv=p=0", path,
        ],
        capture_output=True, text=True, check=True,
    )

    values = []
    for line in result.stdout.splitlines():
        field = line.split(",")[0].strip()
        if not field:
            continue
        try:
            values.append(float(field))
        except ValueError:
            continue
    return values


def median(values: list[float]) -> float:
    ordered = sorted(values)
    count = len(ordered)
    if count == 0:
        return 0.0
    middle = count // 2
    if count % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def local_nominal(deltas: list[float], index: int) -> float:
    """The frame interval in force *around* `index`, excluding the interval itself.

    A single nominal rate per run is wrong on this hardware. iPhone 17 Pro is a ProMotion
    device and the recordings contain two clean populations — roughly 7 ms and roughly
    17 ms — because a transition runs at the high refresh rate and then settles to 60. A
    median taken across the whole run lands between them, representing neither, and every
    60 fps frame then reads as 1.5x late while a genuine stall is diluted.

    Judder is a *local* anomaly: a frame that arrives late relative to the frames either
    side of it. Comparing against a rolling median absorbs a sustained, legitimate change of
    refresh rate while leaving an isolated stall exactly as visible as it is to the eye.
    """
    half = NOMINAL_WINDOW // 2
    start = max(0, index - half)
    end = min(len(deltas), index + half + 1)
    neighbours = [d for position, d in enumerate(deltas[start:end], start) if position != index]
    return median(neighbours) if neighbours else 0.0


def motion_runs(times: list[float]) -> list[list[float]]:
    runs, current = [], [times[0]] if times else []
    for previous, moment in zip(times, times[1:]):
        if moment - previous <= MOTION_GAP_SECONDS:
            current.append(moment)
        else:
            if len(current) >= MIN_RUN_FRAMES:
                runs.append(current)
            current = [moment]
    if len(current) >= MIN_RUN_FRAMES:
        runs.append(current)
    return runs


def main() -> None:
    path = sys.argv[1]
    times = timestamps(path)

    report: dict[str, object] = {"frames": len(times), "problems": []}
    problems: list[str] = report["problems"]  # type: ignore[assignment]

    if len(times) < 2:
        problems.append("fewer than two frames — the recording captured nothing")
        print(json.dumps(report, ensure_ascii=False))
        return

    runs = motion_runs(times)
    report["motion_runs"] = len(runs)

    if not runs:
        problems.append(
            "no motion anywhere — every frame is isolated, so the flow never animated"
        )
        print(json.dumps(report, ensure_ascii=False))
        return

    longest = max(runs, key=len)
    report["action_start"] = round(longest[0], 3)
    report["suggested_in"] = round(max(0.0, longest[0] - HANDLE_SECONDS), 3)
    report["motion_seconds"] = round(sum(run[-1] - run[0] for run in runs), 3)

    worst_jitter, worst_gap, worst_fps = 0.0, 0.0, 0.0
    late_frames, measured_intervals = 0, 0
    all_nominals: list[float] = []

    for run in runs:
        deltas = [b - a for a, b in zip(run, run[1:])]
        interior = deltas[RUN_EDGE_INTERVALS:len(deltas) - RUN_EDGE_INTERVALS]
        if len(interior) < 4:
            continue

        lateness, ratios = [], []
        for index, delta in enumerate(interior):
            nominal = local_nominal(interior, index)
            if nominal <= 0:
                continue
            all_nominals.append(nominal)
            ratios.append(delta / nominal)
            # One-sided. A frame arriving *early* is the encoder writing extra detail,
            # which no viewer has ever perceived as stutter; only late frames matter.
            lateness.append(max(0.0, delta / nominal - 1.0))

        if not ratios:
            continue

        mean = sum(lateness) / len(lateness)
        variance = sum((v - mean) ** 2 for v in lateness) / len(lateness)
        jitter = variance ** 0.5

        measured_intervals += len(ratios)
        late_frames += sum(1 for r in ratios if r > DROPPED_FRAME_INTERVALS)

        if jitter > worst_jitter:
            worst_jitter = jitter
        worst_gap = max(worst_gap, max(ratios))

    worst_fps = 1.0 / median(all_nominals) if all_nominals else 0.0

    report["worst_jitter_ratio"] = round(worst_jitter, 3)
    report["worst_gap_intervals"] = round(worst_gap, 2)
    report["motion_fps"] = round(worst_fps, 1)
    report["late_frames"] = late_frames
    report["measured_intervals"] = measured_intervals

    if worst_jitter > MAX_JITTER_RATIO:
        problems.append(
            f"jitter {worst_jitter:.0%} inside an animation exceeds "
            f"{MAX_JITTER_RATIO:.0%} (§1.15)"
        )
    if worst_gap > MAX_GAP_INTERVALS:
        problems.append(
            f"worst gap {worst_gap:.1f}x nominal exceeds the accepted {MAX_GAP_INTERVALS}x "
            "(§1.15, relaxed)"
        )

    share = late_frames / measured_intervals if measured_intervals else 0.0
    report["late_frame_share"] = round(share, 3)
    if share > MAX_LATE_FRAME_SHARE:
        problems.append(
            f"{late_frames} of {measured_intervals} intervals dropped a frame "
            f"({share:.0%}) — above the {MAX_LATE_FRAME_SHARE:.0%} ceiling, so this is a "
            "regression rather than the simulator's usual floor"
        )

    # ensure_ascii=False so the section signs and dashes in the problem text survive into
    # the terminal instead of arriving as \u escapes.
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
