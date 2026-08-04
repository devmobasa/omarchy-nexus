// Suite-integration model for Omarchy Nexus: read-only views over the
// state files its sibling plugins maintain (screen-time day files, calendar
// caches, the pomodoro session) plus the first-party notification history.
// Loaded by both QML and the Node test harness; dependency-free.

// ---- screen time (community.screen-time day files) --------------------------

function screenTimeDir(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/screen-time"
}

function dayKey(nowMs) {
  var d = new Date(Number(nowMs))
  var pad = function (n) { return n < 10 ? "0" + n : String(n) }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function screenTimeDayPath(dir, key) {
  return dir + "/" + key + ".json"
}

// Summarize a day file: total time and the top app. Malformed input is an
// absent card, never an error.
function screenTimeSummary(text, expectedKey) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!parsed || parsed.date !== expectedKey || !Array.isArray(parsed.spans)) return null
  var totals = {}
  var totalMs = 0
  for (var i = 0; i < parsed.spans.length; i++) {
    var span = parsed.spans[i]
    if (!Array.isArray(span) || span.length < 3) continue
    var duration = Number(span[2]) - Number(span[1])
    if (!isFinite(duration) || duration <= 0) continue
    totals[String(span[0])] = (totals[String(span[0])] || 0) + duration
    totalMs += duration
  }
  if (totalMs <= 0) return null
  var topApp = ""
  var topMs = 0
  for (var app in totals) {
    if (totals[app] > topMs) { topMs = totals[app]; topApp = app }
  }
  return { totalMs: totalMs, topApp: topApp, topMs: topMs }
}

function formatHours(ms) {
  var minutes = Math.floor(Math.max(0, Number(ms)) / 60000)
  var hours = Math.floor(minutes / 60)
  if (hours > 0) return hours + " h " + (minutes % 60) + " m"
  if (minutes > 0) return minutes + " m"
  return "<1 m"
}

function appLabel(appId) {
  var id = String(appId == null ? "" : appId)
  var parts = id.split(".")
  var last = parts[parts.length - 1]
  if (last.length === 0) return id
  return last.charAt(0).toUpperCase() + last.slice(1)
}

function screenTimeLine(summary) {
  if (!summary) return ""
  var text = formatHours(summary.totalMs) + " today"
  if (summary.topApp !== "")
    text += " · " + appLabel(summary.topApp) + " " + formatHours(summary.topMs)
  return text
}

// ---- notification history (omarchy.notifications state file) ---------------

function notificationsPath(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/notifications.json"
}

// Some senders (Ghostty among them) leave app_name empty but set a
// reverse-DNS desktop id as the icon; derive the display name from it.
// Generic themed icons ("utilities-terminal") carry no dot after the
// extension strip and yield nothing.
function notificationAppFallback(appIcon) {
  var icon = String(appIcon == null ? "" : appIcon)
  icon = icon.slice(icon.lastIndexOf("/") + 1).replace(/\.(png|svg|xpm|ico)$/i, "")
  if (icon.indexOf(".") < 0) return ""
  return appLabel(icon)
}

// The v2 file carries pending (unseen) and past rows; merge both, newest
// first, validated field by field.
function parseNotifications(text, cap) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!parsed || typeof parsed !== "object") return []
  var rows = []
  var sources = [
    { list: parsed.pending, pending: true },
    { list: parsed.past, pending: false }
  ]
  for (var s = 0; s < sources.length; s++) {
    var list = Array.isArray(sources[s].list) ? sources[s].list : []
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (!row || typeof row !== "object") continue
      var timestamp = Number(row.timestamp)
      if (!isFinite(timestamp) || timestamp <= 0) continue
      var app = typeof row.app === "string" ? row.app : ""
      if (app === "") app = notificationAppFallback(row.appIcon)
      rows.push({
        app: app,
        summary: typeof row.summary === "string" ? row.summary : "",
        body: typeof row.body === "string" ? row.body.replace(/\s+/g, " ").trim() : "",
        urgency: Number(row.urgency) || 0,
        timestamp: timestamp,
        pending: sources[s].pending,
        // The daemon's stable per-notification id: the key into the
        // service's liveRefs map and removeByOriginalId().
        originalId: isFinite(Number(row.originalId)) ? Number(row.originalId) : 0
      })
    }
  }
  rows.sort(function (a, b) { return b.timestamp - a.timestamp })
  var limit = Number(cap)
  if (!isFinite(limit) || limit < 1) limit = 50
  return rows.slice(0, limit)
}

// Unseen count for the bar badge: just the pending list length, no row
// validation — the badge never renders row content.
function pendingCount(text) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.pending)) return 0
  return parsed.pending.length
}

function relativeTime(timestampMs, nowMs) {
  var deltaMinutes = Math.floor((Number(nowMs) - Number(timestampMs)) / 60000)
  if (deltaMinutes < 1) return "now"
  if (deltaMinutes < 60) return deltaMinutes + " m ago"
  var hours = Math.floor(deltaMinutes / 60)
  if (hours < 24) return hours + " h ago"
  return Math.floor(hours / 24) + " d ago"
}

// ---- clipboard history (omarchy.clipboard state file) -----------------------

function clipboardPath(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/clipboard-history.json"
}

function clipPreview(text) {
  var preview = String(text == null ? "" : text).replace(/\s+/g, " ").trim()
  if (preview.length > 120) preview = preview.slice(0, 117) + "…"
  return preview
}

// Newest-first rows: text entries carry a one-line preview and the full
// text for copying; image entries carry their label only (the full manager
// owns image re-copying).
function parseClipboard(text, cap) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!Array.isArray(parsed)) return []
  var limit = Number(cap)
  if (!isFinite(limit) || limit < 1) limit = 15
  var rows = []
  for (var i = 0; i < parsed.length && rows.length < limit; i++) {
    var entry = parsed[i]
    if (!entry || typeof entry !== "object") continue
    if (entry.type === "text" && typeof entry.text === "string" && entry.text.trim().length > 0) {
      rows.push({ kind: "text", preview: clipPreview(entry.text), text: entry.text,
        key: clipEntryKey(entry) })
    } else if (entry.type === "image") {
      rows.push({
        kind: "image",
        preview: "[image] " + (typeof entry.capturedAt === "string" ? entry.capturedAt : ""),
        text: "",
        key: clipEntryKey(entry)
      })
    }
  }
  return rows
}

// The first-party manager's own identity scheme, so a row maps back to
// its file entry exactly.
function clipEntryKey(entry) {
  if (!entry || typeof entry !== "object") return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

// Remove one entry from the raw history file text by key, preserving the
// manager's exact serialization (2-space indent, trailing newline) so the
// overlay's file watcher adopts the write as its own. Returns null when
// nothing matches — the caller must not write.
function removeClipEntry(rawText, key) {
  var parsed = null
  if (typeof rawText === "string" && rawText.length > 0) {
    try { parsed = JSON.parse(rawText) } catch (error) { parsed = null }
  }
  if (!Array.isArray(parsed) || typeof key !== "string" || key.length === 0) return null
  for (var i = 0; i < parsed.length; i++) {
    if (clipEntryKey(parsed[i]) === key) {
      parsed.splice(i, 1)
      return JSON.stringify(parsed, null, 2) + "\n"
    }
  }
  return null
}

// ---- clipboard pins (Nexus's own state file) --------------------------------
// A JSON array of pinned snippet strings, newest first. Pins are Nexus
// data, not settings, so they live in their own state file.

var PIN_CAP = 20

function pinsPath(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/nexus-clipboard-pins.json"
}

function parsePins(text) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!Array.isArray(parsed)) return []
  var rows = []
  for (var i = 0; i < parsed.length && rows.length < PIN_CAP; i++) {
    if (typeof parsed[i] !== "string" || parsed[i].trim().length === 0) continue
    rows.push({ kind: "text", preview: clipPreview(parsed[i]), text: parsed[i], pinned: true })
  }
  return rows
}

function serializePins(texts) {
  var list = texts && typeof texts.length === "number" ? texts : []
  var out = []
  for (var i = 0; i < list.length && out.length < PIN_CAP; i++) {
    if (typeof list[i] === "string" && list[i].trim().length > 0) out.push(list[i])
  }
  return JSON.stringify(out, null, 2) + "\n"
}

// Toggle semantics: pinning prepends (newest pin first), unpinning removes
// every occurrence. The caller persists the returned list.
function togglePin(texts, text) {
  var value = String(text == null ? "" : text)
  if (value.trim().length === 0) return texts && typeof texts.length === "number" ? texts.slice() : []
  var list = texts && typeof texts.length === "number" ? texts : []
  var out = []
  var removed = false
  for (var i = 0; i < list.length; i++) {
    if (list[i] === value) { removed = true; continue }
    out.push(list[i])
  }
  if (!removed) out.unshift(value)
  return out.slice(0, PIN_CAP)
}

function isPinned(pinRows, text) {
  var list = pinRows && typeof pinRows.length === "number" ? pinRows : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].text === text) return true
  }
  return false
}

function copyCommand(text) {
  return ["wl-copy", "--", String(text == null ? "" : text)]
}

// ---- quick notes ------------------------------------------------------------

function notesPath(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/nexus-notes.md"
}

// ---- game-mode presets ------------------------------------------------------

// Preset buttons batch-set the six gm* booleans; "custom" is whatever the
// individual toggles say. Detection compares the current set to each preset.
var GAME_MODE_PRESETS = [
  { key: "full", label: "Full", settings: { gmAnimations: true, gmBlur: true, gmShadows: true, gmGaps: true, gmRounding: true, gmTearing: true } },
  { key: "effects", label: "Effects only", settings: { gmAnimations: true, gmBlur: true, gmShadows: true, gmGaps: false, gmRounding: false, gmTearing: false } },
  { key: "minimal", label: "Minimal", settings: { gmAnimations: true, gmBlur: false, gmShadows: false, gmGaps: false, gmRounding: false, gmTearing: false } }
]

function activePreset(settings) {
  for (var i = 0; i < GAME_MODE_PRESETS.length; i++) {
    var preset = GAME_MODE_PRESETS[i]
    var matches = true
    for (var key in preset.settings) {
      if ((settings[key] === true) !== preset.settings[key]) { matches = false; break }
    }
    if (matches) return preset.key
  }
  return "custom"
}

if (typeof module !== "undefined") {
  module.exports = {
    screenTimeDir: screenTimeDir,
    dayKey: dayKey,
    screenTimeDayPath: screenTimeDayPath,
    screenTimeSummary: screenTimeSummary,
    formatHours: formatHours,
    appLabel: appLabel,
    screenTimeLine: screenTimeLine,
    notificationsPath: notificationsPath,
    notificationAppFallback: notificationAppFallback,
    parseNotifications: parseNotifications,
    pendingCount: pendingCount,
    relativeTime: relativeTime,
    clipboardPath: clipboardPath,
    parseClipboard: parseClipboard,
    clipPreview: clipPreview,
    clipEntryKey: clipEntryKey,
    removeClipEntry: removeClipEntry,
    PIN_CAP: PIN_CAP,
    pinsPath: pinsPath,
    parsePins: parsePins,
    serializePins: serializePins,
    togglePin: togglePin,
    isPinned: isPinned,
    copyCommand: copyCommand,
    notesPath: notesPath,
    GAME_MODE_PRESETS: GAME_MODE_PRESETS,
    activePreset: activePreset
  }
}
