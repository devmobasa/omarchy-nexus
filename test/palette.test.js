const assert = require('node:assert/strict')
const model = require('../model/NexusPaletteModel.js')

// fuzzyScore: subsequence semantics.
assert.equal(model.fuzzyScore('', 'anything'), 0, 'empty query matches everything neutrally')
assert.equal(model.fuzzyScore('x', ''), -1, 'empty haystack never matches')
assert.equal(model.fuzzyScore('zzz', 'pizza'), -1, 'exhausted haystack fails cleanly')
assert.ok(model.fuzzyScore('zz', 'pizza') > 0, 'subsequences match anywhere')
assert.ok(model.fuzzyScore('dnd', 'Toggle Do Not Disturb') > 0, 'scattered word starts match')
assert.equal(model.fuzzyScore('q', 'do not disturb'), -1, 'missing character is no match')

// Ranking: word starts beat mid-word hits; shorter haystacks win ties.
const wordStart = model.fuzzyScore('night', 'Toggle Night Light')
const midWord = model.fuzzyScore('night', 'brightness overnight')
assert.ok(wordStart > midWord, 'a word-start run outranks a buried one')
assert.ok(model.fuzzyScore('go', 'go') > model.fuzzyScore('go', 'go to the settings page'),
  'shorter haystack wins the tie')

// filterEntries: empty query returns the head of the catalogue.
const entries = [
  { kind: 'page', arg: 'overview', title: 'Go to Overview', subtitle: 'page' },
  { kind: 'control', arg: 'dnd', title: 'Toggle Do Not Disturb', subtitle: 'off' },
  { kind: 'keybind', arg: 'SUPER + M — Minimize window', title: 'SUPER + M', subtitle: 'Minimize window' }
]
assert.deepEqual(model.filterEntries(entries, '', 2), entries.slice(0, 2))
assert.deepEqual(model.filterEntries(entries, '   ', 10), entries, 'whitespace query is empty')

// Query matches titles and subtitles.
const minimize = model.filterEntries(entries, 'minimize', 8)
assert.equal(minimize.length, 1)
assert.equal(minimize[0].kind, 'keybind')
const disturb = model.filterEntries(entries, 'disturb', 8)
assert.equal(disturb[0].arg, 'dnd')

// Cap and garbage tolerance.
assert.equal(model.filterEntries(null, 'x', 5).length, 0)
assert.equal(model.filterEntries([null, entries[0]], 'overview', 5).length, 1)
const many = []
for (let i = 0; i < 40; i++) many.push({ kind: 'page', arg: String(i), title: 'Entry ' + i, subtitle: '' })
assert.equal(model.filterEntries(many, 'entry', 8).length, model.MAX_RESULTS)

// Tiered ranking: a weak title match still outranks a strong subtitle-only
// match, so controls never lose to keybind descriptions.
const tiered = [
  { kind: 'keybind', arg: 'x', title: 'SUPER + Q', subtitle: 'night light toggle helper thing' },
  { kind: 'control', arg: 'night-light', title: 'Toggle Night Light', subtitle: 'off' }
]
assert.equal(model.filterEntries(tiered, 'night', 8)[0].arg, 'night-light')

// Ghost completion: only a case-insensitive prefix of the TOP result's
// title completes; anything else stays empty.
const ghostResults = [{ title: 'Toggle Night Light' }, { title: 'Night owl' }]
assert.equal(model.ghostRemainder('togg', ghostResults), 'le Night Light')
assert.equal(model.ghostRemainder('TOGG', ghostResults), 'le Night Light', 'case-insensitive prefix')
assert.equal(model.ghostRemainder('night', ghostResults), '', 'mid-title match never ghosts')
assert.equal(model.ghostRemainder('', ghostResults), '')
assert.equal(model.ghostRemainder('x', []), '')
assert.equal(model.ghostRemainder('toggle night light', [{ title: 'Toggle Night Light' }]), '',
  'a fully typed title ghosts nothing')

// The control catalogue: args unique, kinds valid, every entry titled.
const seen = new Set()
for (const entry of model.CONTROL_ENTRIES) {
  assert.equal(entry.kind, model.KINDS.CONTROL)
  assert.ok(entry.title.length > 0)
  assert.ok(!seen.has(entry.arg), `duplicate control arg ${entry.arg}`)
  seen.add(entry.arg)
}
assert.ok(seen.has('dnd') && seen.has('clear-alerts') && seen.has('power'))

console.log('ok - nexus palette model')
