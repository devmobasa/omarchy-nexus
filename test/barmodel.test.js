const assert = require('node:assert/strict')
const model = require('../model/NexusBarModel.js')

// Normalization mirrors the host: bare strings become {id}, junk drops.
assert.deepEqual(model.normalizeEntry('omarchy.clock'), { id: 'omarchy.clock' })
assert.deepEqual(model.normalizeEntry({ id: 'x', format: '%H' }), { id: 'x' })
assert.equal(model.normalizeEntry(42), null)
assert.equal(model.normalizeEntry({}), null)

const layout = model.layoutFrom({
  layout: {
    left: ['omarchy.workspaces', { id: 'omarchy.clock', format: '%H' }],
    center: [],
    right: ['omarchy.tray', null, 'community.omarchy-nexus']
  }
})
assert.equal(layout.left.length, 2)
assert.equal(layout.right.length, 2, 'junk entries drop')
assert.deepEqual(model.layoutFrom(null), { left: [], center: [], right: [] })

const installed = {
  'omarchy.clock': { name: 'Clock', kinds: ['bar-widget'] },
  'omarchy.tray': { name: 'System tray', kinds: ['bar-widget'] },
  'omarchy.workspaces': { name: 'Workspaces', kinds: ['bar-widget'] },
  'community.omarchy-nexus': { name: 'Omarchy Nexus', kinds: ['panel', 'bar-widget'] },
  'community.pomodoro': { name: 'Pomodoro', kinds: ['bar-widget'] },
  'community.wallpaper-hub': { name: 'Wallpaper Hub', kinds: ['panel'] }
}
const rows = model.displayRows(layout, installed)
assert.equal(rows.length, 4)
assert.equal(rows[0].title, 'Workspaces')
assert.equal(rows[0].first, true)
assert.equal(rows[1].last, true)
assert.equal(rows[1].prevId, 'omarchy.workspaces', 'relative placement ids ride the row')
assert.equal(rows[2].locked, true, 'the tray is render-pinned, so the editor locks it')
assert.equal(rows[3].section, 'right')

// Available = installed bar-widgets not currently placed; panels excluded.
const available = model.availableWidgets(installed, layout)
assert.deepEqual(available.map(w => w.id), ['community.pomodoro'])

assert.equal(model.nextSection('left'), 'center')
assert.equal(model.nextSection('right'), 'left')

console.log('ok - nexus bar model')
