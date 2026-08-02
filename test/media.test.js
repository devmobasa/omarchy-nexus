const assert = require('node:assert/strict')
const media = require('../model/NexusMediaModel.js')

function raw(overrides) {
  return Object.assign({
    busName: 'org.mpris.MediaPlayer2.test',
    identity: 'Test Player',
    desktopEntry: 'test-player',
    state: 'paused',
    trackKey: 'track-1',
    canPlay: true, canPause: true, canGoNext: true, canGoPrevious: true
  }, overrides)
}

function records(list) {
  return list.map(media.buildRecord)
}

function selected(list, preferred, serials) {
  const result = media.selectPlayer(records(list), preferred || '', serials || {})
  return result ? result.busName : null
}

// ---- record construction ---------------------------------------------------

// sourceKey precedence: alias, then desktopEntry, then identity, then bus.
assert.equal(media.buildRecord(raw({})).sourceKey, 'test-player')
assert.equal(media.buildRecord(raw({ desktopEntry: '' })).sourceKey, 'test player')
assert.equal(media.buildRecord(raw({ desktopEntry: '', identity: '' })).sourceKey,
  'org.mpris.MediaPlayer2.test')

// The identity normalizer is exact trim + lowercase, shared with preference.
assert.equal(media.normalizeIdentity('  Spotify  '), 'spotify')

// Unknown states normalize to unknown; invalid input cannot poison ordering.
assert.equal(media.buildRecord(raw({ state: 'buffering' })).state, 'unknown')

// playerctld can never be attributed to one source: dropped, exact match only.
assert.equal(media.buildRecord(raw({
  busName: 'org.mpris.MediaPlayer2.playerctld', identity: 'playerctld', desktopEntry: 'playerctld'
})).dropped, true)
assert.equal(media.buildRecord(raw({ identity: 'playerctld extra' })).dropped, false,
  'alias matching is exact, never substring')

// The alias table groups an attributable proxy with its real source.
const proxyRecord = media.buildRecord(raw({
  busName: 'org.mpris.MediaPlayer2.plasmaBrowser',
  identity: 'Plasma Browser Integration', desktopEntry: ''
}))
assert.equal(proxyRecord.sourceKey, 'chromium')
assert.equal(proxyRecord.isProxy, true)

// ---- phase 1: a real same-source player always beats its proxy -------------

const pausedRealChromium = raw({
  busName: 'org.mpris.MediaPlayer2.chromium.instance42',
  identity: 'Chromium', desktopEntry: 'chromium', state: 'paused'
})
const playingProxyChromium = raw({
  busName: 'org.mpris.MediaPlayer2.plasmaBrowser',
  identity: 'Plasma Browser Integration', desktopEntry: '', state: 'playing'
})

// A playing proxy never defeats the paused real player of the same source.
assert.equal(selected([pausedRealChromium, playingProxyChromium]),
  'org.mpris.MediaPlayer2.chromium.instance42')

// A preferred proxy never defeats a non-preferred real same-source player.
assert.equal(selected([pausedRealChromium, playingProxyChromium], 'Plasma Browser Integration'),
  'org.mpris.MediaPlayer2.chromium.instance42')

// Proxy-only group: the proxy may represent its source.
assert.equal(selected([playingProxyChromium]), 'org.mpris.MediaPlayer2.plasmaBrowser')

// Real-player disappearance promotes the proxy.
assert.equal(selected([playingProxyChromium, raw({
  busName: 'org.mpris.MediaPlayer2.spotify', identity: 'Spotify',
  desktopEntry: 'spotify', state: 'stopped'
})]), 'org.mpris.MediaPlayer2.plasmaBrowser')

// ---- phase 2: total order across representatives ---------------------------

const playingSpotify = raw({
  busName: 'org.mpris.MediaPlayer2.spotify', identity: 'Spotify',
  desktopEntry: 'spotify', state: 'playing'
})
const pausedMpv = raw({
  busName: 'org.mpris.MediaPlayer2.mpv', identity: 'mpv', desktopEntry: 'mpv', state: 'paused'
})

// Playback state ranks first.
assert.equal(selected([pausedMpv, playingSpotify]), 'org.mpris.MediaPlayer2.spotify')

// Exact preferred identity breaks same-state ties.
const playingMpv = raw({
  busName: 'org.mpris.MediaPlayer2.mpv', identity: 'mpv', desktopEntry: 'mpv', state: 'playing'
})
assert.equal(selected([playingSpotify, playingMpv], 'mpv'), 'org.mpris.MediaPlayer2.mpv')
assert.equal(selected([playingSpotify, playingMpv], 'MPV'), 'org.mpris.MediaPlayer2.mpv',
  'preference uses the shared normalizer')

// Larger activitySerial breaks remaining ties.
const serials = {
  'org.mpris.MediaPlayer2.spotify': { state: 'playing', trackKey: 't', serial: 1 },
  'org.mpris.MediaPlayer2.mpv': { state: 'playing', trackKey: 't', serial: 2 }
}
assert.equal(selected([playingSpotify, playingMpv], '', serials), 'org.mpris.MediaPlayer2.mpv')

// Then identityKey, then bus name, in byte order.
assert.equal(selected([playingSpotify, playingMpv]), 'org.mpris.MediaPlayer2.mpv',
  'mpv < spotify in byte order')

// Ordering is stable across input permutations.
const fixture = [pausedRealChromium, playingProxyChromium, playingSpotify, pausedMpv]
const expected = selected(fixture)
const permutations = [
  [0, 1, 2, 3], [3, 2, 1, 0], [1, 3, 0, 2], [2, 0, 3, 1], [1, 0, 3, 2], [3, 1, 2, 0]
]
for (const order of permutations) {
  assert.equal(selected(order.map(i => fixture[i])), expected,
    `permutation ${order.join(',')} selects the same player`)
}

// Empty and dropped-only inputs select nothing.
assert.equal(selected([]), null)
assert.equal(selected([raw({ busName: 'org.mpris.MediaPlayer2.playerctld', identity: 'playerctld' })]), null)

// ---- activitySerial rules --------------------------------------------------

let activity = media.reconcileActivity({}, records([pausedMpv]), 0)
assert.equal(activity.lastSerial, 0, 'a newly discovered paused player does not bump')

activity = media.reconcileActivity({}, records([playingSpotify]), 0)
assert.equal(activity.lastSerial, 1, 'a newly discovered playing player bumps')

// Transition into playing bumps once; staying in playing does not.
activity = media.reconcileActivity(
  { 'org.mpris.MediaPlayer2.mpv': { state: 'paused', trackKey: 'track-1', serial: 0 } },
  records([playingMpv]), 0)
assert.equal(activity.lastSerial, 1)
const unchanged = media.reconcileActivity(activity.serials, records([playingMpv]), activity.lastSerial)
assert.equal(unchanged.lastSerial, 1, 'steady playing state does not bump')

// Track change while playing bumps; track change while paused does not.
const trackChange = media.reconcileActivity(activity.serials,
  records([raw({ busName: 'org.mpris.MediaPlayer2.mpv', identity: 'mpv', desktopEntry: 'mpv', state: 'playing', trackKey: 'track-2' })]),
  activity.lastSerial)
assert.equal(trackChange.lastSerial, 2)
const pausedTrackChange = media.reconcileActivity(
  { 'org.mpris.MediaPlayer2.mpv': { state: 'paused', trackKey: 'track-1', serial: 0 } },
  records([raw({ busName: 'org.mpris.MediaPlayer2.mpv', identity: 'mpv', desktopEntry: 'mpv', state: 'paused', trackKey: 'track-9' })]), 5)
assert.equal(pausedTrackChange.lastSerial, 5)

// A successful user action bumps exactly its target.
const bumped = media.bumpUserAction(trackChange.serials, 'org.mpris.MediaPlayer2.mpv', trackChange.lastSerial)
assert.equal(bumped.lastSerial, 3)
assert.equal(bumped.serials['org.mpris.MediaPlayer2.mpv'].serial, 3)

// ---- artwork scheme whitelist ----------------------------------------------

assert.equal(media.allowedArtUrl('https://example.com/cover.jpg'), 'https://example.com/cover.jpg')
assert.equal(media.allowedArtUrl('file:///tmp/cover.png'), 'file:///tmp/cover.png')
assert.equal(media.allowedArtUrl('qrc:/art.png'), 'qrc:/art.png')
for (const bad of ['javascript:alert(1)', 'data:image/png;base64,AAAA', 'ftp://x/y', 'cover.jpg', '', null]) {
  assert.equal(media.allowedArtUrl(bad), '', `${JSON.stringify(bad)} is rejected`)
}

console.log('ok - nexus deterministic mpris model')
