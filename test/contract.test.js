const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const root = path.resolve(__dirname, '..')
function read(relative) {
  return fs.readFileSync(path.join(root, relative), 'utf8')
}

function filesBelow(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    if (entry.name === '.git' || entry.name === 'test-output') return []
    const absolute = path.join(directory, entry.name)
    return entry.isDirectory() ? filesBelow(absolute) : [absolute]
  })
}

const repositoryFiles = filesBelow(root)
for (const absolute of repositoryFiles) {
  const relative = path.relative(root, absolute)
  const content = fs.readFileSync(absolute, 'utf8').replace(/\n$/, '')
  const lines = content === '' ? 0 : content.split('\n').length
  assert.ok(lines < 500, `${relative} must stay under 500 lines (got ${lines})`)
}

const manifest = JSON.parse(read('manifest.json'))
assert.equal(manifest.schemaVersion, 1)
assert.equal(manifest.id, 'community.omarchy-nexus')
assert.deepEqual(manifest.kinds, ['panel', 'bar-widget'])
assert.equal(manifest.entryPoints.panel, 'Nexus.qml')
assert.equal(manifest.entryPoints.barWidget, 'NexusBarWidget.qml')
assert.equal(manifest.barWidget.defaultSection, 'right')
assert.equal(manifest.barWidget.allowMultiple, false)
assert.equal(manifest.keepLoaded, undefined,
  'keepLoaded stays omitted until the summon-latency benchmark demands it')
assert.equal(manifest.license, 'MIT')
assert.match(read('LICENSE'), /MIT License/)

const nexusEntry = read('Nexus.qml')
const qmlSource = repositoryFiles
  .filter(absolute => absolute.endsWith('.qml'))
  .sort()
  .map(absolute => fs.readFileSync(absolute, 'utf8'))
  .join('\n')
// Component roots use local `nexus` or `state` facade names. Normalize those
// names so the existing behavior contracts remain about ownership, not ids.
const nexus = qmlSource.replace(/\b(?:nexus|state)\./g, 'root.')

// Host lifecycle contract.
assert.match(nexusEntry, /^Item \{/m, 'plugin entry point is an Item')
assert.doesNotMatch(nexus, /\bShellRoot\s*\{/, 'plugin does not create another shell root')
assert.match(nexusEntry, /property var shell/, 'declares the shell injection')
assert.match(nexusEntry, /property var manifest/, 'declares the manifest injection')
assert.match(nexusEntry, /function open\(payloadJson\)/, 'plugin exposes open lifecycle')
assert.match(nexusEntry, /function close\(\)/, 'plugin exposes close lifecycle')
assert.match(nexusEntry, /function status\(\)/, 'plugin exposes runtime diagnostics')
assert.match(nexusEntry, /property bool opened/, 'host reads the logical open state')
assert.match(nexusEntry, /NexusModel\.normalizePayload\(\s*payloadJson,/,
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

// Closed-state dormancy and animation policy. Six timers total; five are
// gated on `opened` (clock, both samplers, media position tick, sensors
// cadence). The sixth, pendingClearTimer, is a one-shot 400 ms clear
// started only from dispatchControl, which no-ops while closed. Pinning the
// total means any new timer fails this test until reviewed for dormancy.
assert.equal((nexus.match(/\bTimer\s*\{/g) || []).length, 7,
  'the timer inventory is pinned: a new timer must be reviewed for dormancy (the seventh is the notes autosave debounce, gated on notesDirty)')
assert.equal((nexus.match(/running: root\.opened/g) || []).length, 6,
  'five recurring timers plus the cava process are gated on the panel being open')
assert.match(nexus, /Behavior on entrance/, 'open uses a bounded entrance animation')
assert.doesNotMatch(nexus, /execDetached|bash -c|sh -c/, 'no shell command strings, ever')

// Process inventory: exactly ten whitelisted argument-array commands — the
// two proc samplers, three user-action game-mode/settings steps, the keys
// fetch, sensor discovery + sampling + nvidia-smi, and cava. hyprctl
// appears in exactly two commands (reload, binds).
assert.equal((nexus.match(/\bProcess\s*\{/g) || []).length, 11,
  'the process inventory is pinned: a new process must be reviewed (the eleventh is the user-action wl-copy)')
assert.match(nexus, /NexusSuiteModel\.copyCommand/, 'clipboard copies build through the model')
assert.match(nexus, /NexusSuiteModel\.parseClipboard/, 'clipboard history parses through the model')
assert.match(nexus, /summonSibling\("omarchy\.clipboard"\)/, 'image clips defer to the full manager')
assert.match(nexus, /command: \["mkdir", "-p", root\.gameModeDir, root\.settingsDir\]/,
  'directory creation is a fixed argument array')
assert.match(nexus, /command: \["rm", "-f", root\.gameModeFile\]/,
  'flag removal targets exactly the shared flag file')
assert.match(nexus, /command: \["hyprctl", "reload"\]/,
  'the reload is a fixed argument array')
assert.match(nexus, /command: \["hyprctl", "binds"\]/,
  'the keybind fetch reads the plain-text form (JSON blanks code: binds)')
assert.equal((nexus.match(/command: \[[^\]]*hyprctl[^\]]*\]/g) || []).length, 2,
  'hyprctl appears in exactly two commands: reload and binds')
assert.equal((nexus.match(/could not be started/g) || []).length, 4,
  'every failure-surfacing process has a start-failure guard')

// Keybind cheatsheet: text output parsed and filtered through the model;
// Escape clears the filter before it closes the panel.
assert.match(nexus, /NexusKeybindsModel\.parseBindsText/)
assert.match(nexus, /NexusKeybindsModel\.filterBinds/)
assert.match(nexus, /root\.page === NexusModel\.PAGE_KEYS && root\.keysQuery !== ""/,
  'Escape clears the keys filter first')

// Sensors: discovery once per open, self-labeling grep sampling, nvidia-smi
// only for an NVIDIA display GPU, absence degrades to a hidden row. The
// discovery stderr is swallowed (find -L reports harmless sysfs loops).
assert.match(nexus, /NexusSensorsModel\.discoveryCommand\(\)/)
assert.match(nexus, /NexusSensorsModel\.parseDiscovery/)
assert.match(nexus, /NexusSensorsModel\.selectSensors/)
assert.match(nexus, /NexusSensorsModel\.sampleCommand/)
assert.match(nexus, /NexusSensorsModel\.readings/)
assert.match(nexus, /sensorsSpec\.gpu\.kind === "nvidia" && nvidiaAvailable/,
  'nvidia-smi runs only when the display GPU needs it and it works')
assert.match(nexus, /root\.settings\.showSensors/, 'showSensors gates the card and cadence')

// Cava visualizer: config and frames through the model; the process runs
// only while open on Overview with media playing; a start failure (cava not
// installed) hides the strip instead of erroring.
assert.match(nexus, /NexusCavaModel\.buildConfig\(\)/)
assert.match(nexus, /NexusCavaModel\.parseFrame/)
assert.match(nexus, /NexusCavaModel\.cavaCommand/)
assert.match(nexus, /root\.mediaSelected !== null && root\.mediaSelected\.isPlaying/,
  'cava runs only while media actually plays')
assert.match(nexus, /if \(!running && !exitSeen\)\s+root\.cavaAvailable = false/,
  'a missing cava binary degrades cleanly')
assert.match(nexus, /root\.settings\.showVisualizer/)
assert.match(nexus, /command: \["cat", "\/proc\/stat", "\/proc\/meminfo", "\/proc\/net\/dev", "\/proc\/uptime"\]/,
  'cpu/mem/net/uptime sampling reads proc files with one argument array')
assert.match(nexus, /command: \["df", "-P", "-k", "\/"\]/,
  'storage sampling uses POSIX df with an argument array')
assert.match(nexus, /NexusMetricsModel\.parseSample/, 'sampler output parses through the tested model')
assert.match(nexus, /NexusMetricsModel\.parseDiskFree/, 'df output parses through the tested model')
assert.match(nexus, /NexusMetricsModel\.isStale/, 'stale readings are detected, not shown as fresh')

// Network throughput: rates, history, and sparkline points all through the
// tested model; rendering stays declarative.
assert.match(nexus, /NexusMetricsModel\.rateBetween/, 'rates derive from counter deltas in the model')
assert.match(nexus, /NexusMetricsModel\.pushHistory/, 'history capping goes through the model')
assert.match(nexus, /NexusMetricsModel\.sparklinePoints/, 'polyline points come from the model')
assert.match(nexus, /NexusMetricsModel\.formatRate/, 'rate labels format through the model')
assert.match(nexus, /PathPolyline/, 'the sparkline is a declarative polyline, not Canvas')
assert.match(nexus, /root\.settings\.showNetwork/, 'showNetwork gates the network card')

// Fetch row: static facts via one-shot async FileView reads (house pattern),
// uptime rides the existing sampler.
assert.match(nexus, /FileView \{/, 'static system facts use FileView, not processes')
assert.match(nexus, /\/proc\/sys\/kernel\/hostname/, 'hostname reads from proc')
assert.match(nexus, /\/proc\/sys\/kernel\/osrelease/, 'kernel version reads from proc')
assert.doesNotMatch(nexus, /blockLoading|blockAllReads/, 'FileView reads stay async like the rest of the shell')
assert.match(nexus, /NexusMetricsModel\.fetchLine/, 'the fetch line builds through the tested model')
assert.match(nexus, /root\.settings\.showFetch/, 'showFetch gates the fetch row')

// Battery is reactive UPower state with a no-battery fallback; never polled.
assert.match(nexus, /import Quickshell\.Services\.UPower/)
assert.match(nexus, /UPower\.displayDevice/, 'battery state comes from the display device')
assert.match(nexus, /NexusMetricsModel\.batteryDetail/, 'battery presence maps through the tested model')
assert.match(nexus, /timeToEmpty/, 'discharge estimates flow into the detail line')
assert.match(nexus, /timeToFull/, 'charge estimates flow into the detail line')

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

// Seek bar contract, per the verified Quickshell MPRIS semantics: the
// position tick emits positionChanged() only while open+selected+playing;
// absolute seeks clamp through the model and are double-capability-gated;
// the bar never trusts an unsupported length (it mirrors position).
assert.match(nexus, /root\.mediaSelected\.positionChanged\(\)/,
  'position refresh uses the sanctioned positionChanged() emit')
assert.match(nexus, /running: root\.opened && root\.mediaSelected !== null && root\.mediaSelected\.isPlaying/,
  'the position tick is triple-gated')
assert.match(nexus, /NexusMediaModel\.clampSeek/, 'seek targets clamp through the tested model')
assert.match(nexus, /player\.canSeek && player\.positionSupported/,
  'absolute position writes require both capability flags')
assert.match(nexus, /lengthSupported && mediaSelected\.length > 0/,
  'only a supported positive length drives the bar')
assert.match(nexus, /NexusMediaModel\.positionFraction/, 'bar fill fraction comes from the model')
assert.match(nexus, /NexusMediaModel\.formatPlaybackTime/, 'time labels format through the model')

// Player switcher: the manual override and the cycle share the deterministic
// order with selection.
assert.match(nexus, /mediaSerials, mediaOverrideKey\)/,
  'selection passes the manual override into the tested model')
assert.match(nexus, /NexusMediaModel\.cyclePlayer/, 'the chip cycles through the tested order')
assert.match(nexus, /NexusMediaModel\.countPlayers/, 'chip visibility uses the tested count')
assert.match(nexus, /mediaOverrideKey = ""/, 'the override clears on close')

// Controls contract: reactive state sources, one action path each,
// serialized pending dispatch, unavailable reasons.
assert.match(nexus, /import Quickshell\.Services\.Pipewire/, 'audio uses reactive PipeWire state')
assert.match(nexus, /objects: root\.opened \? \[root\.audioSink, root\.audioSource\]/,
  'PipeWire nodes are bound only while the panel is open')
assert.match(nexus, /Math\.max\(0, Math\.min\(1, Number\(value\)/, 'volume writes are clamped')
assert.match(nexus, /serviceFor\("omarchy\.notifications"\)/, 'DND uses the first-party service')
assert.match(nexus, /serviceFor\("omarchy\.nightlight"\)/, 'night light uses the first-party service')
assert.match(nexus, /serviceFor\("omarchy\.idle"\)/, 'stay awake uses the first-party service')
assert.match(nexus, /if \(!opened \|\| pendingActionName !== ""\)\s+return/,
  'pending actions are serialized and cannot overlap')
assert.match(nexus, /service unavailable|No output device|No input device/i,
  'unavailable controls show a reason')

// Settings contract: the shell.json layer stays read-only and validated;
// the Settings page writes only the state file, through the tested
// serializer, with the writer cache tracking disk.
assert.match(nexus, /NexusSettingsModel\.readSettings/, 'settings go through the tested reader')
assert.match(nexus, /NexusSettingsModel\.applyState/, 'the state layer merges through the model')
assert.match(nexus, /NexusSettingsModel\.parseState/, 'state text parses through the model')
assert.match(nexus, /NexusSettingsModel\.buildStateJson/, 'state writes serialize through the model')
assert.match(nexus, /NexusSettingsModel\.statePath/, 'the state file path comes from the model')
assert.doesNotMatch(nexus, /shellConfig\.plugins\s*=|updateEntryInline/,
  'Nexus never writes shell.json')
assert.match(nexus, /normalizePayload\(payloadJson, root\.settings\.defaultPage\)/,
  'defaultPage applies only when the payload names no page')
assert.match(nexus, /settings\.preferredMediaIdentity, mediaSerials/,
  'media preference flows from validated settings')
assert.match(nexus, /root\.settings\.showMedia/, 'showMedia gates the media card')
assert.match(nexus, /root\.settings\.showMetrics/, 'showMetrics gates the metric grid')
assert.match(nexus, /visible: root\.settings\.showCpu/, 'per-meter visibility is settings-driven')
assert.match(nexus, /visible: root\.settings\.showBattery/, 'the battery meter can be hidden')

// Game mode inside Nexus: the flag file is shared with community.game-mode,
// content comes from the configured strip set, and an empty set refuses to
// toggle instead of writing a flag that strips nothing.
assert.match(nexus, /NexusGameModeModel\.flagPath/, 'the shared flag path comes from the model')
assert.match(nexus, /NexusGameModeModel\.buildFlagContent\(settings\)/,
  'the strip set flows from validated settings')
assert.match(nexus, /gameModeFlagContent === null/, 'an empty strip set disables the toggle')
assert.match(nexus, /flagWriter\.reload\(\)/,
  'the writer cache re-reads disk so a re-enable is never a silent no-op')
assert.match(nexus, /watchChanges: true/,
  'external flag/state changes are noticed while open')

// Bar widget: drives only the host toggle surface and tolerates a null bar.
const widget = read('NexusBarWidget.qml')
assert.match(widget, /^BarWidget \{/m, 'the bar entry point is the shared BarWidget base')
assert.match(widget, /isPluginOpen\("community\.omarchy-nexus"\)/,
  'the active state reads the host open map')
assert.match(widget, /shellRoot\.toggle\("community\.omarchy-nexus", "\{\}"\)/,
  'the click goes through the host toggle')
assert.match(widget, /bar \? bar\.shell : null/, 'a null bar at construction is tolerated')
assert.doesNotMatch(widget, /\bProcess\s*\{|\bTimer\s*\{/, 'the widget is purely reactive')

// Menu delegation: close first, then open the Omarchy menu in-process.
assert.match(nexus, /requestClose\(\);?\s*if \(host && typeof host\.summon === "function"\)/,
  'delegated actions close Nexus before opening the menu')
assert.match(nexus,
  /host\.summon\("omarchy\.menu", JSON\.stringify\(\{\s*"?menu"?: String\(route\)/,
  'delegation goes through the shell menu with a fixed route')
assert.match(nexus, /openMenuRoute\(NexusModel\.MENU_ROUTES\.theme\)/, 'theme routes to the existing selector')
assert.match(nexus, /openMenuRoute\(NexusModel\.MENU_ROUTES\.background\)/, 'background routes to the existing selector')
assert.match(nexus, /openMenuRoute\(NexusModel\.MENU_ROUTES\.capture\)/, 'capture delegates to the existing flow')
assert.match(nexus, /openMenuRoute\(NexusModel\.MENU_ROUTES\.power\)/,
  'power opens the system menu, whose second click is the confirmation')

// Bluetooth: native reactive adapter state, no CLI polling.
assert.match(nexus, /import Quickshell\.Bluetooth/)
assert.match(nexus, /Bluetooth\.defaultAdapter/, 'bluetooth reads the default adapter reactively')
assert.match(nexus, /No Bluetooth adapter/, 'missing adapter shows its reason')

// Beauty pass: bounded width, accent-restrained hero, declarative arc meters.
assert.match(nexus, /Math\.min\(Style\.space\(420\), 560\)/,
  'preferred width stays inside the 360-560 logical band under spacing scale')
assert.match(nexus, /NexusArcMeter\s*\{/, 'metrics render with the extracted arc-meter component')
assert.match(nexus, /PathAngleArc/, 'arcs are declarative Shapes, not Canvas repaints')
assert.doesNotMatch(nexus, /\bCanvas\s*\{/, 'no Canvas repaint loops')

// Interaction polish: wheel-cycled tabs, directional page slide, and a
// per-page keyboard cursor that reaches every actionable row.
assert.match(nexus, /WheelHandler \{/, 'the tab row cycles on mouse wheel')
assert.match(nexus, /function setPage\(next\)/, 'page changes route through setPage')
assert.match(nexus, /pageShift/, 'page content slides directionally')
assert.match(nexus, /readonly property int lastCursorIndex/, 'the cursor is page-aware')
assert.match(nexus,
  /onLastCursorIndexChanged:\s*\{\s*if \(controlCursor > lastCursorIndex\)\s*\{?\s*controlCursor = lastCursorIndex/,
  'the cursor clamps when its page loses rows')
assert.match(nexus, /hasCursor: root\.controlCursor === NexusModel\.STYLE_ROWS\.THEME && root\.page === NexusModel\.PAGE_STYLE/,
  'style rows carry a page-scoped keyboard cursor')
assert.match(nexus, /hasCursor: root\.controlCursor === NexusModel\.OVERVIEW_ROWS\.PLAYER_CHIP && root\.page === NexusModel\.PAGE_OVERVIEW/,
  'the overview player-cycle row is a cursor row')
assert.match(nexus, /hasCursor: root\.controlCursor === NexusModel\.CONTROLS_ROWS\.CAPTURE && root\.page === NexusModel\.PAGE_CONTROLS/,
  'the capture row is a cursor row')
assert.match(nexus, /hasCursor: root\.controlCursor === NexusModel\.CONTROLS_ROWS\.POWER && root\.page === NexusModel\.PAGE_CONTROLS/,
  'the power row is a cursor row')

// Suite integrations: read-only views over sibling state files, watch-
// driven, zero subprocesses; absent files hide their cards.
assert.match(nexus, /NexusSuiteModel\.screenTimeSummary/)
assert.match(nexus, /NexusSuiteModel\.parseNotifications/)
assert.match(nexus, /NexusAgendaModel\.mergeAgendas/)
assert.match(nexus, /NexusAgendaModel\.upcoming/)
assert.match(nexus, /NexusPomodoroModel\.parseState/)
assert.match(nexus, /NexusPomodoroModel\.resolveState/, 'expired sessions resolve while open')
assert.match(nexus, /root\.settings\.showScreenTime/)
assert.match(nexus, /root\.settings\.showNextEvent/)
assert.match(nexus, /summonSibling/, 'cross-plugin hand-offs close Nexus first')
assert.match(nexus, /clearPast/, 'history clearing goes through the first-party service')
assert.match(nexus, /running: root\.notesDirty/, 'the autosave debounce only runs while dirty')
assert.match(nexus, /property string notesText/, 'the notes state owner exposes editor text')
assert.match(nexus, /onNotesTextChanged/, 'the extracted editor follows file-driven note changes')
assert.match(nexus, /NexusSuiteModel\.GAME_MODE_PRESETS/)
assert.match(nexusEntry, /NexusSettingsRows\.rows\(\)/,
  'settings row metadata stays outside the lifecycle facade')
assert.match(nexus, /NexusModel\.pageIcon/, 'narrow pages render icon-only tabs')
assert.equal((nexus.match(/hasCursor: root\.controlCursor === NexusModel\.STYLE_ROWS\.[A-Z_]+ && root\.page === NexusModel\.PAGE_STYLE/g) || []).length, 2,
  'both style rows are cursor rows')
assert.match(nexus, /if \(event\.angleDelta\.y === 0\)\s+return/,
  'horizontal wheel deltas never cycle pages')
assert.match(nexus, /if \(!consumed\)\s*\n\s*root\.setPage/,
  'Left\/Right falls back to page cycling when the focused row rejects it')

// Theme integration comes from shared tokens only.
assert.match(nexus, /import qs\.Commons/, 'uses shared Color/Style/Border singletons')
assert.match(nexus, /import qs\.Ui/, 'uses shared UI components')
assert.doesNotMatch(nexus, /#[0-9a-fA-F]{6}/, 'no hard-coded colors')

console.log('ok - nexus plugin contract')
