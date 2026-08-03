const assert = require('node:assert/strict')
const model = require('../model/NexusBrightnessModel.js')

assert.equal(model.clampBrightness(50), 50)
assert.equal(model.clampBrightness(0), 1, 'zero would blank a DDC display; 1 is the floor')
assert.equal(model.clampBrightness(150), 100)
assert.equal(model.clampBrightness('junk'), 1)
assert.equal(model.clampBrightness(49.6), 50)

assert.deepEqual(model.stateCommand(), ['omarchy-monitor-state'])
assert.deepEqual(model.setCommand('DP-3', 80),
  ['omarchy-brightness-display', '--no-osd', '--monitor', 'DP-3', '80%'])
assert.deepEqual(model.setCommand('DP-3', 999),
  ['omarchy-brightness-display', '--no-osd', '--monitor', 'DP-3', '100%'])
assert.deepEqual(model.setCommand('bad name', 50), [], 'monitor names validate before argv')
assert.deepEqual(model.setCommand('', 50), [])

// The 8-line state output: [0] percent, [5] focused monitor.
const good = model.parseMonitorState('99\neDP-1\nDP-1\n\n\nDP-3\n1.67\n[]')
assert.deepEqual(good, { available: true, percent: 99, monitor: 'DP-3' })
const unavailable = model.parseMonitorState('unavailable\n\n\n\n\nDP-3\n\n')
assert.equal(unavailable.available, false)
assert.equal(unavailable.monitor, 'DP-3')
assert.equal(model.parseMonitorState('').available, false)
assert.equal(model.parseMonitorState('50\n\n\n\n\nbad monitor\n\n').available, false,
  'an invalid monitor name can never reach a set command')

console.log('ok - nexus brightness model')
