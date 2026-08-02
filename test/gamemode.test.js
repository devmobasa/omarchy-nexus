const assert = require('node:assert/strict')
const gm = require('../model/NexusGameModeModel.js')

// The flag is the SAME file the community.game-mode bar widget controls, so
// either controller can toggle and both stay in sync by watching it.
assert.equal(gm.FLAG_BASENAME, 'community-game-mode.lua')
assert.equal(gm.flagPath(null, '/home/u'),
  '/home/u/.local/state/omarchy/toggles/hypr/community-game-mode.lua')
assert.equal(gm.flagPath('/custom', '/home/u'),
  '/custom/omarchy/toggles/hypr/community-game-mode.lua')

const all = { gmAnimations: true, gmBlur: true, gmShadows: true, gmGaps: true, gmRounding: true, gmTearing: true }

// The full strip set covers all six effects.
const full = gm.buildFlagContent(all)
assert.match(full, /hl\.config\(\{/, 'the flag is an hl.config Lua block')
assert.match(full, /animations = \{\n    enabled = false,/, 'animations off')
assert.match(full, /gaps_in = 0,/, 'inner gaps off')
assert.match(full, /gaps_out = 0,/, 'outer gaps off')
assert.match(full, /allow_tearing = true,/, 'tearing allowed')
assert.match(full, /rounding = 0,/, 'rounding off')
assert.match(full, /blur = \{\n      enabled = false,/, 'blur off')
assert.match(full, /shadow = \{\n      enabled = false,/, 'shadows off')
assert.doesNotMatch(full, /border_size/, 'the focus border is left alone')
assert.ok(full.endsWith('\n'), 'the flag file ends with a newline')

// Deselected effects drop their whole section, not just a line.
const noDecoration = gm.buildFlagContent({ gmAnimations: true, gmGaps: true })
assert.doesNotMatch(noDecoration, /decoration/, 'no empty decoration table')
assert.doesNotMatch(noDecoration, /allow_tearing/, 'tearing stays untouched when deselected')
assert.match(noDecoration, /animations/, 'selected sections remain')

const onlyBlur = gm.buildFlagContent({ gmBlur: true })
assert.doesNotMatch(onlyBlur, /animations|general/, 'unused tables are absent')
assert.match(onlyBlur, /blur = \{\n      enabled = false,/)

// An empty strip set builds nothing, so the toggle can refuse instead of
// writing a flag that strips nothing.
assert.equal(gm.buildFlagContent({}), null)
assert.equal(gm.buildFlagContent(null), null)
assert.equal(gm.buildFlagContent({ gmAnimations: false, gmBlur: false }), null)

console.log('ok - nexus game-mode flag model')
