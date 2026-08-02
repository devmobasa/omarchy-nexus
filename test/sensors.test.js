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
assert.deepEqual(rows[0], { label: 'CPU', value: '61°C' })
assert.equal(rows[1].label, 'GeForce RTX 5080')
assert.match(rows[1].value, /^1% · 4\.7\/15\.9 GiB · 38°C · 15 W$/)
assert.deepEqual(rows[2], { label: 'NVMe 1', value: '47°C' })
assert.deepEqual(rows[3], { label: 'NVMe 2', value: '29°C' })
assert.equal(rows.length, 4, 'missing readings are omitted, never rendered empty')

// A vanished sensor drops its row without shifting the others (grep -H is
// keyed by path).
const partial = model.readings(spec, model.parseLines('/sys/class/hwmon/hwmon1/temp1_input:29000'), null, catalog)
assert.equal(partial.length, 1)
assert.equal(partial[0].label, 'NVMe 2')

console.log('ok - nexus sensors model')
