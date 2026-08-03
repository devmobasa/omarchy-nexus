const assert = require('node:assert/strict')
const model = require('../model/NexusCavaModel.js')

const config = model.buildConfig()
assert.match(config, /bars = 24/)
assert.match(config, /method = raw/)
assert.match(config, /raw_target = \/dev\/stdout/)
assert.match(config, /data_format = ascii/)
assert.match(config, /ascii_max_range = 100/)
assert.match(config, /bar_delimiter = 59/)
assert.match(config, /frame_delimiter = 10/)
assert.match(config, /channels = mono/, 'mono is pinned so exactly 24 fields arrive')
assert.match(config, /sleep_timer = 0/, 'the isPlaying gate owns idling, not cava')
assert.match(config, /method = pipewire/, 'input pinned to pipewire, no ALSA fallback surprise')
assert.match(config, /noise_reduction = 20/)
assert.ok(config.endsWith('\n'))

// Config over stdin: no file path anywhere in the command.
assert.deepEqual(model.cavaCommand(), ['cava', '-p', '/dev/stdin'])
assert.equal(model.confPath, undefined, 'the on-disk config path is gone')

// Retry policy: 500 ms, 1 s, then the budget is spent.
assert.equal(model.retryDelay(1), 500)
assert.equal(model.retryDelay(2), 1000)
assert.equal(model.retryDelay(3), -1, 'the third failure is terminal')
assert.equal(model.retryDelay(99), -1)
assert.equal(model.retryDelay(0), 500, 'garbage counts floor to the first delay')
assert.equal(model.MAX_RETRIES, 3)
assert.ok(model.STATES.RUNNING === 'running' && model.STATES.FAILED === 'failed')

// A frame is 24 delimited ints with a trailing delimiter.
const frame = model.parseFrame(Array.from({ length: 24 }, (_, i) => i * 4).join(';') + ';')
assert.equal(frame.length, 24)
assert.equal(frame[0], 0)
assert.equal(frame[23], 0.92)
assert.equal(model.parseFrame('100;'.repeat(24))[0], 1)
assert.equal(model.parseFrame('200;'.repeat(24))[0], 1, 'values clamp to the range')

assert.equal(model.parseFrame('1;2;3'), null, 'short frames are rejected')
assert.equal(model.parseFrame('a;'.repeat(24)), null)
assert.equal(model.parseFrame(''), null)
assert.equal(model.parseFrame(null), null)
assert.equal(model.parseFrame('1;'.repeat(3000)), null, 'oversized lines are dropped whole')

assert.equal(model.silentFrame().length, 24)
assert.equal(model.silentFrame()[7], 0)

console.log('ok - nexus cava model')
