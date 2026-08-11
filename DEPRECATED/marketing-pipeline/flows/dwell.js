// A deliberate pause, in milliseconds, passed as MS.
//
// Maestro has no `sleep` command, and `waitForAnimationToEnd` returns immediately on a
// static screen — so neither can produce the human pacing spec §3.4 asks for (300–700 ms
// between taps, ~2 s on the final screen). The point is not to wait for the app; the app
// is already ready. The point is that a flow which fires taps as fast as the driver allows
// records as a machine operating a phone, and no amount of speed ramping in the edit puts
// the humanity back.
//
// A busy loop rather than a timer because the scripting engine exposes no scheduler. The
// durations involved are under two seconds.
var milliseconds = parseInt(typeof MS === 'undefined' ? '500' : MS, 10);
var until = Date.now() + milliseconds;
while (Date.now() < until) {
  // intentionally empty
}
