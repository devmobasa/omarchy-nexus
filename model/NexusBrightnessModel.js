// Brightness for the Controls page, delegated to Omarchy's own CLI (which
// dispatches per display: DDC for externals, backlight for internals).
// Loaded by both QML and the Node test harness; dependency-free.
//
// Read path: `omarchy-monitor-state` — 8 newline-separated fields, [0] is
// the focused monitor's brightness percent ("" or "unavailable" when the
// display cannot be controlled), [5] the focused monitor name. Set path:
// `omarchy-brightness-display --no-osd --monitor <name> <pct>%`. Never
// re-read right after a set: it races the hardware and can bounce to zero.

var MIN_PERCENT = 1
var MAX_PERCENT = 100
var POLL_INTERVAL_MS = 5000
var DRAG_DEBOUNCE_MS = 180
var STEP_PERCENT = 5

function clampBrightness(value) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return MIN_PERCENT
  return Math.min(MAX_PERCENT, Math.max(MIN_PERCENT, n))
}

function stateCommand() {
  return ["omarchy-monitor-state"]
}

var MONITOR_RE = /^[A-Za-z0-9-]{1,32}$/

function setCommand(monitor, percent) {
  var name = String(monitor == null ? "" : monitor)
  if (!MONITOR_RE.test(name)) return []
  return ["omarchy-brightness-display", "--no-osd", "--monitor", name,
    clampBrightness(percent) + "%"]
}

// {available, percent, monitor} from the state output; malformed input is
// an unavailable row, never an error.
function parseMonitorState(text) {
  var lines = String(text == null ? "" : text).split("\n")
  var raw = (lines[0] || "").trim()
  var monitor = (lines[5] || "").trim()
  var percent = Number(raw)
  var available = raw !== "" && raw !== "unavailable" && isFinite(percent)
  return {
    available: available && MONITOR_RE.test(monitor),
    percent: available ? clampBrightness(percent) : 0,
    monitor: MONITOR_RE.test(monitor) ? monitor : ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    MIN_PERCENT: MIN_PERCENT,
    MAX_PERCENT: MAX_PERCENT,
    POLL_INTERVAL_MS: POLL_INTERVAL_MS,
    DRAG_DEBOUNCE_MS: DRAG_DEBOUNCE_MS,
    STEP_PERCENT: STEP_PERCENT,
    clampBrightness: clampBrightness,
    stateCommand: stateCommand,
    setCommand: setCommand,
    parseMonitorState: parseMonitorState
  }
}
