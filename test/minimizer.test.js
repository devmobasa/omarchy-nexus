const assert = require('node:assert/strict')
const model = require('../model/NexusMinimizerModel.js')

// ---- sidecar paths ----------------------------------------------------------

assert.equal(model.runtimeDir('/run/user/1000'), '/run/user/1000/hyprland-minimizer')
assert.equal(model.runtimeDir(''), '/tmp/hyprland-minimizer')
assert.equal(model.sidecarPath('/d'), '/d/state.json')
assert.equal(model.historyPath('/d'), '/d/history.txt')
assert.equal(model.MINIMIZED_WORKSPACE, 'special:minimized')

// ---- sidecar parsing --------------------------------------------------------

const sidecar = model.parseSidecar(JSON.stringify({
  '0xaaa': { workspace: '3', monitor: 'DP-1', thumb: '/run/thumbs/Ghostty.jpg' },
  '0xbbb': { workspace: '1', monitor: '', thumb: '' },
  '0xbad': 'not an object'
}))
assert.equal(Object.keys(sidecar).length, 2)
assert.equal(sidecar['0xaaa'].thumb, '/run/thumbs/Ghostty.jpg')
assert.deepEqual(model.parseSidecar('junk'), {})
assert.deepEqual(model.parseSidecar('[]'), {})

assert.deepEqual(model.parseHistory('0xaaa\n0xbbb\n\n'), ['0xaaa', '0xbbb'])
assert.deepEqual(model.parseHistory(''), [])

// ---- row merging ------------------------------------------------------------

const windows = [
  { address: 'aaa', title: 'Ghostty: session', toplevel: { fake: true } },
  { address: 'bbb', title: '  ', toplevel: null },
  { address: 'ccc', title: 'Hand-moved window', toplevel: null },
  { address: 'zz', title: 'invalid address' }
]
const rows = model.rows(windows, sidecar, ['0xaaa', '0xbbb'])
assert.equal(rows.length, 3, 'invalid addresses drop')
assert.equal(rows[0].address, '0xbbb', 'history newest-last means bbb is newest-first')
assert.equal(rows[1].address, '0xaaa')
assert.equal(rows[2].address, '0xccc', 'windows the scripts never saw list last')
assert.equal(rows[2].origin, 'origin unknown')
assert.equal(rows[2].thumb, '')
assert.equal(rows[0].title, '(untitled window)')
assert.equal(rows[1].origin, 'WS 3 · DP-1')
assert.equal(rows[1].thumb, '/run/thumbs/Ghostty.jpg')

assert.deepEqual(model.rows(null, {}, []), [])

// ---- thumb URLs (titles land in filenames verbatim) -------------------------

assert.equal(model.thumbUrl('/run/thumbs/chromium: New Tab - Chromium.jpg'),
  'file:///run/thumbs/chromium%3A%20New%20Tab%20-%20Chromium.jpg')
assert.equal(model.thumbUrl('/t/a#b?c.jpg'), 'file:///t/a%23b%3Fc.jpg')
assert.equal(model.thumbUrl(''), '')
assert.equal(model.thumbUrl('relative/path.jpg'), '', 'thumb paths must be absolute')

// ---- restore dispatches (the scripts' exact semantics) ----------------------

assert.equal(model.restoreDispatch('aaa', 2),
  'hl.dsp.window.move({ workspace = tostring(2), window = "address:0xaaa", follow = true })',
  'restore follows the window, matching Super+R')
assert.equal(model.focusDispatch('0xaaa'), 'hl.dsp.focus({ window = "address:0xaaa" })')
assert.equal(model.restoreDispatch('zz', 2), '')
assert.equal(model.restoreDispatch('0xaaa', -98), '', 'never restore into a special workspace')
assert.equal(model.focusDispatch("0xa'); evil("), '')

console.log('ok - nexus minimizer model')
