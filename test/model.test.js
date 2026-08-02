const assert = require('node:assert/strict')
const model = require('../model/NexusModel.js')

// Every malformed input maps to the default page; open() must never refuse.
for (const payload of [
  undefined, null, '', '   ', 'not json', '{broken', '[]', '[1,2]',
  '"controls"', '42', 'true', 'null', '{}'
]) {
  assert.deepEqual(model.normalizePayload(payload), { page: 'overview' },
    `payload ${JSON.stringify(payload)} normalizes to overview`)
}

// Whitelisted pages pass through.
assert.deepEqual(model.normalizePayload('{"page":"overview"}'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":"controls"}'), { page: 'controls' })
assert.deepEqual(model.normalizePayload('{"page":"style"}'), { page: 'style' })

// The whitelist is exact: case variants and unknown pages fall back.
assert.deepEqual(model.normalizePayload('{"page":"Controls"}'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":"settings"}'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":42}'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":["controls"]}'), { page: 'overview' })

// Unknown fields are ignored and never echoed back.
assert.deepEqual(model.normalizePayload('{"page":"controls","command":"rm -rf /"}'),
  { page: 'controls' })

// Tab cycling wraps in both directions and recovers from invalid state.
assert.equal(model.adjacentPage('overview', 1), 'controls')
assert.equal(model.adjacentPage('controls', 1), 'style')
assert.equal(model.adjacentPage('style', 1), 'overview')
assert.equal(model.adjacentPage('overview', -1), 'style')
assert.equal(model.adjacentPage('style', -1), 'controls')
assert.equal(model.adjacentPage('bogus', 1), 'overview')
assert.equal(model.adjacentPage('', -1), 'overview')

// Display helpers cover every page and fall back for invalid input.
for (const page of model.PAGES) {
  assert.ok(model.pageTitle(page).length > 0)
  assert.ok(model.pagePlaceholder(page).length > 0)
}
assert.equal(model.pageTitle('bogus'), model.pageTitle(model.DEFAULT_PAGE))
assert.equal(model.pagePlaceholder('bogus'), model.pagePlaceholder(model.DEFAULT_PAGE))

console.log('ok - nexus payload and page model')
