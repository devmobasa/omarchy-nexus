const assert = require('node:assert/strict')
const metrics = require('../model/NexusMetricsModel.js')

// ---- /proc/stat parsing ----------------------------------------------------

const stat1 = 'cpu  1000 50 300 8000 200 10 40 0 0 0\ncpu0 500 25 150 4000 100 5 20 0 0 0\n'
const sample1 = metrics.parseCpuSample(stat1)
assert.deepEqual(sample1, { total: 9600, idle: 8200 }, 'idle includes iowait; total sums every column')

// "cpu0" must never match the aggregate line; malformed input returns null.
assert.equal(metrics.parseCpuSample('cpu0 1 2 3 4 5\n'), null)
assert.equal(metrics.parseCpuSample('cpu  1 2 3\n'), null, 'too few columns')
assert.equal(metrics.parseCpuSample('cpu  1 2 x 4 5\n'), null, 'non-numeric column')
assert.equal(metrics.parseCpuSample(''), null)
assert.equal(metrics.parseCpuSample(null), null)

// ---- cpu delta percentage --------------------------------------------------

const sample2 = { total: sample1.total + 1000, idle: sample1.idle + 600 }
assert.equal(metrics.cpuPercent(sample1, sample2), 40, '400 busy of 1000 total ticks')
assert.equal(metrics.cpuPercent(null, sample2), null, 'needs two samples')
assert.equal(metrics.cpuPercent(sample1, sample1), null, 'zero delta is not a reading')
assert.equal(metrics.cpuPercent(sample2, sample1), null, 'counter reset is not a reading')

// ---- /proc/meminfo parsing -------------------------------------------------

const meminfo = 'MemTotal:       16000000 kB\nMemFree:         2000000 kB\nMemAvailable:    8000000 kB\nBuffers:          500000 kB\n'
assert.deepEqual(metrics.parseMemInfo(meminfo),
  { totalKb: 16000000, availableKb: 8000000, percent: 50 },
  'used percent derives from MemAvailable')
assert.equal(metrics.parseMemInfo('MemTotal: 100 kB\n'), null, 'missing MemAvailable')
assert.equal(metrics.parseMemInfo('MemTotal: 0 kB\nMemAvailable: 0 kB\n'), null, 'zero total')
assert.equal(metrics.parseMemInfo('MemTotal: 100 kB\nMemAvailable: 200 kB\n'), null,
  'available above total is malformed')

// The sampler concatenates both proc files into one output.
const combined = metrics.parseStatAndMem(stat1 + meminfo)
assert.deepEqual(combined.cpu, sample1)
assert.equal(combined.mem.percent, 50)

// ---- df parsing ------------------------------------------------------------

const df = 'Filesystem     1024-blocks      Used Available Capacity Mounted on\n' +
  '/dev/nvme0n1p2   498443264 249221632 224198912      53% /\n'
assert.deepEqual(metrics.parseDiskFree(df), { percent: 53, availableKb: 224198912, mount: '/' })
assert.equal(metrics.parseDiskFree('Filesystem\n'), null)
assert.equal(metrics.parseDiskFree('h\n/dev/sda1 1 1 1 banana% /\n'), null, 'non-numeric capacity')
assert.equal(metrics.parseDiskFree(''), null)

assert.equal(metrics.formatGib(224198912), '213.8 GiB')
assert.equal(metrics.formatGib(-5), '')
assert.equal(metrics.formatGib('x'), '')

// ---- staleness -------------------------------------------------------------

assert.equal(metrics.isStale(0, 1000, 2000), true, 'never sampled is stale')
assert.equal(metrics.isStale(1000, 2000, 2000), false, 'fresh reading')
assert.equal(metrics.isStale(1000, 1000 + 2000 * metrics.STALE_FACTOR + 1, 2000), true,
  'older than STALE_FACTOR x cadence is stale')

// ---- battery ---------------------------------------------------------------

assert.equal(metrics.batteryDetail(false, false, 0), 'No battery')
assert.equal(metrics.batteryDetail(true, true, 80), 'On battery')
assert.equal(metrics.batteryDetail(true, false, 80), 'Charging')
assert.equal(metrics.batteryDetail(true, false, 100), 'Charged')

assert.equal(metrics.clampPercent(0.834), 83)
assert.equal(metrics.clampPercent(1.5), 100)
assert.equal(metrics.clampPercent(-1), 0)
assert.equal(metrics.clampPercent('x'), 0)

console.log('ok - nexus metrics model')
