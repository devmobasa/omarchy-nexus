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

console.log('ok - nexus suite integrations model')
