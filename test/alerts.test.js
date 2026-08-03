const assert = require('node:assert/strict')
const model = require('../model/NexusAlertsModel.js')

// Unit-name validation: raw C-escaped names pass, junk fails.
assert.ok(model.validUnit('docker.service'))
assert.ok(model.validUnit('dev-disk-by\\x2ddesignator-esp.device'), 'raw escaped names are valid argv tokens')
assert.ok(model.validUnit('openvpn-client@de-347.service'))
assert.ok(!model.validUnit('foo bar.service'), 'spaces never appear raw')
assert.ok(!model.validUnit('-rf.service'), 'leading dash rejected even behind --')
assert.ok(!model.validUnit('noext'), 'a unit always has a type suffix')
assert.ok(!model.validUnit(''))
assert.ok(!model.validUnit('a$(b).service'))

// Display unescaping decodes \xNN without touching the raw form.
assert.equal(model.unescapeUnitName('dev-disk-by\\x2ddesignator.device'), 'dev-disk-by-designator.device')
assert.equal(model.unescapeUnitName('a\\x20b.mount'), 'a b.mount')
assert.equal(model.unescapeUnitName('plain.service'), 'plain.service')

// Listing commands.
assert.deepEqual(model.failedCommand(model.SCOPE_SYSTEM),
  ['systemctl', '--failed', '--output=json', '--no-pager'])
assert.deepEqual(model.failedCommand(model.SCOPE_USER),
  ['systemctl', '--user', '--failed', '--output=json', '--no-pager'])

// Action commands: verb whitelist, scope whitelist, `--` closes options,
// and the RAW name is what reaches argv.
assert.deepEqual(model.unitCommand('restart', 'system', 'docker.service'),
  ['systemctl', 'restart', '--', 'docker.service'])
assert.deepEqual(model.unitCommand('reset-failed', 'user', 'bt-agent.service'),
  ['systemctl', '--user', 'reset-failed', '--', 'bt-agent.service'])
assert.deepEqual(model.unitCommand('stop', 'system', 'docker.service'), [], 'stop is not offered')
assert.deepEqual(model.unitCommand('start', 'user', 'x.service'), [], 'start is not offered')
assert.deepEqual(model.unitCommand('restart', 'global', 'x.service'), [], 'unknown scope rejected')
assert.deepEqual(model.unitCommand('restart', 'system', 'foo bar.service'), [], 'invalid unit rejected')

// Parsing: rows keep raw + display forms, tag the scope, drop junk.
const sample = JSON.stringify([
  { unit: 'docker.service', load: 'loaded', active: 'failed', sub: 'failed', description: 'Docker' },
  { unit: 'dev-x\\x2dy.device', load: 'loaded', active: 'failed', sub: 'failed', description: 'Disk\\x20Two' },
  { unit: 42, description: 'not a unit' },
  null
])
const rows = model.parseFailedUnits(sample, model.SCOPE_USER)
assert.equal(rows.length, 2)
assert.equal(rows[0].unit, 'docker.service')
assert.equal(rows[0].scope, 'user')
assert.equal(rows[1].unit, 'dev-x\\x2dy.device', 'raw form preserved for argv')
assert.equal(rows[1].display, 'dev-x-y.device', 'display form unescaped')
assert.equal(rows[1].description, 'Disk Two', 'descriptions unescape too')
assert.deepEqual(model.parseFailedUnits('[]', 'system'), [])
assert.deepEqual(model.parseFailedUnits('not json', 'system'), [])
assert.deepEqual(model.parseFailedUnits('{"a":1}', 'system'), [])

console.log('ok - nexus alerts model')
