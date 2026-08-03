// Shell-log self-diagnostics for the Alerts page. Loaded by both QML and
// the Node test harness; dependency-free.
//
// The running Quickshell instance mirrors its default-rule log to
// $XDG_RUNTIME_DIR/quickshell/by-id/<instanceId>/log.log (plain text, no
// ANSI). Reading it with tail is ~600x cheaper than `qs log` (which scans
// the whole binary log), never mixes error text into stdout, and loses
// nothing relative to the qs command's default output.

var TAIL_LINES = 400
var MAX_ROWS = 8
var MAX_ROW_LENGTH = 240
var CONFIG_LOADED_MARKER = "Configuration Loaded"

// The QML failure classes worth surfacing; case-insensitive.
var ERROR_RE = /binding loop|referenceerror|typeerror|failed to load|error loading|could not resolve type|is not a type|cannot assign/i
// Lines that could carry secrets are dropped whole, never truncated in.
var SENSITIVE_RE = /authorization|cookie|credential|password|secret|ssid|token/i

function logPath(runtimeDir, instanceId) {
  var dir = String(runtimeDir == null ? "" : runtimeDir)
  var id = String(instanceId == null ? "" : instanceId)
  if (dir.length === 0 || id.length === 0) return ""
  if (!/^[A-Za-z0-9._-]+$/.test(id)) return ""
  return dir + "/quickshell/by-id/" + id + "/log.log"
}

function tailCommand(path) {
  if (typeof path !== "string" || path.charAt(0) !== "/") return []
  return ["tail", "-n", String(TAIL_LINES), path]
}

// ~ for any /home/<user> (no lookbehind — the QML JS engine may lack it).
function redactHomePaths(text) {
  return String(text == null ? "" : text)
    .replace(/(^|[^A-Za-z0-9._-])\/home\/[^/\s]+/g, "$1~")
}

function collapse(text, limit) {
  var flat = String(text == null ? "" : text).replace(/\s+/g, " ").trim()
  return flat.length <= limit ? flat : flat.slice(0, limit - 1) + "…"
}

// Scan the tailed log: keep only lines after the LAST configuration load
// (errors resolved by a reload must not linger), keep error lines that
// carry no sensitive vocabulary, redact home paths, cap row length and
// count (newest last).
function scanLog(text) {
  var lines = String(text == null ? "" : text).split("\n")
  var start = 0
  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].indexOf(CONFIG_LOADED_MARKER) !== -1) {
      start = i + 1
      break
    }
  }
  var rows = []
  for (var j = start; j < lines.length; j++) {
    var line = lines[j]
    if (!ERROR_RE.test(line)) continue
    if (SENSITIVE_RE.test(line)) continue
    rows.push(collapse(redactHomePaths(line), MAX_ROW_LENGTH))
  }
  return rows.slice(-MAX_ROWS)
}

if (typeof module !== "undefined") {
  module.exports = {
    TAIL_LINES: TAIL_LINES,
    MAX_ROWS: MAX_ROWS,
    MAX_ROW_LENGTH: MAX_ROW_LENGTH,
    CONFIG_LOADED_MARKER: CONFIG_LOADED_MARKER,
    ERROR_RE: ERROR_RE,
    SENSITIVE_RE: SENSITIVE_RE,
    logPath: logPath,
    tailCommand: tailCommand,
    redactHomePaths: redactHomePaths,
    collapse: collapse,
    scanLog: scanLog
  }
}
