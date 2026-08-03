const assert = require('node:assert/strict')
const model = require('../model/NexusSensorsModel.js')

// Discovery fixture mirroring the reference machine: AMD k10temp, two NVMe
// hwmons with non-uniform temp indices, an amdgpu iGPU, an empty asus
// hwmon, and a hybrid GPU pair where the NVIDIA card is boot_vga.
const discovery = [
  '/sys/class/hwmon/hwmon3/name:k10temp',
  '/sys/class/hwmon/hwmon3/temp1_input:61375',
  '/sys/class/hwmon/hwmon3/temp1_label:Tctl',
  '/sys/class/hwmon/hwmon3/temp3_input:45500',
  '/sys/class/hwmon/hwmon3/temp3_label:Tccd1',
  '/sys/class/hwmon/hwmon0/name:nvme',
  '/sys/class/hwmon/hwmon0/temp1_input:46850',
  '/sys/class/hwmon/hwmon0/temp1_label:Composite',
  '/sys/class/hwmon/hwmon0/temp2_input:47000',
  '/sys/class/hwmon/hwmon0/temp2_label:Sensor 1',
  '/sys/class/hwmon/hwmon1/name:nvme',
  '/sys/class/hwmon/hwmon1/temp1_input:28850',
  '/sys/class/hwmon/hwmon1/temp1_label:Composite',
  '/sys/class/hwmon/hwmon2/name:amdgpu',
  '/sys/class/hwmon/hwmon2/temp1_input:47000',
  '/sys/class/hwmon/hwmon2/temp1_label:edge',
  '/sys/class/hwmon/hwmon4/name:asus',
  '/sys/class/drm/card0/device/vendor:0x1002',
  '/sys/class/drm/card0/device/boot_vga:0',
  '/sys/class/drm/card0/device/gpu_busy_percent:0',
  '/sys/class/drm/card0/device/mem_info_vram_used:16736256',
  '/sys/class/drm/card0/device/mem_info_vram_total:536870912',
  '/sys/class/drm/card1/device/vendor:0x10de',
  '/sys/class/drm/card1/device/boot_vga:1'
].join('\n')

const catalog = model.parseDiscovery(discovery)
assert.equal(catalog.hwmons.hwmon3.name, 'k10temp')
assert.equal(Object.keys(catalog.hwmons.hwmon3.temps).length, 2, 'non-contiguous indices survive')
assert.equal(catalog.cards.card1.vendor, '0x10de')

const spec = model.selectSensors(catalog)
assert.equal(spec.cpu.path, '/sys/class/hwmon/hwmon3/temp1_input', 'Tctl wins for k10temp')
assert.equal(spec.nvme.length, 2, 'only Composite per NVMe, never Sensor N')
assert.equal(spec.fans.length, 0, 'no fans discovered means no fan rows')
assert.equal(spec.gpu.kind, 'nvidia', 'the boot_vga card decides — the idle iGPU never masquerades as the GPU')

const paths = model.samplePaths(spec, catalog)
assert.ok(paths.indexOf(spec.cpu.path) !== -1)
assert.equal(paths.length, 3, 'nvidia GPUs add no sysfs sample paths')
assert.deepEqual(model.sampleCommand(['/a', '/b']), ['grep', '-H', '.', '/a', '/b'])

// AMD-primary variant: swap boot_vga.
const amdCatalog = model.parseDiscovery(discovery
  .replace('card1/device/boot_vga:1', 'card1/device/boot_vga:0')
  .replace('card0/device/boot_vga:0', 'card0/device/boot_vga:1'))
const amdSpec = model.selectSensors(amdCatalog)
assert.equal(amdSpec.gpu.kind, 'amd')
assert.equal(amdSpec.gpu.tempPath, '/sys/class/hwmon/hwmon2/temp1_input', 'edge temp attached')
assert.ok(model.samplePaths(amdSpec, amdCatalog).indexOf('/sys/class/drm/card0/device/gpu_busy_percent') !== -1)

// ---- sampling ---------------------------------------------------------------

const sample = model.parseLines([
  '/sys/class/hwmon/hwmon3/temp1_input:61375',
  '/sys/class/hwmon/hwmon0/temp1_input:46850',
  '/sys/class/hwmon/hwmon1/temp1_input:28850'
].join('\n'))
const nvidia = model.parseNvidiaSmi('NVIDIA GeForce RTX 5080, 1, 4821, 16303, 38, 14.64\n')
assert.equal(nvidia.name, 'GeForce RTX 5080')
assert.equal(nvidia.utilPercent, 1)
assert.equal(nvidia.tempC, 38)
assert.equal(nvidia.powerW, 15)
assert.equal(model.parseNvidiaSmi('garbage'), null)
assert.equal(model.parseNvidiaSmi(''), null)

const rows = model.readings(spec, sample, nvidia, catalog)
assert.equal(rows[0].label, 'CPU')
assert.equal(rows[0].value, '61°C')
assert.equal(rows[0].severity, '', 'no declared limit degrades to plain temperature')
assert.equal(rows[1].label, 'GeForce RTX 5080')
assert.match(rows[1].value, /^1% · 4\.7\/15\.9 GiB · 38°C · 15 W$/)
assert.equal(rows[2].label, 'NVMe 1')
assert.equal(rows[2].value, '47°C')
assert.equal(rows[3].label, 'NVMe 2')
assert.equal(rows[3].value, '29°C')
assert.equal(rows.length, 4, 'missing readings are omitted, never rendered empty')

// A vanished sensor drops its row without shifting the others (grep -H is
// keyed by path).
const partial = model.readings(spec, model.parseLines('/sys/class/hwmon/hwmon1/temp1_input:29000'), null, catalog)
assert.equal(partial.length, 1)
assert.equal(partial[0].label, 'NVMe 2')

// ---- hardware-declared limits -----------------------------------------------

// Sentinels and junk never become limits; real values round from milli-C.
assert.equal(model.clampLimit('81850'), 82)
assert.equal(model.clampLimit('65261850'), null, 'the NVMe no-limit sentinel is rejected')
assert.equal(model.clampLimit('-273150'), null)
assert.equal(model.clampLimit('junk'), null)
assert.equal(model.clampLimit('150000'), 150)
assert.equal(model.clampLimit('151000'), null)

assert.equal(model.limitSeverity(84, 82, 85), 'warn')
assert.equal(model.limitSeverity(85, 82, 85), 'crit')
assert.equal(model.limitSeverity(50, 82, 85), '')
assert.equal(model.limitSeverity(90, null, null), '', 'no limits, no severity')
assert.equal(model.limitSeverity(null, 82, 85), '')

// Limits are captured at discovery, per index; spd5118 DIMMs select as a
// memory family and render as one hottest-module row.
const limitsCatalog = model.parseDiscovery([
  '/sys/class/hwmon/hwmon0/name:nvme',
  '/sys/class/hwmon/hwmon0/temp1_input:49850',
  '/sys/class/hwmon/hwmon0/temp1_label:Composite',
  '/sys/class/hwmon/hwmon0/temp1_max:81850',
  '/sys/class/hwmon/hwmon0/temp1_crit:84850',
  '/sys/class/hwmon/hwmon5/name:spd5118',
  '/sys/class/hwmon/hwmon5/temp1_input:50750',
  '/sys/class/hwmon/hwmon5/temp1_max:55000',
  '/sys/class/hwmon/hwmon5/temp1_crit:85000',
  '/sys/class/hwmon/hwmon6/name:spd5118',
  '/sys/class/hwmon/hwmon6/temp1_input:51500',
  '/sys/class/hwmon/hwmon6/temp1_max:55000',
  '/sys/class/hwmon/hwmon6/temp1_crit:85000'
].join('\n'))
const limitsSpec = model.selectSensors(limitsCatalog)
assert.equal(limitsSpec.nvme[0].maxC, 82)
assert.equal(limitsSpec.nvme[0].critC, 85)
assert.equal(limitsSpec.dimms.length, 2)
const limitsSample = model.parseLines([
  '/sys/class/hwmon/hwmon0/temp1_input:83000',
  '/sys/class/hwmon/hwmon5/temp1_input:50750',
  '/sys/class/hwmon/hwmon6/temp1_input:56500'
].join('\n'))
const limitRows = model.readings(limitsSpec, limitsSample, null, limitsCatalog)
assert.equal(limitRows[0].label, 'NVMe 1')
assert.equal(limitRows[0].severity, 'warn', '83 sits between max 82 and crit 85')
const memoryRow = limitRows.find(r => r.label === 'Memory')
assert.equal(memoryRow.tempC, 57, 'the hottest DIMM wins the row')
assert.equal(memoryRow.severity, 'warn', '57 is past the 55 max but under the 85 crit')

console.log('ok - nexus sensors model')
