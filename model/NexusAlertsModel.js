// Failed-systemd-unit model for the Alerts page. Loaded by both QML and
// the Node test harness; dependency-free.
//
// systemctl's JSON output C-escapes unit names (\x2d etc.). The RAW name
// is the only safe argv token: unescaping can collide with a different,
// real unit (a dash is a legal unit-name character), so rows keep both
// forms — `unit` for commands, `display` for the UI.

var SCOPE_SYSTEM = "system"
var SCOPE_USER = "user"

// Unit-name charset per systemd plus the \xNN escape backslash. `--` in
// every command closes option parsing, so a leading dash cannot become a
// flag, but reject it anyway.
var RAW_UNIT_RE = /^[A-Za-z0-9@:._\\-]{1,256}$/

function validUnit(name) {
  var unit = String(name == null ? "" : name)
  if (!RAW_UNIT_RE.test(unit)) return false
  if (unit.charAt(0) === "-") return false
  return unit.indexOf(".") > 0
}

function unescapeUnitName(name) {
  return String(name == null ? "" : name).replace(/\\x([0-9a-fA-F]{2})/g, function (m, hex) {
    return String.fromCharCode(parseInt(hex, 16))
  })
}

function failedCommand(scope) {
  var command = ["systemctl"]
  if (scope === SCOPE_USER) command.push("--user")
  return command.concat(["--failed", "--output=json", "--no-pager"])
}

// restart re-runs the unit; reset-failed just clears the failed state (and
// the start rate-limit counter), which is the "dismiss" verb.
var UNIT_VERBS = ["restart", "reset-failed"]

function unitCommand(verb, scope, unit) {
  if (UNIT_VERBS.indexOf(verb) === -1) return []
  if (scope !== SCOPE_SYSTEM && scope !== SCOPE_USER) return []
  if (!validUnit(unit)) return []
  var command = ["systemctl"]
  if (scope === SCOPE_USER) command.push("--user")
  return command.concat([verb, "--", String(unit)])
}

// systemctl exits 0 with `[]` when nothing failed, so only the JSON shape
// matters. Rows: {unit, display, description, sub, scope}.
function parseFailedUnits(text, scope) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!Array.isArray(parsed)) return []
  var rows = []
  for (var i = 0; i < parsed.length; i++) {
    var entry = parsed[i]
    if (!entry || typeof entry !== "object") continue
    if (typeof entry.unit !== "string" || !validUnit(entry.unit)) continue
    rows.push({
      unit: entry.unit,
      display: unescapeUnitName(entry.unit),
      description: typeof entry.description === "string" ? unescapeUnitName(entry.description) : "",
      sub: typeof entry.sub === "string" ? entry.sub : "",
      scope: scope === SCOPE_USER ? SCOPE_USER : SCOPE_SYSTEM
    })
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    SCOPE_SYSTEM: SCOPE_SYSTEM,
    SCOPE_USER: SCOPE_USER,
    UNIT_VERBS: UNIT_VERBS,
    validUnit: validUnit,
    unescapeUnitName: unescapeUnitName,
    failedCommand: failedCommand,
    unitCommand: unitCommand,
    parseFailedUnits: parseFailedUnits
  }
}
