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
assert.deepEqual(model.normalizePayload('{"page":"settings"}'), { page: 'settings' })

// The whitelist is exact: case variants and unknown pages fall back.
assert.deepEqual(model.normalizePayload('{"page":"Controls"}'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":"preferences"}'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":42}'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":["controls"]}'), { page: 'overview' })

// Unknown fields are ignored and never echoed back.
assert.deepEqual(model.normalizePayload('{"page":"controls","command":"rm -rf /"}'),
  { page: 'controls' })

// The defaultPage setting applies only when the payload names no valid page.
assert.deepEqual(model.normalizePayload('{}', 'controls'), { page: 'controls' })
assert.deepEqual(model.normalizePayload('not json', 'style'), { page: 'style' })
assert.deepEqual(model.normalizePayload('{"page":"overview"}', 'controls'), { page: 'overview' })
assert.deepEqual(model.normalizePayload('{"page":"bogus"}', 'style'), { page: 'style' })
assert.deepEqual(model.normalizePayload('{}', 'bogus'), { page: 'overview' },
  'an invalid fallback cannot smuggle in an unknown page')

// Tab cycling wraps in both directions (keys and settings included) and
// recovers from invalid state.
assert.equal(model.adjacentPage('overview', 1), 'controls')
assert.equal(model.adjacentPage('controls', 1), 'style')
assert.equal(model.adjacentPage('style', 1), 'keys')
assert.equal(model.adjacentPage('keys', 1), 'settings')
assert.equal(model.adjacentPage('settings', 1), 'overview')
assert.equal(model.adjacentPage('overview', -1), 'settings')
assert.equal(model.adjacentPage('style', -1), 'controls')
assert.equal(model.adjacentPage('bogus', 1), 'overview')
assert.equal(model.adjacentPage('', -1), 'overview')

// The labelled tab row excludes settings (the cog owns it).
assert.deepEqual(model.tabPages(), ['overview', 'controls', 'style', 'keys'])

// The keys page is payload-reachable.
assert.deepEqual(model.normalizePayload('{"page":"keys"}'), { page: 'keys' })

// Display helpers cover every page and fall back for invalid input. Every
// page has real content now, so all placeholders are empty.
for (const page of model.PAGES) {
  assert.ok(model.pageTitle(page).length > 0)
  assert.equal(model.pagePlaceholder(page), '')
}
assert.equal(model.pageTitle('bogus'), model.pageTitle(model.DEFAULT_PAGE))
assert.equal(model.pagePlaceholder('bogus'), model.pagePlaceholder(model.DEFAULT_PAGE))

console.log('ok - nexus payload and page model')
