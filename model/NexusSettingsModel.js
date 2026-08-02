// Validated settings reader for Omarchy Nexus. Loaded by both the QML entry
// point and the Node test harness, so it must stay dependency-free.
//
// Two layers, both optional and both validated field by field:
// 1. inline fields on the canonical top-level plugins[] entry in shell.json
//    (read-only from Nexus's side — Nexus never writes shell.json);
// 2. the interactive state file written by the Settings page
//    (~/.local/state/omarchy/settings/nexus.json), which overrides layer 1
//    for the boolean toggles it owns.

var DEFAULTS = {
  defaultPage: "overview",
  monitor: "focused",
  showMedia: true,
  showMetrics: true,
  showNetwork: true,
  showFetch: true,
  showCpu: true,
  showMemory: true,
  showStorage: true,
  showBattery: true,
  gmAnimations: true,
  gmBlur: true,
  gmShadows: true,
  gmGaps: true,
  gmRounding: true,
  gmTearing: true,
  preferredMediaIdentity: ""
}

// The booleans the Settings page owns; only these round-trip through the
// state file, and only literal true/false values are honored.
var STATE_FIELDS = ["showMedia", "showMetrics", "showNetwork", "showFetch",
  "showCpu", "showMemory", "showStorage", "showBattery",
  "gmAnimations", "gmBlur", "gmShadows", "gmGaps", "gmRounding", "gmTearing"]

function findEntry(pluginsArray, pluginId) {
  if (!pluginsArray || typeof pluginsArray.length !== "number") return null
  for (var i = 0; i < pluginsArray.length; i++) {
    var entry = pluginsArray[i]
    if (entry && typeof entry === "object" && entry.id === pluginId) return entry
  }
  return null
}

// validPages guards defaultPage against unknown pages; pass NexusModel.PAGES.
function readSettings(pluginsArray, pluginId, validPages) {
  var pages = validPages && typeof validPages.indexOf === "function" ? validPages : []
  var entry = findEntry(pluginsArray, pluginId) || {}

  var defaultPage = DEFAULTS.defaultPage
  if (typeof entry.defaultPage === "string" && pages.indexOf(entry.defaultPage) !== -1)
    defaultPage = entry.defaultPage

  var monitor = DEFAULTS.monitor
  if (typeof entry.monitor === "string" && entry.monitor.trim().length > 0)
    monitor = entry.monitor.trim()

  var settings = {
    defaultPage: defaultPage,
    monitor: monitor,
    preferredMediaIdentity: typeof entry.preferredMediaIdentity === "string"
      ? entry.preferredMediaIdentity : DEFAULTS.preferredMediaIdentity
  }
  for (var i = 0; i < STATE_FIELDS.length; i++) {
    var field = STATE_FIELDS[i]
    settings[field] = entry[field] === false ? false
      : (entry[field] === true ? true : DEFAULTS[field])
  }
  return settings
}

// Parse the state file's text into a validated overrides object. Anything
// that is not a known field with a literal boolean value is dropped.
function parseState(text) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try {
      parsed = JSON.parse(text)
    } catch (error) {
      parsed = null
    }
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) parsed = {}
  var overrides = {}
  for (var i = 0; i < STATE_FIELDS.length; i++) {
    var field = STATE_FIELDS[i]
    if (parsed[field] === true || parsed[field] === false) overrides[field] = parsed[field]
  }
  return overrides
}

// Layer the interactive overrides over the shell.json layer.
function applyState(base, overrides) {
  var merged = {}
  for (var key in base) merged[key] = base[key]
  var state = overrides || {}
  for (var i = 0; i < STATE_FIELDS.length; i++) {
    var field = STATE_FIELDS[i]
    if (state[field] === true || state[field] === false) merged[field] = state[field]
  }
  return merged
}

// Serialize overrides for the state file: known fields only, stable key
// order, trailing newline.
function buildStateJson(overrides) {
  var state = overrides || {}
  var kept = []
  for (var i = 0; i < STATE_FIELDS.length; i++) {
    var field = STATE_FIELDS[i]
    if (state[field] === true || state[field] === false)
      kept.push('  "' + field + '": ' + (state[field] ? "true" : "false"))
  }
  return "{\n" + kept.join(",\n") + "\n}\n"
}

// The state file's directory and path, XDG-aware like the rest of Omarchy.
function stateDir(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/settings"
}

function statePath(xdgStateHome, home) {
  return stateDir(xdgStateHome, home) + "/nexus.json"
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS,
    STATE_FIELDS: STATE_FIELDS,
    findEntry: findEntry,
    readSettings: readSettings,
    parseState: parseState,
    applyState: applyState,
    buildStateJson: buildStateJson,
    stateDir: stateDir,
    statePath: statePath
  }
}
