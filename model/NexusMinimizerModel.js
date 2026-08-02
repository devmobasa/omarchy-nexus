// Minimizer model for Omarchy Nexus. Loaded by both QML and the Node test
// harness; dependency-free.
//
// Integrates with the user's hyprland-minimizer scripts (Super+M / Super+R):
// minimized windows live on the special:minimized workspace, and the
// scripts keep sidecar data under $XDG_RUNTIME_DIR/hyprland-minimizer —
// state.json ({address: {workspace, monitor, thumb}}) plus history.txt
// (addresses, newest last) and pre-captured 16:9 preview JPGs.
//
// Nexus reads the sidecar and restores with the scripts' exact dispatch
// semantics (move to the active workspace WITH follow, then focus). It
// never edits the sidecar: the scripts' own prune pass drops entries for
// windows that are no longer minimized, so restored rows self-heal there.

var MINIMIZED_WORKSPACE = "special:minimized"

function runtimeDir(xdgRuntimeDir) {
  var base = typeof xdgRuntimeDir === "string" && xdgRuntimeDir.trim().length > 0
    ? xdgRuntimeDir.trim() : "/tmp"
  return base + "/hyprland-minimizer"
}

function sidecarPath(dir) {
  return dir + "/state.json"
}

function historyPath(dir) {
  return dir + "/history.txt"
}

function ensure0x(address) {
  var value = String(address == null ? "" : address).trim()
  if (value.length === 0) return ""
  return value.indexOf("0x") === 0 ? value : "0x" + value
}

function isValidAddress(address) {
  return /^0x[0-9a-fA-F]+$/.test(ensure0x(address))
}

// The sidecar keys addresses in the 0x form hyprctl reports.
function parseSidecar(text) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {}
  var out = {}
  for (var address in parsed) {
    var entry = parsed[address]
    if (!entry || typeof entry !== "object") continue
    out[ensure0x(address)] = {
      workspace: typeof entry.workspace === "string" ? entry.workspace : "",
      monitor: typeof entry.monitor === "string" ? entry.monitor : "",
      thumb: typeof entry.thumb === "string" ? entry.thumb : ""
    }
  }
  return out
}

function parseHistory(text) {
  var lines = String(text == null ? "" : text).split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line.length > 0) out.push(ensure0x(line))
  }
  return out
}

// Thumb filenames embed window titles verbatim (spaces, colons, '#'), so
// the file:// URL must encode every path segment.
function thumbUrl(path) {
  var value = String(path == null ? "" : path)
  if (value.length === 0 || value.charAt(0) !== "/") return ""
  var segments = value.split("/")
  var encoded = []
  for (var i = 0; i < segments.length; i++) encoded.push(encodeURIComponent(segments[i]))
  return "file://" + encoded.join("/")
}

function originLabel(origin) {
  if (!origin) return "origin unknown"
  var parts = []
  if (origin.workspace !== "") parts.push("WS " + origin.workspace)
  if (origin.monitor !== "") parts.push(origin.monitor)
  return parts.length > 0 ? parts.join(" · ") : "origin unknown"
}

// Merge the live minimized windows with the sidecar, newest-minimized
// first (the history file is newest LAST). Windows the scripts never saw
// (moved by hand) still list, with unknown origin and no thumb.
function rows(windows, sidecar, history) {
  var list = windows && typeof windows.length === "number" ? windows : []
  var order = {}
  var reversed = (history || []).slice().reverse()
  for (var h = 0; h < reversed.length; h++) {
    if (order[reversed[h]] === undefined) order[reversed[h]] = h
  }
  var out = []
  for (var i = 0; i < list.length; i++) {
    var win = list[i]
    if (!win) continue
    var address = ensure0x(win.address)
    if (!isValidAddress(address)) continue
    var origin = (sidecar || {})[address] || null
    out.push({
      address: address,
      title: String(win.title || "").trim() || "(untitled window)",
      origin: originLabel(origin),
      thumb: origin && origin.thumb !== "" ? origin.thumb : "",
      toplevel: win.toplevel || null,
      sortKey: order[address] !== undefined ? order[address] : 1000 + i
    })
  }
  out.sort(function (a, b) { return a.sortKey - b.sortKey })
  return out
}

// The scripts' exact restore semantics: move to the target workspace WITH
// follow (the window lands focused where you are), then an explicit focus.
// Both use the string window selector the scripts use; nothing unhex can
// reach the Lua string.
function restoreDispatch(address, workspaceId) {
  var addr = ensure0x(address)
  var id = Number(workspaceId)
  if (!isValidAddress(addr) || !isFinite(id) || id <= 0 || id !== Math.floor(id)) return ""
  return 'hl.dsp.window.move({ workspace = tostring(' + id
    + '), window = "address:' + addr + '", follow = true })'
}

function focusDispatch(address) {
  var addr = ensure0x(address)
  if (!isValidAddress(addr)) return ""
  return 'hl.dsp.focus({ window = "address:' + addr + '" })'
}

if (typeof module !== "undefined") {
  module.exports = {
    MINIMIZED_WORKSPACE: MINIMIZED_WORKSPACE,
    runtimeDir: runtimeDir,
    sidecarPath: sidecarPath,
    historyPath: historyPath,
    ensure0x: ensure0x,
    isValidAddress: isValidAddress,
    parseSidecar: parseSidecar,
    parseHistory: parseHistory,
    thumbUrl: thumbUrl,
    originLabel: originLabel,
    rows: rows,
    restoreDispatch: restoreDispatch,
    focusDispatch: focusDispatch
  }
}
