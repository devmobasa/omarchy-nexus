// Cava visualizer model for Omarchy Nexus. Loaded by both the QML adapter
// and the Node test harness, so it must stay dependency-free.
//
// cava runs with raw ascii output: every frame is one line of
// semicolon-delimited ints (a trailing delimiter before the newline),
// scaled 0..ascii_max_range. cava may not be installed — the caller treats
// a start failure as "absent" and hides the strip.

var BAR_COUNT = 24
var MAX_RANGE = 100

function buildConfig() {
  return [
    "[general]",
    "bars = " + BAR_COUNT,
    "framerate = 30",
    "sleep_timer = 3",
    "",
    "[output]",
    "method = raw",
    "data_format = ascii",
    "ascii_max_range = " + MAX_RANGE,
    "bar_delimiter = 59",
    "frame_delimiter = 10",
    "channels = mono",
    "mono_option = average",
    ""
  ].join("\n")
}

function confPath(stateDir) {
  return String(stateDir == null ? "" : stateDir) + "/nexus-cava.conf"
}

function cavaCommand(configPath) {
  return ["cava", "-p", configPath]
}

// One frame line -> BAR_COUNT values in 0..1, or null when malformed.
function parseFrame(line) {
  var parts = String(line == null ? "" : line).split(";")
  var values = []
  for (var i = 0; i < parts.length && values.length < BAR_COUNT; i++) {
    var token = parts[i].trim()
    if (token.length === 0) continue
    var value = Number(token)
    if (!isFinite(value)) return null
    values.push(Math.min(1, Math.max(0, value / MAX_RANGE)))
  }
  return values.length === BAR_COUNT ? values : null
}

function silentFrame() {
  var values = []
  for (var i = 0; i < BAR_COUNT; i++) values.push(0)
  return values
}

if (typeof module !== "undefined") {
  module.exports = {
    BAR_COUNT: BAR_COUNT,
    MAX_RANGE: MAX_RANGE,
    buildConfig: buildConfig,
    confPath: confPath,
    cavaCommand: cavaCommand,
    parseFrame: parseFrame,
    silentFrame: silentFrame
  }
}
