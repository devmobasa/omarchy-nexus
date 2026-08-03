const assert = require('node:assert/strict')
const model = require('../model/NexusSuiteModel.js')

// The copied shared engines must load and expose their key functions.
const agenda = require('../model/NexusAgendaModel.js')
assert.equal(typeof agenda.mergeAgendas, 'function')
assert.equal(typeof agenda.upcoming, 'function')
assert.equal(typeof agenda.countdownLabel, 'function')
const pomodoro = require('../model/NexusPomodoroModel.js')
assert.equal(typeof pomodoro.parseState, 'function')
assert.equal(typeof pomodoro.startPhase, 'function')
assert.equal(pomodoro.statePath(null, '/h'), '/h/.local/state/omarchy/pomodoro.json',
  'the shared state file path matches the widget')

// ---- screen time ------------------------------------------------------------

const day = JSON.stringify({
  date: '2026-08-03',
  spans: [['ghostty', 0, 7200000], ['brave', 7200000, 9000000], ['bad'], ['x', 5, 'y']]
})
const summary = model.screenTimeSummary(day, '2026-08-03')
assert.equal(summary.totalMs, 9000000)
assert.equal(summary.topApp, 'ghostty')
assert.equal(model.screenTimeLine(summary), '2 h 30 m today · Ghostty 2 h 0 m')
assert.equal(model.screenTimeSummary(day, 'other-day'), null)
assert.equal(model.screenTimeSummary('junk', 'k'), null)
assert.equal(model.screenTimeSummary('{"date":"k","spans":[]}', 'k'), null,
  'an empty day renders no card')
assert.equal(model.screenTimeDayPath('/d', '2026-08-03'), '/d/2026-08-03.json')

// ---- notification history ---------------------------------------------------

const history = JSON.stringify({
  version: 2,
  pending: [{ id: 4, app: 'starship', summary: 'Done', body: ' multi\n line ', urgency: 1, timestamp: 2000 }],
  past: [
    { id: 1, app: 'Signal', summary: 'Msg', body: 'hey', urgency: 1, timestamp: 3000 },
    { id: 2, app: '', summary: '', body: '', urgency: 0, timestamp: 1000 },
    { bogus: true },
    { app: 'x', summary: 'no time' }
  ]
})
const rows = model.parseNotifications(history, 50)
assert.equal(rows.length, 3, 'malformed rows are dropped')
assert.equal(rows[0].app, 'Signal', 'newest first across pending and past')
assert.equal(rows[1].pending, true)
assert.equal(rows[1].body, 'multi line', 'bodies flatten to one line')
assert.equal(model.parseNotifications(history, 2).length, 2, 'the cap applies')
assert.deepEqual(model.parseNotifications('junk', 10), [])

assert.equal(model.relativeTime(1000, 1000 + 30000), 'now')
assert.equal(model.relativeTime(1000, 1000 + 5 * 60000), '5 m ago')
assert.equal(model.relativeTime(1000, 1000 + 3 * 3600000), '3 h ago')
assert.equal(model.relativeTime(1000, 1000 + 50 * 3600000), '2 d ago')

// ---- presets ----------------------------------------------------------------

assert.equal(model.activePreset({ gmAnimations: true, gmBlur: true, gmShadows: true, gmGaps: true, gmRounding: true, gmTearing: true }), 'full')
assert.equal(model.activePreset({ gmAnimations: true, gmBlur: true, gmShadows: true, gmGaps: false, gmRounding: false, gmTearing: false }), 'effects')
assert.equal(model.activePreset({ gmAnimations: true, gmBlur: false, gmShadows: false, gmGaps: false, gmRounding: false, gmTearing: false }), 'minimal')
assert.equal(model.activePreset({ gmAnimations: false, gmBlur: true, gmShadows: false, gmGaps: false, gmRounding: false, gmTearing: false }), 'custom')

assert.equal(model.notesPath(null, '/h'), '/h/.local/state/omarchy/nexus-notes.md')
assert.equal(model.notificationsPath(null, '/h'), '/h/.local/state/omarchy/notifications.json')
assert.equal(model.clipboardPath(null, '/h'), '/h/.local/state/omarchy/clipboard-history.json')

// ---- clipboard --------------------------------------------------------------

const clips = model.parseClipboard(JSON.stringify([
  { type: 'text', text: '  hello\n world  ' },
  { type: 'image', path: '/x.png', mime: 'image/png', capturedAt: 'Monday 00:06' },
  { type: 'text', text: '   ' },
  { bogus: true },
  { type: 'text', text: 'x'.repeat(200) }
]), 10)
assert.equal(clips.length, 3, 'blank and malformed entries are dropped')
assert.equal(clips[0].preview, 'hello world', 'previews flatten to one line')
assert.equal(clips[0].text, '  hello\n world  ', 'the original text is preserved for copying')
assert.equal(clips[1].kind, 'image')
assert.equal(clips[1].preview, '[image] Monday 00:06')
assert.ok(clips[2].preview.endsWith('…'), 'long previews truncate')
assert.equal(model.parseClipboard(JSON.stringify([{ type: 'text', text: 'a' }, { type: 'text', text: 'b' }]), 1).length, 1)
assert.deepEqual(model.parseClipboard('junk', 5), [])

assert.deepEqual(model.copyCommand('some -- text'), ['wl-copy', '--', 'some -- text'],
  'the copy is one argv element behind an argument terminator')

// ---- clipboard pins ---------------------------------------------------------

assert.ok(model.pinsPath('/tmp/state', '/home/u').endsWith('/omarchy/nexus-clipboard-pins.json'))
const pinRows = model.parsePins(JSON.stringify(['alpha', '', 42, '  beta text  ']))
assert.equal(pinRows.length, 2, 'blank and non-string pins are dropped')
assert.equal(pinRows[0].kind, 'text')
assert.equal(pinRows[0].pinned, true)
assert.equal(pinRows[1].preview, 'beta text')
assert.equal(pinRows[1].text, '  beta text  ', 'pin rows keep the exact text for copying')
assert.deepEqual(model.parsePins('junk'), [])
assert.deepEqual(model.parsePins('{"a":1}'), [])

const pinned = model.togglePin([], 'first')
assert.deepEqual(pinned, ['first'])
assert.deepEqual(model.togglePin(pinned, 'second'), ['second', 'first'], 'new pins prepend')
assert.deepEqual(model.togglePin(['a', 'b'], 'a'), ['b'], 'toggling an existing pin removes it')
assert.deepEqual(model.togglePin(['a'], '   '), ['a'], 'blank text never pins')
const overCap = []
for (let i = 0; i < model.PIN_CAP + 5; i++) overCap.push('pin' + i)
assert.equal(model.togglePin(overCap, 'fresh').length, model.PIN_CAP, 'the cap holds')
assert.ok(model.isPinned(pinRows, '  beta text  '))
assert.ok(!model.isPinned(pinRows, 'beta text'), 'pin identity is the exact text')

const roundTrip = model.parsePins(model.serializePins(['one', 'two']))
assert.deepEqual(roundTrip.map(r => r.text), ['one', 'two'], 'serialize/parse round-trips')

// ---- clipboard history deletion ---------------------------------------------

const historyRaw = JSON.stringify([
  { type: 'text', text: 'keep me' },
  { type: 'image', path: '/p/shot.png', mime: 'image/png', capturedAt: 'Monday 12:00' },
  { type: 'text', text: 'delete me' }
], null, 2) + '\n'
assert.equal(model.clipEntryKey({ type: 'text', text: 'x' }), 'text:x')
assert.equal(model.clipEntryKey({ type: 'image', path: '/p.png' }), 'image:/p.png')
const afterText = model.removeClipEntry(historyRaw, 'text:delete me')
assert.ok(afterText.endsWith('\n'), 'the manager serialization survives')
assert.deepEqual(JSON.parse(afterText).map(model.clipEntryKey),
  ['text:keep me', 'image:/p/shot.png'])
const afterImage = model.removeClipEntry(historyRaw, 'image:/p/shot.png')
assert.equal(JSON.parse(afterImage).length, 2, 'image rows delete by path identity')
assert.equal(model.removeClipEntry(historyRaw, 'text:absent'), null, 'no match, no write')
assert.equal(model.removeClipEntry('junk', 'text:x'), null)
assert.equal(model.removeClipEntry(historyRaw, ''), null)

const keyedRows = model.parseClipboard(historyRaw, 10)
assert.equal(keyedRows[0].key, 'text:keep me')
assert.equal(keyedRows[1].key, 'image:/p/shot.png', 'image rows carry a deletable identity')

// ---- pending count and action identity --------------------------------------

assert.equal(model.pendingCount(JSON.stringify({ pending: [1, 2, 3], past: [] })), 3)
assert.equal(model.pendingCount(JSON.stringify({ past: [] })), 0)
assert.equal(model.pendingCount('junk'), 0)

const withIds = model.parseNotifications(JSON.stringify({
  pending: [{ app: 'x', summary: 's', timestamp: 5, originalId: 42 }],
  past: [{ app: 'y', summary: 't', timestamp: 4 }]
}), 10)
assert.equal(withIds[0].originalId, 42, 'the daemon id survives for liveRefs/removeByOriginalId')
assert.equal(withIds[1].originalId, 0, 'a missing id degrades to 0, never undefined')

console.log('ok - nexus suite integrations model')
