const assert = require('node:assert/strict')
const model = require('../model/NexusKeybindsModel.js')

// ---- modifier decoding ------------------------------------------------------

assert.deepEqual(model.decodeModmask(64), ['SUPER'])
assert.deepEqual(model.decodeModmask(65), ['SUPER', 'SHIFT'])
assert.deepEqual(model.decodeModmask(76), ['SUPER', 'CTRL', 'ALT'])
assert.deepEqual(model.decodeModmask(0), [])
assert.deepEqual(model.decodeModmask('x'), [])

// ---- combo rendering --------------------------------------------------------

assert.equal(model.comboFor(64, 'B'), 'SUPER + B')
assert.equal(model.comboFor(65, 'j'), 'SUPER + SHIFT + J')
assert.equal(model.comboFor(0, 'XF86AudioRaiseVolume'), 'XF86AudioRaiseVolume')
// code: binds embed the whole combo in the key field — never double-prefix.
assert.equal(model.comboFor(64, 'SUPER + code:10'), 'SUPER + 1')
assert.equal(model.comboFor(65, 'SUPER + SHIFT + code:19'), 'SUPER + SHIFT + 0')
assert.equal(model.comboFor(64, 'SUPER + code:255'), 'SUPER + code:255', 'unknown codes stay visible')
assert.equal(model.comboFor(64, 'mouse:272'), 'SUPER + LeftClick')
assert.equal(model.comboFor(64, ''), 'SUPER')

// ---- text parsing -----------------------------------------------------------

const sample = [
  'bindled',
  '\tmodmask: 0',
  '\tsubmap: ',
  '\tkey: XF86AudioRaiseVolume',
  '\tkeycode: 0',
  '\tcatchall: false',
  '\tdescription: Volume up',
  '\tdispatcher: __lua',
  '\targ: 6',
  '',
  'bindd',
  '\tmodmask: 64',
  '\tsubmap: ',
  '\tkey: SUPER + code:10',
  '\tkeycode: 0',
  '\tcatchall: false',
  '\tdescription: Switch to workspace 1',
  '\tdispatcher: __lua',
  '\targ: 71',
  '',
  'bindd',
  '\tmodmask: 64',
  '\tsubmap: ',
  '\tkey: B',
  '\tkeycode: 0',
  '\tcatchall: false',
  '\tdescription: Browser',
  '\tdispatcher: __lua',
  '\targ: 12',
  '',
  'bind',
  '\tmodmask: 64',
  '\tsubmap: ',
  '\tkey: Z',
  '\tkeycode: 0',
  '\tcatchall: false',
  '\tdescription: ',
  '\tdispatcher: __lua',
  '\targ: 99',
  ''
].join('\n')

const rows = model.parseBindsText(sample)
assert.equal(rows.length, 4)
// Described binds sort before undescribed; combos sort alphabetically.
assert.equal(rows[rows.length - 1].combo, 'SUPER + Z', 'undescribed binds sink to the bottom')
const workspace = rows.find(r => r.description === 'Switch to workspace 1')
assert.equal(workspace.combo, 'SUPER + 1', 'code: binds resolve to digits')
const browser = rows.find(r => r.description === 'Browser')
assert.equal(browser.combo, 'SUPER + B')

assert.deepEqual(model.parseBindsText(''), [])
assert.deepEqual(model.parseBindsText(null), [])

// Duplicate combo+arg pairs collapse.
const dup = model.parseBindsText(sample + '\n' + sample)
assert.equal(dup.length, 4)

// ---- filtering --------------------------------------------------------------

assert.equal(model.filterBinds(rows, '').length, 4)
assert.equal(model.filterBinds(rows, 'browser').length, 1)
assert.equal(model.filterBinds(rows, 'super 1').length, 1, 'every term must match')
assert.equal(model.filterBinds(rows, 'workspace switch').length, 1, 'term order is free')
assert.equal(model.filterBinds(rows, 'zzz').length, 0)
assert.equal(model.filterBinds(null, 'x').length, 0)

console.log('ok - nexus keybinds model')
