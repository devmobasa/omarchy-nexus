// Microphone peak math for the Controls page. Loaded by both QML and the
// Node test harness; dependency-free.
//
// Quickshell's PwNodePeakMonitor reports cbrt(linear sample peak), so the
// cube recovers true amplitude; the meter is then a linear 0..1 map of
// -55..0 dBFS — the floor hides idle electrical noise, full scale is
// clipping.

var NOISE_FLOOR_DB = -55

function peakToMeter(peak) {
  var value = Number(peak == null ? 0 : peak)
  if (!isFinite(value) || value <= 0) return 0
  var amplitude = value * value * value
  var db = 20 * Math.log10(amplitude)
  if (db <= NOISE_FLOOR_DB) return 0
  return Math.min(1, Math.max(0, (db - NOISE_FLOOR_DB) / -NOISE_FLOOR_DB))
}

if (typeof module !== "undefined") {
  module.exports = {
    NOISE_FLOOR_DB: NOISE_FLOOR_DB,
    peakToMeter: peakToMeter
  }
}
