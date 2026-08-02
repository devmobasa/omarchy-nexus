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
assert.deepEqual(read([{ id: ID, defaultPage: 'controls', monitor: 'DP-3', showMedia: false, showMetrics: false, showNetwork: false, showFetch: false, preferredMediaIdentity: 'Spotify' }]), {
  defaultPage: 'controls',
  monitor: 'DP-3',
  showMedia: false,
  showMetrics: false,
  showNetwork: false,
  showFetch: false,
  preferredMediaIdentity: 'Spotify'
})

// Invalid values fall back field by field; extra fields are ignored.
assert.deepEqual(read([{ id: ID, defaultPage: 'bogus', monitor: '   ', showMedia: 'yes', showMetrics: 1, showNetwork: 0, showFetch: 'no', preferredMediaIdentity: 42, extra: true }]),
  settings.DEFAULTS)

// Only the exact id matches; the first matching entry wins.
assert.equal(read([{ id: ID + 'x', defaultPage: 'style' }]).defaultPage, 'overview')
assert.equal(read([{ id: ID, defaultPage: 'style' }, { id: ID, defaultPage: 'controls' }]).defaultPage, 'style')

// Booleans accept only literal false to disable (true stays the default).
assert.equal(read([{ id: ID, showMedia: 0 }]).showMedia, true)
assert.equal(read([{ id: ID, showMedia: false }]).showMedia, false)

console.log('ok - nexus settings model')
