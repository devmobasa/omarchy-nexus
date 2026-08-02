const assert = require('node:assert/strict')
const model = require('../model/NexusCavaModel.js')

const config = model.buildConfig()
assert.match(config, /bars = 24/)
assert.match(config, /method = raw/)
assert.match(config, /data_format = ascii/)
assert.match(config, /ascii_max_range = 100/)
assert.match(config, /bar_delimiter = 59/)
assert.match(config, /frame_delimiter = 10/)
assert.match(config, /sleep_timer = 3/, 'silence stops the FFT')
assert.ok(config.endsWith('\n'))

assert.equal(model.confPath('/state/dir'), '/state/dir/nexus-cava.conf')
assert.deepEqual(model.cavaCommand('/p/c.conf'), ['cava', '-p', '/p/c.conf'])

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

assert.equal(model.silentFrame().length, 24)
assert.equal(model.silentFrame()[7], 0)

console.log('ok - nexus cava model')
