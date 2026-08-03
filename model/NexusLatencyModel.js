// Split-path latency for the Network card: the LAN router leg answers "is
// my local network fine", the internet leg answers "is my ISP fine".
// Loaded by both QML and the Node test harness; dependency-free.
//
// The router is the PHYSICAL default gateway (`ip -j route show default`),
// deliberately not `route get <probe>` — with a VPN up the probe route
// resolves to the tunnel next hop, which is the internet leg's business.
// The internet probe traverses whatever route real traffic takes.

var INTERNET_PROBE = "1.1.1.1"
var PING_INTERVAL_MS = 3000
var HISTORY_WINDOW = 24
var AVERAGE_WINDOW = 5

function routeCommand() {
  return ["ip", "-j", "route", "show", "default"]
}

var IPV4_RE = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/

function validHost(host) {
  var match = IPV4_RE.exec(String(host == null ? "" : host))
  if (!match) return false
  for (var i = 1; i <= 4; i++) {
    if (Number(match[i]) > 255) return false
  }
  return true
}

// The gateway of the first default route, or "" (no route, VPN-only
// setups where the default lives in another table, parse failures).
function parseDefaultRoute(text) {
  var parsed = null
  if (typeof text === "string" && text.length > 0) {
    try { parsed = JSON.parse(text) } catch (error) { parsed = null }
  }
  if (!Array.isArray(parsed)) return ""
  for (var i = 0; i < parsed.length; i++) {
    var route = parsed[i]
    if (route && typeof route.gateway === "string" && validHost(route.gateway)) return route.gateway
  }
  return ""
}

// One packet, one-second reply timeout: worst case ~1 s wall, well inside
// the poll interval. LC_ALL=C pins the decimal separator (set on the
// Process environment).
function pingCommand(host) {
  if (!validHost(host)) return []
  return ["ping", "-n", "-c", "1", "-W", "1", host]
}

// The reply line carries `time=NN.N ms`; a timeout has no such token, so
// null means lost, not zero.
function parsePing(text) {
  var match = /time[=<]([0-9.]+)\s*ms/.exec(String(text == null ? "" : text))
  if (!match) return null
  var value = Number(match[1])
  return isFinite(value) && value >= 0 ? value : null
}

// Rolling sample ring, nulls included (a null is a lost packet).
function pushSample(ring, value) {
  var source = ring && typeof ring.length === "number" ? ring : []
  var next = source.concat([typeof value === "number" && isFinite(value) ? value : null])
  return next.length > HISTORY_WINDOW ? next.slice(next.length - HISTORY_WINDOW) : next
}

// Average of the last AVERAGE_WINDOW non-null samples; -1 when the recent
// window is all losses (distinct from "no samples yet" = empty ring).
function averageLatency(ring) {
  var list = ring && typeof ring.length === "number" ? ring : []
  var sum = 0
  var count = 0
  for (var i = list.length - 1; i >= 0 && count < AVERAGE_WINDOW; i--) {
    if (typeof list[i] === "number" && isFinite(list[i])) { sum += list[i]; count++ }
  }
  if (count === 0) return -1
  return sum / count
}

// "--" before the first sample, "timeout" when the window is all losses,
// otherwise one decimal under 10 ms and whole numbers above.
function formatLatency(ring) {
  var list = ring && typeof ring.length === "number" ? ring : []
  if (list.length === 0) return "--"
  var average = averageLatency(list)
  if (average < 0) return "timeout"
  return (average < 10 ? average.toFixed(1) : String(Math.round(average))) + " ms"
}

if (typeof module !== "undefined") {
  module.exports = {
    INTERNET_PROBE: INTERNET_PROBE,
    PING_INTERVAL_MS: PING_INTERVAL_MS,
    HISTORY_WINDOW: HISTORY_WINDOW,
    AVERAGE_WINDOW: AVERAGE_WINDOW,
    routeCommand: routeCommand,
    validHost: validHost,
    parseDefaultRoute: parseDefaultRoute,
    pingCommand: pingCommand,
    parsePing: parsePing,
    pushSample: pushSample,
    averageLatency: averageLatency,
    formatLatency: formatLatency
  }
}
