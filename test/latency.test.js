const assert = require('node:assert/strict')
const model = require('../model/NexusLatencyModel.js')

// Route parsing takes the first default route's gateway; anything else is
// "no router" (VPN-only tables, empty arrays, junk).
assert.equal(model.parseDefaultRoute(JSON.stringify([
  { dst: 'default', gateway: '192.168.50.1', dev: 'eno1' }
])), '192.168.50.1')
assert.equal(model.parseDefaultRoute('[]'), '')
assert.equal(model.parseDefaultRoute('junk'), '')
assert.equal(model.parseDefaultRoute(JSON.stringify([{ dst: 'default', dev: 'tun0' }])), '',
  'a gatewayless route yields no router leg')
assert.equal(model.parseDefaultRoute(JSON.stringify([{ gateway: 'evil; rm -rf' }])), '')

assert.ok(model.validHost('1.1.1.1'))
assert.ok(!model.validHost('1.1.1.256'))
assert.ok(!model.validHost('router.local'), 'only literal IPv4 reaches argv')
assert.deepEqual(model.pingCommand('192.168.50.1'), ['ping', '-n', '-c', '1', '-W', '1', '192.168.50.1'])
assert.deepEqual(model.pingCommand('bad host'), [])

// Ping output: the reply's time token, absent on timeout.
assert.equal(model.parsePing('64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=34.8 ms'), 34.8)
assert.equal(model.parsePing('1 packets transmitted, 0 received, 100% packet loss'), null)
assert.equal(model.parsePing(''), null)
assert.equal(model.parsePing('time=abc ms'), null)

// Rings: nulls count as losses; the window slides.
let ring = []
ring = model.pushSample(ring, 10)
ring = model.pushSample(ring, null)
ring = model.pushSample(ring, 20)
assert.equal(model.averageLatency(ring), 15, 'losses are excluded from the average')
for (let i = 0; i < 40; i++) ring = model.pushSample(ring, 5)
assert.equal(ring.length, model.HISTORY_WINDOW)
assert.equal(model.averageLatency(ring), 5)

// Display rules: -- before any sample, timeout when the window is losses.
assert.equal(model.formatLatency([]), '--')
assert.equal(model.formatLatency([null, null]), 'timeout')
assert.equal(model.formatLatency([0.42]), '0.4 ms')
assert.equal(model.formatLatency([34.8]), '35 ms')
assert.equal(model.formatLatency([9.94]), '9.9 ms')

console.log('ok - nexus latency model')
