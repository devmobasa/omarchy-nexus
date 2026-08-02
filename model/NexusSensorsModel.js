// Hardware sensors model for Omarchy Nexus. Loaded by both the QML sampler
// and the Node test harness, so it must stay dependency-free.
//
// Discovery runs once per open: one find+grep process emits `path:value`
// lines for every hwmon name/temp/fan file and the DRM GPU identity files.
// Sampling then greps exactly the selected paths — `grep -H .` is
// self-labeling, so a sensor that vanishes cannot silently shift later
// readings the way bare `cat` does. hwmon indices are probe-order and never
// hardcoded. Units: temp*_input millidegrees C, fan*_input RPM,
// power1_input microwatts; amdgpu vram files are bytes; nvidia-smi (the
// only window into an NVIDIA card) reports MiB / percent / degrees / watts.

var SENSOR_INTERVAL_MS = 5000

function discoveryCommand() {
  return ["find", "-L", "/sys/class/hwmon", "/sys/class/drm", "-maxdepth", "3",
    "(", "-name", "name", "-o", "-name", "temp*_input", "-o", "-name", "temp*_label",
    "-o", "-name", "fan*_input", "-o", "-name", "fan*_label",
    "-o", "-name", "boot_vga", "-o", "-name", "vendor",
    "-o", "-name", "gpu_busy_percent", "-o", "-name", "mem_info_vram_used",
    "-o", "-name", "mem_info_vram_total", ")",
    "-exec", "grep", "-H", ".", "{}", "+"]
}

function parseLines(text) {
  var lines = String(text == null ? "" : text).split("\n")
  var map = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var colon = line.indexOf(":")
    if (colon <= 0) continue
    map[line.slice(0, colon)] = line.slice(colon + 1)
  }
  return map
}

var HWMON_RE = /^\/sys\/class\/hwmon\/(hwmon\d+)\/(name|(?:temp|fan)\d+_(?:input|label))$/
var DRM_RE = /^\/sys\/class\/drm\/(card\d+)\/device\/(boot_vga|vendor|gpu_busy_percent|mem_info_vram_used|mem_info_vram_total)$/

// Build the machine catalog from discovery output.
function parseDiscovery(text) {
  var values = parseLines(text)
  var hwmons = {}
  var cards = {}
  for (var path in values) {
    var hwmonMatch = HWMON_RE.exec(path)
    if (hwmonMatch) {
      var hwmonId = hwmonMatch[1]
      if (!hwmons[hwmonId]) hwmons[hwmonId] = { name: "", temps: {}, fans: {} }
      var file = hwmonMatch[2]
      if (file === "name") {
        hwmons[hwmonId].name = values[path].trim()
      } else {
        var sensorMatch = /^(temp|fan)(\d+)_(input|label)$/.exec(file)
        var bucket = sensorMatch[1] === "temp" ? hwmons[hwmonId].temps : hwmons[hwmonId].fans
        var index = sensorMatch[2]
        if (!bucket[index]) bucket[index] = {}
        if (sensorMatch[3] === "input")
          bucket[index].inputPath = path
        else
          bucket[index].label = values[path].trim()
      }
      continue
    }
    var drmMatch = DRM_RE.exec(path)
    if (drmMatch) {
      var card = drmMatch[1]
      if (!cards[card]) cards[card] = {}
      cards[card][drmMatch[2]] = values[path].trim()
    }
  }
  return { hwmons: hwmons, cards: cards }
}

function tempsOf(hwmon) {
  var temps = []
  for (var index in hwmon.temps) {
    var temp = hwmon.temps[index]
    if (temp.inputPath) temps.push({ path: temp.inputPath, label: temp.label || ("temp" + index) })
  }
  temps.sort(function (a, b) { return a.path < b.path ? -1 : 1 })
  return temps
}

// Choose what the card shows. CPU: k10temp Tctl (AMD) or coretemp Package
// (Intel). NVMe: every Composite. Fans: every labeled fan (this reference
// machine has none — the row hides, never renders 0 RPM). GPU: the boot_vga
// card; NVIDIA (0x10de) has no sysfs telemetry and needs nvidia-smi, AMD
// (0x1002) reads busy/vram from sysfs and its edge temp from the amdgpu
// hwmon.
function selectSensors(catalog) {
  var spec = { cpu: null, nvme: [], fans: [], gpu: null }
  var nvmeIndex = 1
  for (var hwmonId in catalog.hwmons) {
    var hwmon = catalog.hwmons[hwmonId]
    var temps = tempsOf(hwmon)
    if (hwmon.name === "k10temp" || hwmon.name === "coretemp") {
      var pick = null
      for (var i = 0; i < temps.length; i++) {
        if (temps[i].label === "Tctl" || /^Package/.test(temps[i].label)) { pick = temps[i]; break }
      }
      if (!pick && temps.length > 0) pick = temps[0]
      if (pick) spec.cpu = { path: pick.path }
    } else if (hwmon.name === "nvme") {
      for (var j = 0; j < temps.length; j++) {
        if (temps[j].label === "Composite") {
          spec.nvme.push({ path: temps[j].path, label: "NVMe " + nvmeIndex })
          nvmeIndex += 1
        }
      }
    }
    for (var fanIndex in hwmon.fans) {
      var fan = hwmon.fans[fanIndex]
      if (fan.inputPath)
        spec.fans.push({ path: fan.inputPath, label: fan.label || (hwmon.name + " fan" + fanIndex) })
    }
  }

  var displayCard = null
  for (var cardId in catalog.cards) {
    var card = catalog.cards[cardId]
    if (card.boot_vga === "1") { displayCard = card; break }
  }
  if (!displayCard) {
    for (var anyId in catalog.cards) { displayCard = catalog.cards[anyId]; break }
  }
  if (displayCard) {
    if (displayCard.vendor === "0x10de") {
      spec.gpu = { kind: "nvidia" }
    } else if (displayCard.vendor === "0x1002" && displayCard.gpu_busy_percent !== undefined) {
      var amdTempPath = null
      for (var amdId in catalog.hwmons) {
        if (catalog.hwmons[amdId].name === "amdgpu") {
          var amdTemps = tempsOf(catalog.hwmons[amdId])
          for (var t = 0; t < amdTemps.length; t++) {
            if (amdTemps[t].label === "edge") { amdTempPath = amdTemps[t].path; break }
          }
          if (!amdTempPath && amdTemps.length > 0) amdTempPath = amdTemps[0].path
        }
      }
      spec.gpu = { kind: "amd", tempPath: amdTempPath }
    }
  }
  return spec
}

// AMD GPU sysfs paths ride the sample grep; they are keyed by path, so the
// card directory must be remembered in the spec... they are discovered
// under /sys/class/drm and re-read each sample via their absolute paths.
function samplePaths(spec, catalog) {
  var paths = []
  if (spec.cpu) paths.push(spec.cpu.path)
  for (var i = 0; i < spec.nvme.length; i++) paths.push(spec.nvme[i].path)
  for (var j = 0; j < spec.fans.length; j++) paths.push(spec.fans[j].path)
  if (spec.gpu && spec.gpu.kind === "amd") {
    for (var cardId in catalog.cards) {
      var card = catalog.cards[cardId]
      if (card.vendor === "0x1002" && card.gpu_busy_percent !== undefined) {
        paths.push("/sys/class/drm/" + cardId + "/device/gpu_busy_percent")
        paths.push("/sys/class/drm/" + cardId + "/device/mem_info_vram_used")
        paths.push("/sys/class/drm/" + cardId + "/device/mem_info_vram_total")
        break
      }
    }
    if (spec.gpu.tempPath) paths.push(spec.gpu.tempPath)
  }
  return paths
}

function sampleCommand(paths) {
  return ["grep", "-H", "."].concat(paths)
}

function nvidiaCommand() {
  return ["nvidia-smi",
    "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
    "--format=csv,noheader,nounits"]
}

function parseNvidiaSmi(text) {
  var line = String(text == null ? "" : text).split("\n")[0]
  var parts = line.split(",")
  if (parts.length < 6) return null
  var name = parts[0].trim()
  var util = Number(parts[1])
  var usedMiB = Number(parts[2])
  var totalMiB = Number(parts[3])
  var temp = Number(parts[4])
  var watts = Number(parts[5])
  if (!isFinite(util) || !isFinite(usedMiB) || !isFinite(totalMiB)) return null
  return {
    name: name.replace(/^NVIDIA /, ""),
    utilPercent: Math.min(100, Math.max(0, Math.round(util))),
    vramUsedMiB: usedMiB,
    vramTotalMiB: totalMiB,
    tempC: isFinite(temp) ? Math.round(temp) : null,
    powerW: isFinite(watts) ? Math.round(watts) : null
  }
}

function milliToC(value) {
  var n = Number(value)
  return isFinite(n) ? Math.round(n / 1000) : null
}

// Assemble display rows from one sample. Every row is {label, value}; rows
// with no reading are omitted rather than rendered empty.
function readings(spec, sampleMap, nvidia, catalog) {
  var rows = []
  if (spec.cpu && sampleMap[spec.cpu.path] !== undefined) {
    var cpuTemp = milliToC(sampleMap[spec.cpu.path])
    if (cpuTemp !== null) rows.push({ label: "CPU", value: cpuTemp + "°C" })
  }
  if (spec.gpu && spec.gpu.kind === "nvidia" && nvidia) {
    var gpuParts = [nvidia.utilPercent + "%"]
    if (nvidia.vramTotalMiB > 0)
      gpuParts.push((nvidia.vramUsedMiB / 1024).toFixed(1) + "/" + (nvidia.vramTotalMiB / 1024).toFixed(1) + " GiB")
    if (nvidia.tempC !== null) gpuParts.push(nvidia.tempC + "°C")
    if (nvidia.powerW !== null) gpuParts.push(nvidia.powerW + " W")
    rows.push({ label: nvidia.name || "GPU", value: gpuParts.join(" · ") })
  } else if (spec.gpu && spec.gpu.kind === "amd") {
    var busyPath = null
    var usedPath = null
    var totalPath = null
    for (var cardId in catalog.cards) {
      var card = catalog.cards[cardId]
      if (card.vendor === "0x1002" && card.gpu_busy_percent !== undefined) {
        busyPath = "/sys/class/drm/" + cardId + "/device/gpu_busy_percent"
        usedPath = "/sys/class/drm/" + cardId + "/device/mem_info_vram_used"
        totalPath = "/sys/class/drm/" + cardId + "/device/mem_info_vram_total"
        break
      }
    }
    var amdParts = []
    if (busyPath && sampleMap[busyPath] !== undefined) amdParts.push(Number(sampleMap[busyPath]) + "%")
    if (usedPath && totalPath && sampleMap[usedPath] !== undefined && sampleMap[totalPath] !== undefined) {
      var gib = 1024 * 1024 * 1024
      amdParts.push((Number(sampleMap[usedPath]) / gib).toFixed(1) + "/"
        + (Number(sampleMap[totalPath]) / gib).toFixed(1) + " GiB")
    }
    if (spec.gpu.tempPath && sampleMap[spec.gpu.tempPath] !== undefined) {
      var amdTemp = milliToC(sampleMap[spec.gpu.tempPath])
      if (amdTemp !== null) amdParts.push(amdTemp + "°C")
    }
    if (amdParts.length > 0) rows.push({ label: "GPU", value: amdParts.join(" · ") })
  }
  for (var i = 0; i < spec.nvme.length; i++) {
    var nvmeTemp = sampleMap[spec.nvme[i].path] !== undefined
      ? milliToC(sampleMap[spec.nvme[i].path]) : null
    if (nvmeTemp !== null) rows.push({ label: spec.nvme[i].label, value: nvmeTemp + "°C" })
  }
  for (var j = 0; j < spec.fans.length; j++) {
    var rpm = sampleMap[spec.fans[j].path] !== undefined
      ? Number(sampleMap[spec.fans[j].path]) : null
    if (rpm !== null && isFinite(rpm)) rows.push({ label: spec.fans[j].label, value: rpm + " RPM" })
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    SENSOR_INTERVAL_MS: SENSOR_INTERVAL_MS,
    discoveryCommand: discoveryCommand,
    parseLines: parseLines,
    parseDiscovery: parseDiscovery,
    selectSensors: selectSensors,
    samplePaths: samplePaths,
    sampleCommand: sampleCommand,
    nvidiaCommand: nvidiaCommand,
    parseNvidiaSmi: parseNvidiaSmi,
    readings: readings
  }
}
