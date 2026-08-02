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
assert.match(nexus, /NexusModel\.normalizePayload\(payloadJson,/,
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
assert.equal((nexus.match(/running: root\.opened/g) || []).length, 3,
  'clock and both sampler timers stop while the panel is closed')
assert.match(nexus, /Behavior on entrance/, 'open uses a bounded entrance animation')
assert.doesNotMatch(nexus, /execDetached|hyprctl|bash -c/, 'plugin builds no shell commands')

// Metrics sampler contract: exactly two whitelisted argument-array commands.
assert.equal((nexus.match(/\bProcess\s*\{/g) || []).length, 2,
  'one stat+mem sampler process and one df process, nothing else')
assert.match(nexus, /command: \["cat", "\/proc\/stat", "\/proc\/meminfo"\]/,
  'cpu/mem sampling reads proc files with an argument array')
assert.match(nexus, /command: \["df", "-P", "-k", "\/"\]/,
  'storage sampling uses POSIX df with an argument array')
assert.match(nexus, /NexusMetricsModel\.parseStatAndMem/, 'sampler output parses through the tested model')
assert.match(nexus, /NexusMetricsModel\.parseDiskFree/, 'df output parses through the tested model')
assert.match(nexus, /NexusMetricsModel\.isStale/, 'stale readings are detected, not shown as fresh')

// Battery is reactive UPower state with a no-battery fallback; never polled.
assert.match(nexus, /import Quickshell\.Services\.UPower/)
assert.match(nexus, /UPower\.displayDevice/, 'battery state comes from the display device')
assert.match(nexus, /NexusMetricsModel\.batteryDetail/, 'battery presence maps through the tested model')

// Bar-aware geometry and internal scrolling.
assert.match(nexus, /shell\.barConfig/, 'margins read the live bar position')
assert.match(nexus, /barHidden/, 'a hidden bar frees its edge')
assert.match(nexus, /edgeClearance\("top"\)/, 'each edge derives its own clearance')
assert.match(nexus, /Flickable \{/, 'vertical overflow scrolls internally')
assert.match(nexus, /clip: true/, 'scrolled content clips to the card')

// Media adapter contract.
assert.match(nexus, /import Quickshell\.Services\.Mpris/, 'one direct MPRIS adapter')
assert.doesNotMatch(nexus, /omarchy\.media/, 'never polls the media service IPC in parallel')
assert.match(nexus, /NexusMediaModel\.buildRecord/, 'records go through the tested model')
assert.match(nexus, /NexusMediaModel\.selectPlayer/, 'selection uses the deterministic two-phase model')
assert.match(nexus, /NexusMediaModel\.reconcileActivity/, 'activity serials follow the tested rules')
assert.match(nexus, /NexusMediaModel\.bumpUserAction/, 'successful user actions bump the target serial')
assert.match(nexus, /NexusMediaModel\.allowedArtUrl/, 'artwork sources pass the scheme whitelist')
assert.match(nexus, /model: root\.opened \? root\.mprisPlayers : \[\]/,
  'media reactivity is dormant while the panel is closed')
assert.match(nexus, /canGoNext/, 'next is capability-gated')
assert.match(nexus, /canGoPrevious/, 'previous is capability-gated')
assert.match(nexus, /canPause : root\.mediaSelected\.canPlay/, 'play/pause is capability-gated')

// Controls contract: reactive state sources, one action path each,
// serialized pending dispatch, unavailable reasons.
assert.match(nexus, /import Quickshell\.Services\.Pipewire/, 'audio uses reactive PipeWire state')
assert.match(nexus, /objects: root\.opened \? \[root\.audioSink, root\.audioSource\]/,
  'PipeWire nodes are bound only while the panel is open')
assert.match(nexus, /Math\.max\(0, Math\.min\(1, Number\(value\)/, 'volume writes are clamped')
assert.match(nexus, /serviceFor\("omarchy\.notifications"\)/, 'DND uses the first-party service')
assert.match(nexus, /serviceFor\("omarchy\.nightlight"\)/, 'night light uses the first-party service')
assert.match(nexus, /serviceFor\("omarchy\.idle"\)/, 'stay awake uses the first-party service')
assert.match(nexus, /if \(!opened \|\| pendingActionName !== ""\) return/,
  'pending actions are serialized and cannot overlap')
assert.match(nexus, /service unavailable|No output device|No input device/i,
  'unavailable controls show a reason')

// Settings contract: read-only, validated, reactive.
assert.match(nexus, /NexusSettingsModel\.readSettings/, 'settings go through the tested reader')
assert.match(nexus, /normalizePayload\(payloadJson, root\.settings\.defaultPage\)/,
  'defaultPage applies only when the payload names no page')
assert.match(nexus, /settings\.preferredMediaIdentity, mediaSerials\)/,
  'media preference flows from validated settings')
assert.match(nexus, /root\.settings\.showMedia/, 'showMedia gates the media card')
assert.match(nexus, /root\.settings\.showMetrics/, 'showMetrics gates the metric grid')

// Style delegation: close first, then open the Omarchy selector in-process.
assert.match(nexus, /requestClose\(\)\s*\n\s*if \(host && typeof host\.summon === "function"\)/,
  'style actions close Nexus before delegating')
assert.match(nexus, /host\.summon\("omarchy\.menu", JSON\.stringify\(\{ menu: String\(route\) \}\)\)/,
  'delegation goes through the shell menu with a fixed route')
assert.match(nexus, /openStyleMenu\("style\.theme"\)/, 'theme routes to the existing selector')
assert.match(nexus, /openStyleMenu\("style\.background"\)/, 'background routes to the existing selector')

// Theme integration comes from shared tokens only.
assert.match(nexus, /import qs\.Commons/, 'uses shared Color/Style/Border singletons')
assert.match(nexus, /import qs\.Ui/, 'uses shared UI components')
assert.doesNotMatch(nexus, /#[0-9a-fA-F]{6}/, 'no hard-coded colors')

console.log('ok - nexus plugin contract')
