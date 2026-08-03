const assert = require('node:assert/strict')
const model = require('../model/NexusAudioModel.js')

function near(actual, expected) {
  assert.ok(Math.abs(actual - expected) < 0.001, `${actual} !~ ${expected}`)
}

// Reference vectors: Quickshell reports cbrt(linear peak); the cube
// recovers amplitude and the meter maps -55..0 dBFS linearly.
near(model.peakToMeter(1), 1)
near(model.peakToMeter(0.9), 0.9501)
near(model.peakToMeter(0.75), 0.8637)
near(model.peakToMeter(0.5), 0.6716)
near(model.peakToMeter(0.3), 0.4296)
near(model.peakToMeter(0.25), 0.3432)
near(model.peakToMeter(0.15), 0.1012)
near(model.peakToMeter(Math.pow(10, -55 / 60)), 0)

// The floor and garbage inputs.
assert.equal(model.peakToMeter(0.1), 0, 'below the noise floor')
assert.equal(model.peakToMeter(0), 0)
assert.equal(model.peakToMeter(-1), 0)
assert.equal(model.peakToMeter(NaN), 0)
assert.equal(model.peakToMeter(null), 0)
assert.equal(model.peakToMeter(2), 1, 'clamped at full scale')

console.log('ok - nexus audio model')
