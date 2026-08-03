// Cava visualizer model for Omarchy Nexus. Loaded by both the QML adapter
// and the Node test harness, so it must stay dependency-free.
//
// cava runs with the config fed over stdin (`-p /dev/stdin`, EOF starts
// the stream) — no config file on disk. Raw ascii output: every frame is
// one line of semicolon-delimited ints (a trailing delimiter before the
// newline), scaled 0..ascii_max_range. The worker lifecycle is an explicit
// state machine whose transitions live here as pure functions.

var BAR_COUNT = 24
var MAX_RANGE = 100
// SplitParser has no internal cap; frames longer than this are dropped
// before parsing.
var MAX_LINE_LENGTH = 4096

// Worker lifecycle states. "failed" is terminal for the session once the
// retry budget is spent; resetSession() clears it on close.
var STATES = {
  INACTIVE: "inactive",
  STARTING: "starting",
  RUNNING: "running",
  FAILED: "failed",
  UNAVAILABLE: "unavailable"
}

var MAX_RETRIES = 3

// Exponential backoff after a crash: 500 ms, 1 s, then the budget is
// spent. Returns -1 when no retry is allowed.
function retryDelay(failureCount) {
  var n = Math.floor(Number(failureCount))
  if (!isFinite(n) || n < 1) n = 1
  if (n >= MAX_RETRIES) return -1
  return Math.min(8000, 500 * Math.pow(2, n - 1))
}

function buildConfig() {
  return [
    "[general]",
    "bars = " + BAR_COUNT,
    "framerate = 30",
    // We gate on isPlaying ourselves; cava idling on silence would freeze
    // the strip with no signal to the worker owner.
    "sleep_timer = 0",
    "autosens = 1",
    "",
    "[input]",
    "method = pipewire",
    "source = auto",
    "",
    "[output]",
    "method = raw",
    "raw_target = /dev/stdout",
    "data_format = ascii",
    "ascii_max_range = " + MAX_RANGE,
    "bar_delimiter = 59",
    "frame_delimiter = 10",
    "channels = mono",
    "mono_option = average",
    "",
    "[smoothing]",
    "monstercat = 0",
    "waves = 0",
    "noise_reduction = 20",
    ""
  ].join("\n")
}

function cavaCommand() {
  return ["cava", "-p", "/dev/stdin"]
}

// One frame line -> BAR_COUNT values in 0..1, or null when malformed.
// Strict: the config pins delimiters and mono, so exactly BAR_COUNT
// fields arrive; anything else is rejected rather than zero-filled.
function parseFrame(line) {
  var text = String(line == null ? "" : line)
  if (text.length === 0 || text.length > MAX_LINE_LENGTH) return null
  var parts = text.split(";")
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
    MAX_LINE_LENGTH: MAX_LINE_LENGTH,
    STATES: STATES,
    MAX_RETRIES: MAX_RETRIES,
    retryDelay: retryDelay,
    buildConfig: buildConfig,
    cavaCommand: cavaCommand,
    parseFrame: parseFrame,
    silentFrame: silentFrame
  }
}
