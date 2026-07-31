"""Tempo and first-downbeat estimate from raw mono 16-bit PCM on stdin.

Prints "<bpm> <offset_seconds>".

Deliberately dependency-free — numpy is not installed on the recording machine and a music
analysis library is a large dependency for two numbers. This is not a mastering-grade
analyser: it builds an onset envelope, autocorrelates it over the plausible tempo range,
and reports the first onset that clears a threshold. Both numbers are starting points to be
confirmed against the waveform in Remotion Studio, which is what §1.9 asks for anyway.

Tempo octave is genuinely ambiguous for some material: 70 and 140 BPM produce the same grid
at half resolution, and a half-time groove will often report its half tempo. Halving or
doubling the reported value never breaks the grid — it only changes how many boundaries a
bar offers. Confirm against the waveform before timing anything.
"""
import math
import struct
import sys

SAMPLE_RATE = 8000
HOP = 80  # 10 ms frames
MIN_BPM, MAX_BPM = 40, 200
ONSET_THRESHOLD_RATIO = 3.0

# Raw autocorrelation is biased toward long lags: slow periodicities accumulate more
# correlated low-frequency energy, so an unweighted search reports whatever the slowest
# tempo in range happens to be — move the floor and the answer moves with it. Weighting by
# a log-normal preference around a central tempo is the standard correction, and it is what
# makes the estimate a property of the music rather than of the search window.
PREFERRED_BPM = 120.0
PREFERENCE_WIDTH = 0.9  # in octaves


def main() -> None:
    raw = sys.stdin.buffer.read()
    count = len(raw) // 2
    if count < SAMPLE_RATE:
        print("120.0 0.0")
        return

    samples = struct.unpack(f"<{count}h", raw[: count * 2])

    energy = []
    for start in range(0, count - HOP, HOP):
        total = 0
        for index in range(start, start + HOP):
            value = samples[index]
            total += value * value
        energy.append(math.sqrt(total / HOP))

    flux = [max(0.0, energy[i] - energy[i - 1]) for i in range(1, len(energy))]
    mean = sum(flux) / len(flux)
    centred = [value - mean for value in flux]

    frames_per_second = SAMPLE_RATE / HOP

    best_lag, best_score = 0, -1e18
    for half_bpm in range(MIN_BPM * 2, MAX_BPM * 2 + 1):
        bpm = half_bpm / 2
        lag = int(round(frames_per_second * 60.0 / bpm))
        if lag < 2 or lag >= len(centred):
            continue
        score = sum(centred[i] * centred[i - lag] for i in range(lag, len(centred)))
        score /= len(centred) - lag
        score *= math.exp(
            -0.5 * (math.log2(bpm / PREFERRED_BPM) / PREFERENCE_WIDTH) ** 2
        )
        if score > best_score:
            best_score, best_lag = score, lag

    bpm = frames_per_second * 60.0 / best_lag if best_lag else 120.0

    # First downbeat: earliest onset clearly above the noise floor. Tracks commonly open on
    # silence or a fade, and starting the grid at t=0 puts every cut a fraction of a beat
    # early for the whole film.
    threshold = mean * ONSET_THRESHOLD_RATIO
    offset = 0.0
    for index, value in enumerate(flux):
        if value > threshold:
            offset = index / frames_per_second
            break

    print(f"{bpm:.1f} {offset:.3f}")


if __name__ == "__main__":
    main()
