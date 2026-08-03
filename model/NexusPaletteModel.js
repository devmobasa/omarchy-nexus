// Command palette model for Omarchy Nexus: entry catalogue constants plus
// the fuzzy filter. Loaded by both QML and the Node test harness, so it
// must stay dependency-free. The facade assembles live entries (players,
// minimized windows, pins, keybinds) around the static catalogue here and
// executes activations by entry kind — this module never runs anything.

var MAX_RESULTS = 8

// Entry kinds; `arg` semantics per kind:
//   page      -> page id to switch to
//   control   -> control action name dispatched by the facade
//   player    -> index into mediaAllPlayers
//   minimized -> window address to restore
//   setting   -> settings key to toggle
//   pin       -> pinned snippet text to copy
//   keybind   -> combo text to copy
//   sibling   -> plugin id to summon
var KINDS = {
  PAGE: "page",
  CONTROL: "control",
  PLAYER: "player",
  MINIMIZED: "minimized",
  SETTING: "setting",
  PIN: "pin",
  KEYBIND: "keybind",
  SIBLING: "sibling"
}

// The fixed control actions. Subtitles showing live state are attached at
// assembly time; args match the facade's dispatch switch exactly.
var CONTROL_ENTRIES = [
  { kind: KINDS.CONTROL, arg: "dnd", title: "Toggle Do Not Disturb", icon: "󰂛" },
  { kind: KINDS.CONTROL, arg: "night-light", title: "Toggle Night Light", icon: "󰛨" },
  { kind: KINDS.CONTROL, arg: "stay-awake", title: "Toggle Stay Awake", icon: "󰅶" },
  { kind: KINDS.CONTROL, arg: "bluetooth", title: "Toggle Bluetooth", icon: "󰂯" },
  { kind: KINDS.CONTROL, arg: "mute-output", title: "Mute / unmute output", icon: "󰝟" },
  { kind: KINDS.CONTROL, arg: "mute-microphone", title: "Mute / unmute microphone", icon: "󰍭" },
  { kind: KINDS.CONTROL, arg: "game-mode", title: "Toggle Game Mode", icon: "󰊴" },
  { kind: KINDS.CONTROL, arg: "pomodoro", title: "Start / pause Pomodoro", icon: "󰄉" },
  { kind: KINDS.CONTROL, arg: "capture", title: "Capture (screenshot / record)", icon: "󰄀" },
  { kind: KINDS.CONTROL, arg: "power", title: "Power menu", icon: "󰐥" },
  { kind: KINDS.CONTROL, arg: "theme", title: "Change theme", icon: "󰸌" },
  { kind: KINDS.CONTROL, arg: "background", title: "Change background", icon: "󰸉" },
  { kind: KINDS.CONTROL, arg: "clear-alerts", title: "Clear notification history", icon: "󰎟" }
]

// Case-insensitive subsequence score; -1 means no match. Word starts and
// consecutive runs outrank scattered hits, and shorter haystacks win ties
// so exact-ish titles surface above long keybind descriptions.
function fuzzyScore(query, text) {
  var needle = String(query == null ? "" : query).toLowerCase()
  var haystack = String(text == null ? "" : text).toLowerCase()
  if (needle.length === 0) return 0
  if (haystack.length === 0) return -1
  var score = 0
  var hi = 0
  var lastHit = -2
  for (var ni = 0; ni < needle.length; ni++) {
    var ch = needle.charAt(ni)
    if (ch === " ") { lastHit = -2; continue }
    var found = -1
    for (; hi < haystack.length; hi++) {
      if (haystack.charAt(hi) === ch) { found = hi; break }
    }
    if (found === -1) return -1
    if (found === 0 || haystack.charAt(found - 1) === " ") score += 3
    else if (found === lastHit + 1) score += 2
    else score += 1
    lastHit = found
    hi = found + 1
  }
  return score * 1000 - haystack.length
}

// Rank entries against the query over "title subtitle". An empty query
// returns the head of the catalogue in assembly order.
function filterEntries(entries, query, cap) {
  var list = entries && typeof entries.length === "number" ? entries : []
  var limit = Math.floor(Number(cap))
  if (!isFinite(limit) || limit < 1) limit = MAX_RESULTS
  var trimmed = String(query == null ? "" : query).trim()
  if (trimmed.length === 0) return list.slice(0, limit)
  var scored = []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry) continue
    var haystack = String(entry.title || "") + " " + String(entry.subtitle || "")
    var score = fuzzyScore(trimmed, haystack)
    if (score < 0) continue
    scored.push({ entry: entry, score: score, index: i })
  }
  scored.sort(function (a, b) {
    if (a.score !== b.score) return b.score - a.score
    return a.index - b.index
  })
  var out = []
  for (var j = 0; j < scored.length && out.length < limit; j++) out.push(scored[j].entry)
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_RESULTS: MAX_RESULTS,
    KINDS: KINDS,
    CONTROL_ENTRIES: CONTROL_ENTRIES,
    fuzzyScore: fuzzyScore,
    filterEntries: filterEntries
  }
}
