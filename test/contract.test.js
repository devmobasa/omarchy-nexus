const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const root = path.resolve(__dirname, '..')
function read(relative) {
  return fs.readFileSync(path.join(root, relative), 'utf8')
}

const manifest = JSON.parse(read('manifest.json'))
assert.equal(manifest.schemaVersion, 1)
assert.equal(manifest.id, 'community.omarchy-nexus')
assert.deepEqual(manifest.kinds, ['panel'])
assert.equal(manifest.entryPoints.panel, 'Nexus.qml')
assert.equal(manifest.keepLoaded, undefined,
  'keepLoaded stays omitted until the summon-latency benchmark demands it')
assert.equal(manifest.license, 'MIT')
assert.match(read('LICENSE'), /MIT License/)

const nexus = read('Nexus.qml')

// Host lifecycle contract.
assert.match(nexus, /^Item \{/m, 'plugin entry point is an Item')
assert.doesNotMatch(nexus, /\bShellRoot\s*\{/, 'plugin does not create another shell root')
assert.match(nexus, /property var shell/, 'declares the shell injection')
assert.match(nexus, /property var manifest/, 'declares the manifest injection')
assert.match(nexus, /function open\(payloadJson\)/, 'plugin exposes open lifecycle')
assert.match(nexus, /function close\(\)/, 'plugin exposes close lifecycle')
assert.match(nexus, /function status\(\)/, 'plugin exposes runtime diagnostics')
assert.match(nexus, /property bool opened/, 'host reads the logical open state')
assert.match(nexus, /NexusModel\.normalizePayload\(payloadJson\)/,
  'open() routes every payload through the tested normalizer')
assert.match(nexus, /shell\.hide\(/, 'self-initiated close goes through shell.hide')
assert.match(nexus, /closingFromHost/, 'host close and self close cannot recurse')

// Surface and input-region model.
assert.match(nexus, /visible: root\.opened/, 'the surface follows the logical open state')
assert.match(nexus,
  /WlrLayershell\.keyboardFocus: root\.opened \? WlrKeyboardFocus\.Exclusive : WlrKeyboardFocus\.None/,
  'exclusive keyboard focus only while logically open')
assert.match(nexus, /WlrLayershell\.layer: WlrLayer\.Overlay/, 'modal surface sits on the overlay layer')
assert.match(nexus, /exclusionMode: ExclusionMode\.Ignore/, 'no exclusive work area')
assert.match(nexus, /onClicked: root\.requestClose\(\)/, 'outside click requests shell.hide')
assert.match(nexus, /Qt\.Key_Escape/, 'Escape closes the panel')

// Monitor resolution.
assert.match(nexus, /screen: root\.targetScreen/, 'one window targets one resolved screen')
assert.match(nexus, /Hyprland\.focusedMonitor/, 'resolution starts from the focused monitor')
assert.match(nexus, /ToplevelManager\.activeToplevel/, 'falls back to the active toplevel screen')
assert.match(nexus, /onScreensChanged/, 'screen disappearance retargets or closes')

// Closed-state dormancy and animation policy.
assert.match(nexus, /running: root\.opened/, 'no timer runs while the panel is closed')
assert.match(nexus, /Behavior on entrance/, 'open uses a bounded entrance animation')
assert.doesNotMatch(nexus, /\bProcess\s*\{/, 'plugin spawns no subprocess in Milestone 1')
assert.doesNotMatch(nexus, /execDetached|hyprctl|bash -c/, 'plugin builds no shell commands')

// Theme integration comes from shared tokens only.
assert.match(nexus, /import qs\.Commons/, 'uses shared Color/Style/Border singletons')
assert.match(nexus, /import qs\.Ui/, 'uses shared UI components')
assert.doesNotMatch(nexus, /#[0-9a-fA-F]{6}/, 'no hard-coded colors')

console.log('ok - nexus plugin contract')
