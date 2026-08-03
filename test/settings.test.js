const assert = require('node:assert/strict')
const settings = require('../model/NexusSettingsModel.js')

const PAGES = ['overview', 'controls', 'style']
const ID = 'community.omarchy-nexus'

function read(plugins) {
  return settings.readSettings(plugins, ID, PAGES)
}

// Missing array, missing entry, or malformed entries all yield pure defaults.
for (const input of [null, undefined, [], {}, 'x', [null, 'x', 42], [{ id: 'other.plugin' }]]) {
  assert.deepEqual(read(input), settings.DEFAULTS, `${JSON.stringify(input)} yields defaults`)
}

// A matching entry overrides only with valid values.
const disabled = read([{ id: ID, defaultPage: 'controls', monitor: 'DP-3', showMedia: false, showMetrics: false, showNetwork: false, showFetch: false, showBattery: false, gmBlur: false, preferredMediaIdentity: 'Spotify' }])
assert.equal(disabled.defaultPage, 'controls')
assert.equal(disabled.monitor, 'DP-3')
assert.equal(disabled.showMedia, false)
assert.equal(disabled.showMetrics, false)
assert.equal(disabled.showNetwork, false)
assert.equal(disabled.showFetch, false)
assert.equal(disabled.showBattery, false)
assert.equal(disabled.gmBlur, false)
assert.equal(disabled.showCpu, true, 'untouched fields keep their defaults')
assert.equal(disabled.gmAnimations, true)
assert.equal(disabled.preferredMediaIdentity, 'Spotify')

// Invalid values fall back field by field; extra fields are ignored.
assert.deepEqual(read([{ id: ID, defaultPage: 'bogus', monitor: '   ', showMedia: 'yes', showMetrics: 1, showNetwork: 0, showFetch: 'no', showBattery: 'off', gmGaps: null, preferredMediaIdentity: 42, extra: true }]),
  settings.DEFAULTS)

// ---- interactive state layer ------------------------------------------------

// The state file overrides the shell.json layer for the fields it owns.
const base = read([{ id: ID, showMedia: false }])
const merged = settings.applyState(base, settings.parseState('{"showMedia": true, "showBattery": false}'))
assert.equal(merged.showMedia, true, 'state file wins over the shell.json layer')
assert.equal(merged.showBattery, false)
assert.equal(merged.showCpu, true)
assert.equal(merged.defaultPage, 'overview', 'non-state fields pass through untouched')

// Malformed or hostile state parses to no overrides.
for (const bad of [null, '', 'not json', '[1,2]', '"showMedia"', '{"showMedia":"yes","defaultPage":"style","bogus":true}']) {
  assert.deepEqual(settings.parseState(bad), {}, `${JSON.stringify(bad)} yields no overrides`)
}
assert.deepEqual(settings.parseState('{"showFetch":false,"gmTearing":false}'),
  { showFetch: false, gmTearing: false })

// Serialization round-trips through the parser and keeps only known fields.
const written = settings.buildStateJson({ showBattery: false, gmBlur: true, bogus: 1, showMedia: 'x' })
assert.deepEqual(settings.parseState(written), { showBattery: false, gmBlur: true })
assert.ok(written.endsWith('\n'), 'the state file ends with a newline')

// XDG-aware state path.
assert.equal(settings.statePath(null, '/home/u'), '/home/u/.local/state/omarchy/settings/nexus.json')
assert.equal(settings.statePath('/custom', '/home/u'), '/custom/omarchy/settings/nexus.json')

// Only the exact id matches; the first matching entry wins.
assert.equal(read([{ id: ID + 'x', defaultPage: 'style' }]).defaultPage, 'overview')
assert.equal(read([{ id: ID, defaultPage: 'style' }, { id: ID, defaultPage: 'controls' }]).defaultPage, 'style')

// Booleans accept only literal false to disable (true stays the default).
assert.equal(read([{ id: ID, showMedia: 0 }]).showMedia, true)
assert.equal(read([{ id: ID, showMedia: false }]).showMedia, false)

// The serializer doubles as the equality gate for skip-equal writes: it
// must be deterministic and immune to hostile keys in a hand-edited file.
assert.equal(settings.buildStateJson({ showMedia: true, gmBlur: false }),
  settings.buildStateJson({ gmBlur: false, showMedia: true }),
  'stable key order regardless of insertion order')
const hostile = settings.parseState('{"__proto__": {"x": 1}, "constructor": 2, "showMedia": false}')
assert.deepEqual(Object.keys(hostile), ['showMedia'], 'unknown and prototype keys never survive parsing')
assert.equal(({}).x, undefined, 'no prototype pollution occurred')

console.log('ok - nexus settings model')
