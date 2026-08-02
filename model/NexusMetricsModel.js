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

// Parse the aggregate "cpu " line of /proc/stat into cumulative tick counters.
// idle time includes iowait; total is the sum of every column.
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
      total += value
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

// The sampler reads /proc/stat and /proc/meminfo in one bounded process; the
// concatenated output parses as one text.
function parseStatAndMem(text) {
  return { cpu: parseCpuSample(text), mem: parseMemInfo(text) }
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

// Battery detail line from reactive UPower state; presence decides between a
// reading and the normal desktop no-battery fallback.
function batteryDetail(present, onBattery, percent) {
  if (!present) return "No battery"
  if (!onBattery) return Number(percent) >= 100 ? "Charged" : "Charging"
  return "On battery"
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
    parseCpuSample: parseCpuSample,
    cpuPercent: cpuPercent,
    parseMemInfo: parseMemInfo,
    parseStatAndMem: parseStatAndMem,
    parseDiskFree: parseDiskFree,
    formatGib: formatGib,
    isStale: isStale,
    batteryDetail: batteryDetail,
    clampPercent: clampPercent
  }
}
