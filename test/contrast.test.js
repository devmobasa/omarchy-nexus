const assert = require('node:assert/strict')
const model = require('../model/NexusContrastModel.js')

// The WCAG constants at their anchor points.
assert.equal(model.relativeLuminance(0, 0, 0), 0, 'black is zero luminance')
assert.ok(Math.abs(model.relativeLuminance(1, 1, 1) - 1) < 1e-9, 'white is unit luminance')
assert.ok(Math.abs(model.contrastRatio(0, 1) - 21) < 0.01, 'black on white is 21:1')
assert.equal(model.contrastRatio(0.5, 0.5), 1, 'identical luminance is 1:1')

// Channel linearization: the 0.04045 knee.
assert.ok(model.linearChannel(0.03) < 0.03, 'low channel divides by 12.92')
assert.ok(model.linearChannel(0.5) < 0.5, 'gamma curve compresses midtones')
assert.equal(model.linearChannel(-5), 0, 'clamped low')
assert.equal(model.linearChannel(5), 1, 'clamped high')
assert.equal(model.linearChannel(NaN), 0)

// Picking: dark text wins on a light fill, light text on a dark fill.
const black = { r: 0, g: 0, b: 0 }
const white = { r: 1, g: 1, b: 1 }
assert.equal(model.readableIndex({ r: 0.9, g: 0.9, b: 0.2 }, [white, black]), 1,
  'a bright accent takes the dark candidate')
assert.equal(model.readableIndex({ r: 0.1, g: 0.1, b: 0.4 }, [white, black]), 0,
  'a dark accent takes the light candidate')
assert.equal(model.readableIndex(black, []), -1)
assert.equal(model.readableIndex(null, [white]), 0, 'a missing fill degrades, never throws')

console.log('ok - nexus contrast model')
