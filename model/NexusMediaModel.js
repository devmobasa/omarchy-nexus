// Deterministic MPRIS player model for Omarchy Nexus. Loaded by both the QML
// adapter and the Node test harness, so it must stay dependency-free.
//
// Records are grouped by exact sourceKey; a real player always beats a proxy
// of the same source; representatives are then ordered by one total order.
// No fuzzy matching, substring matching, or display-name preference anywhere.

var STATE_ORDER = { playing: 0, paused: 1, stopped: 2, unknown: 3 }

var ALLOWED_ART_SCHEMES = ["file", "image", "qrc", "http", "https"]

// One shared identity normalizer: exact after trim + ASCII lowercase.
function normalizeIdentity(value) {
  return String(value == null ? "" : value).trim().toLowerCase()
}

// Explicit proxy alias table. Matches are exact against the normalized
// identity, normalized desktopEntry, or verbatim bus name — never substrings.
// - sourceKey groups an attributable proxy with its real source.
// - drop excludes a proxy that mirrors whichever player is active and can
//   never be attributed to one source (it would otherwise surface as a
//   permanent ghost duplicate of the real player).
var PROXY_ALIASES = [
  { busName: "org.mpris.MediaPlayer2.playerctld", drop: true },
  { identity: "playerctld", drop: true },
  { desktopEntry: "playerctld", drop: true },
  { identity: "plasma browser integration", sourceKey: "chromium", isProxy: true }
]

function aliasFor(busName, identityKey, desktopEntryKey) {
  for (var i = 0; i < PROXY_ALIASES.length; i++) {
    var alias = PROXY_ALIASES[i]
    if (alias.busName !== undefined && alias.busName === busName) return alias
    if (alias.identity !== undefined && alias.identity === identityKey) return alias
    if (alias.desktopEntry !== undefined && alias.desktopEntry === desktopEntryKey) return alias
  }
  return null
}

// raw: { busName, identity, desktopEntry, state, trackKey,
//        canPlay, canPause, canGoNext, canGoPrevious }
// state must already be one of playing/paused/stopped/unknown.
function buildRecord(raw) {
  var busName = String(raw && raw.busName || "")
  var identityKey = normalizeIdentity(raw && raw.identity)
  var desktopEntryKey = normalizeIdentity(raw && raw.desktopEntry)
  var alias = aliasFor(busName, identityKey, desktopEntryKey)

  var sourceKey = busName
  if (alias && alias.sourceKey !== undefined) sourceKey = alias.sourceKey
  else if (desktopEntryKey) sourceKey = desktopEntryKey
  else if (identityKey) sourceKey = identityKey

  var state = String(raw && raw.state || "")
  if (STATE_ORDER[state] === undefined) state = "unknown"

  return {
    busName: busName,
    identity: String(raw && raw.identity || "").trim(),
    identityKey: identityKey,
    sourceKey: sourceKey,
    isProxy: !!(alias && (alias.isProxy || alias.drop)),
    dropped: !!(alias && alias.drop),
    state: state,
    trackKey: String(raw && raw.trackKey || ""),
    canPlay: !!(raw && raw.canPlay),
    canPause: !!(raw && raw.canPause),
    canGoNext: !!(raw && raw.canGoNext),
    canGoPrevious: !!(raw && raw.canGoPrevious)
  }
}

// activitySerial bookkeeping. previous maps busName -> { state, trackKey,
// serial }; lastSerial is the monotonic counter. A serial bumps only when a
// player transitions into playing, changes track while playing, or is newly
// discovered already playing. Position, volume, artwork, and other metadata
// are not inputs, so they can never bump it.
function reconcileActivity(previous, records, lastSerial) {
  var prior = previous || {}
  var serial = Number(lastSerial) || 0
  var next = {}
  for (var i = 0; i < records.length; i++) {
    var record = records[i]
    if (record.dropped) continue
    var before = prior[record.busName]
    var bumped = false
    if (!before) {
      bumped = record.state === "playing"
    } else if (record.state === "playing") {
      bumped = before.state !== "playing" || before.trackKey !== record.trackKey
    }
    if (bumped) serial += 1
    next[record.busName] = {
      state: record.state,
      trackKey: record.trackKey,
      serial: bumped ? serial : (before ? before.serial : 0)
    }
  }
  return { serials: next, lastSerial: serial }
}

// A successful user action explicitly targeting a player bumps its serial.
function bumpUserAction(serials, busName, lastSerial) {
  var next = {}
  for (var key in serials) next[key] = serials[key]
  var serial = (Number(lastSerial) || 0) + 1
  var before = next[busName]
  next[busName] = {
    state: before ? before.state : "unknown",
    trackKey: before ? before.trackKey : "",
    serial: serial
  }
  return { serials: next, lastSerial: serial }
}

function serialOf(serials, busName) {
  var entry = serials ? serials[busName] : null
  return entry ? Number(entry.serial) || 0 : 0
}

// Phase 2 total order. Returns negative when a ranks before b. Plain string
// comparison is UTF-16 code-unit order: locale-independent by construction.
function compareRepresentatives(a, b, preferredIdentity, serials) {
  var stateDelta = STATE_ORDER[a.state] - STATE_ORDER[b.state]
  if (stateDelta !== 0) return stateDelta
  if (preferredIdentity) {
    var aPreferred = a.identityKey === preferredIdentity ? 0 : 1
    var bPreferred = b.identityKey === preferredIdentity ? 0 : 1
    if (aPreferred !== bPreferred) return aPreferred - bPreferred
  }
  var serialDelta = serialOf(serials, b.busName) - serialOf(serials, a.busName)
  if (serialDelta !== 0) return serialDelta
  if (a.identityKey !== b.identityKey) return a.identityKey < b.identityKey ? -1 : 1
  if (a.busName !== b.busName) return a.busName < b.busName ? -1 : 1
  return 0
}

// Phase 1: group by exact sourceKey and pick one representative per group.
// Real records discard every proxy in their group; a proxy can represent only
// a proxy-only group, so a vanished real player lets its proxy promote.
// Phase 2: one total order across representatives. Selection and the player
// cycle both consume this list, so they can never disagree about ordering.
function orderedRepresentatives(records, preferred, serials) {
  var groups = {}
  var groupOrder = []
  for (var i = 0; i < records.length; i++) {
    var record = records[i]
    if (record.dropped) continue
    if (!groups[record.sourceKey]) {
      groups[record.sourceKey] = []
      groupOrder.push(record.sourceKey)
    }
    groups[record.sourceKey].push(record)
  }

  var representatives = []
  for (var g = 0; g < groupOrder.length; g++) {
    var group = groups[groupOrder[g]]
    var candidates = []
    for (var j = 0; j < group.length; j++) {
      if (!group[j].isProxy) candidates.push(group[j])
    }
    if (candidates.length === 0) candidates = group
    candidates.sort(function (a, b) {
      return compareRepresentatives(a, b, preferred, serials)
    })
    representatives.push(candidates[0])
  }

  representatives.sort(function (a, b) {
    return compareRepresentatives(a, b, preferred, serials)
  })
  return representatives
}

// A manual override (sourceKey) wins while that player still exists, then
// selection falls back to the deterministic order.
function selectPlayer(records, preferredMediaIdentity, serials, overrideKey) {
  var preferred = normalizeIdentity(preferredMediaIdentity)
  var representatives = orderedRepresentatives(records, preferred, serials)
  if (representatives.length === 0) return null
  if (overrideKey) {
    for (var i = 0; i < representatives.length; i++) {
      if (representatives[i].sourceKey === overrideKey) return representatives[i]
    }
  }
  return representatives[0]
}

function countPlayers(records) {
  return orderedRepresentatives(records, "", null).length
}

// Next representative's sourceKey after currentKey, wrapping; an unknown or
// absent key lands on the first representative.
function cyclePlayer(records, currentKey, preferredMediaIdentity, serials) {
  var preferred = normalizeIdentity(preferredMediaIdentity)
  var representatives = orderedRepresentatives(records, preferred, serials)
  if (representatives.length === 0) return ""
  var index = -1
  for (var i = 0; i < representatives.length; i++) {
    if (representatives[i].sourceKey === currentKey) { index = i; break }
  }
  return representatives[(index + 1) % representatives.length].sourceKey
}

// m:ss under an hour, h:mm:ss above; invalid input renders as nothing rather
// than a fake zero.
function formatPlaybackTime(seconds) {
  var s = Math.floor(Number(seconds))
  if (!isFinite(s) || s < 0) return ""
  var hours = Math.floor(s / 3600)
  var minutes = Math.floor((s % 3600) / 60)
  var secs = s % 60
  var pad = function (n) { return n < 10 ? "0" + n : String(n) }
  return hours > 0
    ? hours + ":" + pad(minutes) + ":" + pad(secs)
    : minutes + ":" + pad(secs)
}

// Fill fraction for the seek bar; null when the track has no usable length.
function positionFraction(positionSeconds, lengthSeconds) {
  var length = Number(lengthSeconds)
  var position = Number(positionSeconds)
  if (!isFinite(length) || length <= 0 || !isFinite(position)) return null
  return Math.min(1, Math.max(0, position / length))
}

// Target position in seconds for a seek to `fraction` of the track; null when
// the player cannot seek or the length is unusable, so the caller never sends
// a blind seek.
function clampSeek(fraction, lengthSeconds, canSeek) {
  if (!canSeek) return null
  var length = Number(lengthSeconds)
  var f = Number(fraction)
  if (!isFinite(length) || length <= 0 || !isFinite(f)) return null
  return Math.min(length, Math.max(0, f * length))
}

// Artwork URL whitelist: exact scheme match, everything else rejected.
function allowedArtUrl(url) {
  var value = String(url == null ? "" : url)
  var colon = value.indexOf(":")
  if (colon <= 0) return ""
  var scheme = value.slice(0, colon).toLowerCase()
  return ALLOWED_ART_SCHEMES.indexOf(scheme) !== -1 ? value : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    STATE_ORDER: STATE_ORDER,
    normalizeIdentity: normalizeIdentity,
    buildRecord: buildRecord,
    reconcileActivity: reconcileActivity,
    bumpUserAction: bumpUserAction,
    compareRepresentatives: compareRepresentatives,
    orderedRepresentatives: orderedRepresentatives,
    selectPlayer: selectPlayer,
    countPlayers: countPlayers,
    cyclePlayer: cyclePlayer,
    formatPlaybackTime: formatPlaybackTime,
    positionFraction: positionFraction,
    clampSeek: clampSeek,
    allowedArtUrl: allowedArtUrl
  }
}
