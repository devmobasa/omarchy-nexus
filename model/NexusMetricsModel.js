// Bounded resource-metrics model for Omarchy Nexus. Loaded by both the QML
// sampler and the Node test harness, so it must stay dependency-free.
//
// Units and cadence:
// - percentages are integers 0-100;
// - storage is reported in GiB (1024^3 bytes) with one decimal;
// - cpu/mem sample every CPU_MEM_INTERVAL_MS, storage every DISK_INTERVAL_MS,
//   and only while the panel is open;
// - a reading older than STALE_FACTOR times its cadence is stale and renders
//   as an em dash instead of a number.

var CPU_MEM_INTERVAL_MS = 2000
var DISK_INTERVAL_MS = 30000
var STALE_FACTOR = 3
var NET_HISTORY_CAP = 30

// Sparkline scale floor: idle background chatter (ARP, mDNS, RA, NTP) runs a
// few hundred B/s. Without a floor the window max always maps to the top
// pixel, so an idle link would draw identically to a saturated one.
var NET_SCALE_FLOOR = 65536

// Parse the aggregate "cpu " line of /proc/stat into cumulative tick counters.
// idle time includes iowait; total sums columns 1-8 only — the guest columns
// are excluded because the kernel already folds guest time into user/nice.
function parseCpuSample(text) {
  var lines = String(text == null ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("cpu ") !== 0) continue
    var fields = line.trim().split(/\s+/).slice(1)
    if (fields.length < 5) return null
    var total = 0
    for (var j = 0; j < fields.length; j++) {
      var value = Number(fields[j])
      if (!isFinite(value) || value < 0) return null
      if (j < 8) total += value
    }
    var idle = Number(fields[3]) + Number(fields[4])
    return { total: total, idle: idle }
  }
  return null
}

// Busy percentage over the delta between two cumulative samples. Returns null
// until two valid, advancing samples exist (counter resets included).
function cpuPercent(previous, current) {
  if (!previous || !current) return null
  var totalDelta = current.total - previous.total
  var idleDelta = current.idle - previous.idle
  if (!isFinite(totalDelta) || !isFinite(idleDelta) || totalDelta <= 0 || idleDelta < 0) return null
  var busy = Math.round(((totalDelta - idleDelta) / totalDelta) * 100)
  return Math.min(100, Math.max(0, busy))
}

// Parse /proc/meminfo. Used percent derives from MemAvailable, the kernel's
// own estimate, never from free/buffers arithmetic.
function parseMemInfo(text) {
  var lines = String(text == null ? "" : text).split("\n")
  var totalKb = null
  var availableKb = null
  for (var i = 0; i < lines.length; i++) {
    var match = /^(MemTotal|MemAvailable):\s+(\d+)\s+kB/.exec(lines[i])
    if (!match) continue
    if (match[1] === "MemTotal") totalKb = Number(match[2])
    else availableKb = Number(match[2])
  }
  if (!totalKb || availableKb === null || availableKb > totalKb) return null
  return {
    totalKb: totalKb,
    availableKb: availableKb,
    percent: Math.round(((totalKb - availableKb) / totalKb) * 100)
  }
}

// Virtual interfaces that would double-count real traffic (loopback mirrors
// everything local; tunnels/VPNs mirror the physical link they ride on;
// container bridges and veth pairs mirror container traffic). No standard
// predictable or legacy NIC name begins with any of these.
var VIRTUAL_INTERFACE_PREFIXES = ["lo", "docker", "br", "veth", "tun", "tap",
  "virbr", "vnet", "vmnet", "wg", "tailscale", "zt", "nordlynx", "ipsec",
  "ppp", "bond", "gre", "sit", "ifb", "dummy"]

function isVirtualInterface(name) {
  // VLAN sub-interfaces (eno1.100) mirror the parent link they ride on.
  if (name.indexOf(".") !== -1) return true
  for (var i = 0; i < VIRTUAL_INTERFACE_PREFIXES.length; i++) {
    var prefix = VIRTUAL_INTERFACE_PREFIXES[i]
    if (name === prefix || name.indexOf(prefix) === 0) return true
  }
  return false
}

// Parse /proc/net/dev: interface lines are `name: rx_bytes <7 more rx
// fields> tx_bytes ...` (tx_bytes is the 9th numeric field). Virtual
// interfaces are excluded so the sum tracks real link traffic; meminfo/stat
// lines can never match the nine-numeric-field shape.
function parseNetDev(text) {
  var lines = String(text == null ? "" : text).split("\n")
  var rxBytes = 0
  var txBytes = 0
  var interfaces = 0
  for (var i = 0; i < lines.length; i++) {
    var match = /^\s*([^\s:]+):\s*(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)\s+\d+/.exec(lines[i])
    if (!match || isVirtualInterface(match[1])) continue
    rxBytes += Number(match[2])
    txBytes += Number(match[3])
    interfaces += 1
  }
  return interfaces > 0 ? { rxBytes: rxBytes, txBytes: txBytes, interfaces: interfaces } : null
}

// /proc/uptime is the only sampled line of exactly two decimal floats.
function parseUptime(text) {
  var match = /^\s*(\d+\.\d+)\s+\d+\.\d+\s*$/m.exec(String(text == null ? "" : text))
  return match ? Number(match[1]) : null
}

// The sampler reads /proc/stat, /proc/meminfo, /proc/net/dev and /proc/uptime
// in one bounded process; the concatenated output parses as one text.
function parseSample(text) {
  return {
    cpu: parseCpuSample(text),
    mem: parseMemInfo(text),
    net: parseNetDev(text),
    uptimeSeconds: parseUptime(text)
  }
}

// Bytes/second between two cumulative counter samples; null across counter
// resets or non-advancing clocks, mirroring cpuPercent's reset rule.
function rateBetween(prevBytes, prevMs, curBytes, curMs) {
  if (prevBytes == null || curBytes == null) return null
  var dtMs = Number(curMs) - Number(prevMs)
  var delta = Number(curBytes) - Number(prevBytes)
  if (!isFinite(dtMs) || !isFinite(delta) || dtMs <= 0 || delta < 0) return null
  return delta * 1000 / dtMs
}

// Rolling sample window; invalid values record as zero so the timeline keeps
// its shape instead of silently skipping samples.
function pushHistory(list, value, cap) {
  var source = list && typeof list.length === "number" ? list : []
  var capped = Math.floor(Number(cap))
  if (!isFinite(capped) || capped < 1) capped = NET_HISTORY_CAP
  var v = Number(value)
  var next = source.concat([isFinite(v) && v >= 0 ? v : 0])
  return next.length > capped ? next.slice(next.length - capped) : next
}

function historyMax(a, b) {
  var max = 0
  var lists = [a, b]
  for (var l = 0; l < lists.length; l++) {
    var list = lists[l] && typeof lists[l].length === "number" ? lists[l] : []
    for (var i = 0; i < list.length; i++) {
      var value = Number(list[i])
      if (isFinite(value) && value > max) max = value
    }
  }
  return max
}

// Normalised polyline points for a declarative Shapes path; fewer than two
// samples draw nothing rather than a misleading dot or flat line.
function sparklinePoints(history, width, height, sharedMax) {
  var list = history && typeof history.length === "number" ? history : []
  var w = Number(width)
  var h = Number(height)
  if (list.length < 2 || !isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return []
  var max = Number(sharedMax)
  if (!isFinite(max) || max <= 0) max = 1
  var points = []
  for (var i = 0; i < list.length; i++) {
    var value = Number(list[i])
    if (!isFinite(value) || value < 0) value = 0
    points.push({
      x: (i / (list.length - 1)) * w,
      y: h - Math.min(1, value / max) * h
    })
  }
  return points
}

function formatRate(bytesPerSec) {
  if (bytesPerSec == null) return "—"
  var rate = Number(bytesPerSec)
  if (!isFinite(rate) || rate < 0) return "—"
  if (rate < 1024) return Math.round(rate) + " B/s"
  if (rate < 1024 * 1024) return (rate / 1024).toFixed(1) + " KiB/s"
  if (rate < 1024 * 1024 * 1024) return (rate / (1024 * 1024)).toFixed(1) + " MiB/s"
  return (rate / (1024 * 1024 * 1024)).toFixed(2) + " GiB/s"
}

// At most two units, largest first: "3 d 4 h", "2 h 13 m", "45 m", "<1 m".
// Minutes are dropped once days show, matching how people read uptimes.
function formatDuration(seconds) {
  var s = Number(seconds)
  if (!isFinite(s) || s <= 0) return ""
  var minutes = Math.floor(s / 60)
  var days = Math.floor(minutes / (60 * 24))
  var hours = Math.floor((minutes % (60 * 24)) / 60)
  var mins = minutes % 60
  var parts = []
  if (days > 0) parts.push(days + " d")
  if (hours > 0) parts.push(hours + " h")
  if (days === 0 && mins > 0) parts.push(mins + " m")
  if (parts.length === 0) return "<1 m"
  return parts.slice(0, 2).join(" ")
}

// hostname · kernel · up 3 d 4 h — missing parts drop out silently.
function fetchLine(host, kernel, uptimeSeconds) {
  var parts = []
  var h = String(host == null ? "" : host).trim()
  var k = String(kernel == null ? "" : kernel).trim()
  if (h) parts.push(h)
  if (k) parts.push(k)
  var up = formatDuration(uptimeSeconds)
  if (up) parts.push("up " + up)
  return parts.join(" · ")
}

// Parse `df -P -k <mount>` (POSIX format): the second line is
//   device 1024-blocks used available capacity% mount
function parseDiskFree(text) {
  var lines = String(text == null ? "" : text).split("\n")
  if (lines.length < 2) return null
  var fields = lines[1].trim().split(/\s+/)
  if (fields.length < 6) return null
  var percent = Number(String(fields[4]).replace("%", ""))
  var availableKb = Number(fields[3])
  if (!isFinite(percent) || percent < 0 || percent > 100) return null
  if (!isFinite(availableKb) || availableKb < 0) return null
  return { percent: Math.round(percent), availableKb: availableKb, mount: fields[5] }
}

function formatGib(kb) {
  var gib = Number(kb) / (1024 * 1024)
  if (!isFinite(gib) || gib < 0) return ""
  return gib.toFixed(1) + " GiB"
}

function isStale(sampledAtMs, nowMs, intervalMs) {
  var sampled = Number(sampledAtMs) || 0
  if (sampled <= 0) return true
  return Number(nowMs) - sampled > Number(intervalMs) * STALE_FACTOR
}

// UPowerDeviceState values, mirrored so the model stays QML-free.
var BATTERY_STATE = { Unknown: 0, Charging: 1, Discharging: 2, Empty: 3,
  FullyCharged: 4, PendingCharge: 5, PendingDischarge: 6 }

// Battery detail line from reactive UPower state. The device's own state
// enum is primary; the system-wide onBattery flag is only the fallback when
// the device reports Unknown (a threshold-parked battery is not "charging"
// just because AC is attached). Time estimates are optional — UPower reports
// 0 when it does not know, which renders as the bare state rather than a
// fake countdown.
function batteryDetail(present, state, onBattery, percent, timeToEmptySec, timeToFullSec) {
  if (!present) return "No battery"
  var s = Number(state)
  if (!isFinite(s) || s === BATTERY_STATE.Unknown)
    s = onBattery ? BATTERY_STATE.Discharging : BATTERY_STATE.Charging
  var pct = Number(percent)

  if (s === BATTERY_STATE.Discharging || s === BATTERY_STATE.PendingDischarge) {
    var left = formatDuration(timeToEmptySec)
    return left ? "On battery — " + left + " left" : "On battery"
  }
  if (s === BATTERY_STATE.Empty) return "Empty"
  // Firmware charge thresholds surface as FullyCharged well below 100% or
  // as PendingCharge; neither should read as an active charge.
  if (s === BATTERY_STATE.FullyCharged) return pct < 99 ? "Holding at " + pct + "%" : "Charged"
  if (s === BATTERY_STATE.PendingCharge) return "Plugged in — not charging"
  if (pct >= 100) return "Charged"
  var toFull = formatDuration(timeToFullSec)
  return toFull ? "Charging — " + toFull + " to full" : "Charging"
}

function clampPercent(value01) {
  var percent = Math.round(Number(value01) * 100)
  if (!isFinite(percent)) return 0
  return Math.min(100, Math.max(0, percent))
}

if (typeof module !== "undefined") {
  module.exports = {
    CPU_MEM_INTERVAL_MS: CPU_MEM_INTERVAL_MS,
    DISK_INTERVAL_MS: DISK_INTERVAL_MS,
    STALE_FACTOR: STALE_FACTOR,
    NET_HISTORY_CAP: NET_HISTORY_CAP,
    NET_SCALE_FLOOR: NET_SCALE_FLOOR,
    BATTERY_STATE: BATTERY_STATE,
    VIRTUAL_INTERFACE_PREFIXES: VIRTUAL_INTERFACE_PREFIXES,
    isVirtualInterface: isVirtualInterface,
    parseCpuSample: parseCpuSample,
    cpuPercent: cpuPercent,
    parseMemInfo: parseMemInfo,
    parseNetDev: parseNetDev,
    parseUptime: parseUptime,
    parseSample: parseSample,
    rateBetween: rateBetween,
    pushHistory: pushHistory,
    historyMax: historyMax,
    sparklinePoints: sparklinePoints,
    formatRate: formatRate,
    formatDuration: formatDuration,
    fetchLine: fetchLine,
    parseDiskFree: parseDiskFree,
    formatGib: formatGib,
    isStale: isStale,
    batteryDetail: batteryDetail,
    clampPercent: clampPercent
  }
}
