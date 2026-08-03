// Bar editor model: pure views over the host's shell.json bar layout for
// the Bar page. Loaded by both QML and the Node test harness;
// dependency-free.
//
// All MUTATIONS go through the host's pluginRegistry (moveBarWidget /
// setEnabled) — never raw shell.json edits: the registry preserves entry
// objects (inline settings survive moves), owns the clone/disabledPlugins
// bookkeeping, and validates placement. This module only prepares what
// those calls need.

var SECTIONS = ["left", "center", "right"]

// The tray is pinned at render time (the bar reorders it to the inner
// edge regardless of shell.json order), so moving it would visibly do
// nothing — the editor marks it locked instead of lying.
var LOCKED_IDS = ["omarchy.tray"]

function normalizeEntry(entry) {
  if (typeof entry === "string" && entry.length > 0) return { id: entry }
  if (entry && typeof entry === "object" && typeof entry.id === "string" && entry.id.length > 0)
    return { id: entry.id }
  return null
}

function layoutFrom(barConfig) {
  var layout = barConfig && typeof barConfig === "object" && barConfig.layout && typeof barConfig.layout === "object"
    ? barConfig.layout : {}
  var out = {}
  for (var s = 0; s < SECTIONS.length; s++) {
    var section = SECTIONS[s]
    var source = Array.isArray(layout[section]) ? layout[section] : []
    var entries = []
    for (var i = 0; i < source.length; i++) {
      var entry = normalizeEntry(source[i])
      if (entry) entries.push(entry)
    }
    out[section] = entries
  }
  return out
}

function titleFor(id, installedPlugins) {
  var manifest = installedPlugins && installedPlugins[id] ? installedPlugins[id] : null
  if (manifest && typeof manifest.name === "string" && manifest.name.length > 0) return manifest.name
  return id
}

// Flat display rows with everything a row's actions need.
function displayRows(layout, installedPlugins) {
  var rows = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var section = SECTIONS[s]
    var entries = layout[section] || []
    for (var i = 0; i < entries.length; i++) {
      rows.push({
        id: entries[i].id,
        title: titleFor(entries[i].id, installedPlugins),
        section: section,
        index: i,
        first: i === 0,
        last: i === entries.length - 1,
        locked: LOCKED_IDS.indexOf(entries[i].id) !== -1,
        prevId: i > 0 ? entries[i - 1].id : "",
        nextId: i < entries.length - 1 ? entries[i + 1].id : ""
      })
    }
  }
  return rows
}

// Installed bar-widget-kind plugins not currently in any section.
function availableWidgets(installedPlugins, layout) {
  var present = {}
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout[SECTIONS[s]] || []
    for (var i = 0; i < entries.length; i++) present[entries[i].id] = true
  }
  var out = []
  for (var id in installedPlugins) {
    var manifest = installedPlugins[id]
    if (!manifest || !Array.isArray(manifest.kinds)) continue
    if (manifest.kinds.indexOf("bar-widget") === -1) continue
    if (present[id]) continue
    out.push({ id: id, title: titleFor(id, installedPlugins) })
  }
  out.sort(function (a, b) { return a.title < b.title ? -1 : 1 })
  return out
}

function nextSection(section) {
  var index = SECTIONS.indexOf(section)
  return SECTIONS[(index + 1 + SECTIONS.length) % SECTIONS.length]
}

if (typeof module !== "undefined") {
  module.exports = {
    SECTIONS: SECTIONS,
    LOCKED_IDS: LOCKED_IDS,
    normalizeEntry: normalizeEntry,
    layoutFrom: layoutFrom,
    titleFor: titleFor,
    displayRows: displayRows,
    availableWidgets: availableWidgets,
    nextSection: nextSection
  }
}
