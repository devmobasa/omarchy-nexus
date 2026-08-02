// Validated settings reader for Omarchy Nexus. Loaded by both the QML entry
// point and the Node test harness, so it must stay dependency-free.
//
// Settings live inline on the canonical top-level plugins[] entry in
// shell.json. Every field is optional; invalid values fall back to defaults
// rather than failing. Nexus never writes settings during open.

var DEFAULTS = {
  defaultPage: "overview",
  monitor: "focused",
  showMedia: true,
  showMetrics: true,
  preferredMediaIdentity: ""
}

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

  return {
    defaultPage: defaultPage,
    monitor: monitor,
    showMedia: entry.showMedia === false ? false : DEFAULTS.showMedia,
    showMetrics: entry.showMetrics === false ? false : DEFAULTS.showMetrics,
    preferredMediaIdentity: typeof entry.preferredMediaIdentity === "string"
      ? entry.preferredMediaIdentity : DEFAULTS.preferredMediaIdentity
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS,
    findEntry: findEntry,
    readSettings: readSettings
  }
}
