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

// ---- /proc/net/dev parsing -------------------------------------------------

const netdev = 'Inter-|   Receive                                                |  Transmit\n' +
  ' face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n' +
  '    lo: 9999999    1000    0    0    0     0          0         0  9999999    1000    0    0    0     0       0          0\n' +
  '  wlan0: 5000000    4000    0    0    0     0          0         0  1000000    2000    0    0    0     0       0          0\n' +
  '   eth0: 2000000    3000    0    0    0     0          0         0   500000    1500    0    0    0     0       0          0\n'
assert.deepEqual(metrics.parseNetDev(netdev),
  { rxBytes: 7000000, txBytes: 1500000, interfaces: 2 },
  'loopback is excluded; physical interfaces sum')
assert.equal(metrics.parseNetDev('Inter-| Receive\n face |bytes\n'), null, 'header only')
assert.equal(metrics.parseNetDev(meminfo), null, 'meminfo lines can never look like interfaces')
assert.equal(metrics.parseNetDev(''), null)

// Virtual interfaces (containers, bridges, tunnels) double-count real link
// traffic and never sum.
const virt = (name) => `  ${name}: 1000    1    0    0    0     0          0         0  1000    1    0    0    0     0       0          0\n`
const virtualHeavy = netdev + virt('docker0') + virt('br-583ee8df871e') +
  virt('vetheeacea0') + virt('tun0') + virt('wg0') + virt('virbr0')
assert.deepEqual(metrics.parseNetDev(virtualHeavy),
  { rxBytes: 7000000, txBytes: 1500000, interfaces: 2 },
  'docker bridges, veths, tunnels, and wireguard are all excluded')
assert.equal(metrics.isVirtualInterface('lo'), true)
assert.equal(metrics.isVirtualInterface('eno1'), false)
assert.equal(metrics.isVirtualInterface('wlp9s0'), false)
assert.equal(metrics.isVirtualInterface('enp3s0'), false)

// ---- /proc/uptime parsing --------------------------------------------------

assert.equal(metrics.parseUptime('12345.67 89012.34\n'), 12345.67)
assert.equal(metrics.parseUptime(stat1), null, 'stat integer lines never match')
assert.equal(metrics.parseUptime(''), null)

// The sampler concatenates all four proc files into one output.
const combined = metrics.parseSample(stat1 + meminfo + netdev + '500000.10 900000.20\n')
assert.deepEqual(combined.cpu, sample1)
assert.equal(combined.mem.percent, 50)
assert.equal(combined.net.rxBytes, 7000000)
assert.equal(combined.uptimeSeconds, 500000.10)

// A missing section parses as null without poisoning the others.
const partial = metrics.parseSample(stat1 + meminfo)
assert.deepEqual(partial.cpu, sample1)
assert.equal(partial.net, null)
assert.equal(partial.uptimeSeconds, null)

// ---- byte rates ------------------------------------------------------------

assert.equal(metrics.rateBetween(1000, 0, 3000, 2000), 1000, '2000 bytes over 2 s')
assert.equal(metrics.rateBetween(3000, 0, 1000, 2000), null, 'counter reset is not a rate')
assert.equal(metrics.rateBetween(1000, 2000, 3000, 2000), null, 'zero dt is not a rate')
assert.equal(metrics.rateBetween(null, 0, 3000, 2000), null)

// ---- rolling history + sparkline math --------------------------------------

let history = []
for (let i = 1; i <= metrics.NET_HISTORY_CAP + 5; i++) {
  history = metrics.pushHistory(history, i, metrics.NET_HISTORY_CAP)
}
assert.equal(history.length, metrics.NET_HISTORY_CAP, 'history caps at NET_HISTORY_CAP')
assert.equal(history[0], 6, 'oldest samples fall off the front')
assert.equal(history[history.length - 1], metrics.NET_HISTORY_CAP + 5)
assert.deepEqual(metrics.pushHistory([1], null, 3), [1, 0], 'a null rate records as zero')
assert.deepEqual(metrics.pushHistory(null, 4, 3), [4], 'missing history starts fresh')

assert.equal(metrics.historyMax([1, 5, 2], [3, 4]), 5)
assert.equal(metrics.historyMax([], []), 0)
assert.equal(metrics.historyMax(null, [2, 'x', 9]), 9, 'invalid samples are ignored')

const points = metrics.sparklinePoints([0, 50, 100], 200, 40, 100)
assert.deepEqual(points, [{ x: 0, y: 40 }, { x: 100, y: 20 }, { x: 200, y: 0 }])
assert.deepEqual(metrics.sparklinePoints([5], 200, 40, 100), [], 'one sample draws nothing')
assert.deepEqual(metrics.sparklinePoints([1, 2], 0, 40, 100), [], 'zero width draws nothing')
assert.equal(metrics.sparklinePoints([0, 200], 100, 40, 100)[1].y, 0,
  'values above the shared max clamp to the top instead of escaping the card')

// ---- rate and duration formatting ------------------------------------------

assert.equal(metrics.formatRate(512), '512 B/s')
assert.equal(metrics.formatRate(1536), '1.5 KiB/s')
assert.equal(metrics.formatRate(2.5 * 1024 * 1024), '2.5 MiB/s')
assert.equal(metrics.formatRate(3 * 1024 * 1024 * 1024), '3.00 GiB/s')
assert.equal(metrics.formatRate(null), '—')
assert.equal(metrics.formatRate(-1), '—')

assert.equal(metrics.formatDuration(2 * 3600 + 13 * 60), '2 h 13 m')
assert.equal(metrics.formatDuration(3 * 86400 + 4 * 3600 + 30 * 60), '3 d 4 h')
assert.equal(metrics.formatDuration(2 * 86400 + 5 * 60), '2 d', 'minutes drop once days show')
assert.equal(metrics.formatDuration(45 * 60), '45 m')
assert.equal(metrics.formatDuration(30), '<1 m')
assert.equal(metrics.formatDuration(0), '')
assert.equal(metrics.formatDuration('x'), '')

// ---- fetch line ------------------------------------------------------------

assert.equal(metrics.fetchLine('arch', '7.1.5-arch1-2', 3 * 86400 + 4 * 3600),
  'arch · 7.1.5-arch1-2 · up 3 d 4 h')
assert.equal(metrics.fetchLine('', '7.1.5', 60), '7.1.5 · up 1 m', 'missing parts drop out')
assert.equal(metrics.fetchLine('  ', null, null), '', 'nothing renders as nothing')

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

// Time estimates render when UPower knows them; 0 means unknown and falls
// back to the bare state.
assert.equal(metrics.batteryDetail(true, true, 80, 2 * 3600 + 13 * 60),
  'On battery — 2 h 13 m left')
assert.equal(metrics.batteryDetail(true, true, 80, 0), 'On battery')
assert.equal(metrics.batteryDetail(true, false, 80, 0, 45 * 60), 'Charging — 45 m to full')
assert.equal(metrics.batteryDetail(true, false, 80, 0, 0), 'Charging')
assert.equal(metrics.batteryDetail(true, false, 100, 0, 45 * 60), 'Charged',
  'a full battery never shows a countdown')

assert.equal(metrics.clampPercent(0.834), 83)
assert.equal(metrics.clampPercent(1.5), 100)
assert.equal(metrics.clampPercent(-1), 0)
assert.equal(metrics.clampPercent('x'), 0)

console.log('ok - nexus metrics model')
