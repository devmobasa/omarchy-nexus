const assert = require('node:assert/strict')
const model = require('../model/NexusDiagnosticsModel.js')

// Path construction validates the instance id — it lands inside argv.
assert.equal(model.logPath('/run/user/1000', 'lft6z3p6jt'),
  '/run/user/1000/quickshell/by-id/lft6z3p6jt/log.log')
assert.equal(model.logPath('', 'x'), '')
assert.equal(model.logPath('/run/user/1000', ''), '')
assert.equal(model.logPath('/run/user/1000', '../../etc'), '', 'traversal never builds a path')
assert.deepEqual(model.tailCommand('/run/user/1000/quickshell/by-id/x/log.log'),
  ['tail', '-n', '400', '/run/user/1000/quickshell/by-id/x/log.log'])
assert.deepEqual(model.tailCommand('relative/path'), [])
assert.deepEqual(model.tailCommand(null), [])

// Redaction: any user's home collapses to ~, mid-string too, but not when
// glued to a preceding word character.
assert.equal(model.redactHomePaths('file:///home/user/x.qml'), 'file://~/x.qml')
assert.equal(model.redactHomePaths('PATH=/home/user/bin:/home/other/bin'), 'PATH=~/bin:~/bin')
assert.equal(model.redactHomePaths('a/home/eve/y'), 'a/home/eve/y')
assert.equal(model.redactHomePaths('/home/user'), '~')

// The scan: only lines after the LAST "Configuration Loaded", only error
// classes, sensitive lines dropped whole, caps applied newest-last.
const log = [
  '10:00:00.000  WARN scene: ReferenceError: stale is not defined',
  '10:00:01.000  INFO quickshell: Configuration Loaded',
  '10:00:02.000  WARN scene: file:///home/user/p/Broken.qml:5: ReferenceError: x is not defined',
  '10:00:03.000  INFO quickshell: something fine',
  '10:00:04.000  WARN scene: Binding loop detected for property "width"',
  '10:00:05.000  WARN scene: TypeError with token=abc123 secret sauce',
  '10:00:06.000  WARN scene: Cannot assign to non-existent property "foo"'
].join('\n')
const rows = model.scanLog(log)
assert.equal(rows.length, 3, 'pre-reload and sensitive lines are gone')
assert.ok(rows[0].indexOf('~/p/Broken.qml') !== -1, 'home path redacted')
assert.ok(rows[1].indexOf('Binding loop') !== -1)
assert.ok(rows[2].indexOf('Cannot assign') !== -1)
assert.ok(rows.every(r => r.indexOf('token=') === -1), 'sensitive vocabulary never survives')

// No marker: the whole tail is eligible. Empty input: no rows.
assert.equal(model.scanLog('WARN: TypeError: boom').length, 1)
assert.deepEqual(model.scanLog(''), [])
assert.deepEqual(model.scanLog(null), [])

// Row cap keeps the NEWEST entries; row length caps with an ellipsis.
const many = Array.from({ length: 20 }, (_, i) => 'WARN scene: TypeError number ' + i).join('\n')
const capped = model.scanLog(many)
assert.equal(capped.length, model.MAX_ROWS)
assert.ok(capped[model.MAX_ROWS - 1].endsWith('number 19'), 'newest survive the cap')
const long = model.scanLog('WARN: TypeError: ' + 'x'.repeat(500))[0]
assert.equal(long.length, model.MAX_ROW_LENGTH)
assert.ok(long.endsWith('…'))

console.log('ok - nexus diagnostics model')
