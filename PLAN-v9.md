# Omarchy Nexus — V9 implementation plan

Status: active; Milestone 1 scaffold implemented and statically green; live
checks pending a user-invoked test/live run
Supersedes: PLAN-v8.md
Review basis: Omarchy Quattro checkout /home/user/omarchy/code at 12af1883,
re-verified against the source on 2026-08-02
Plugin id: community.omarchy-nexus
Source workspace: /home/user/omarchy/plugins/community.omarchy-nexus

## What changed from V8

V8 sections 1–4 specified a transactional staging harness — per-uid lifecycle
locks with boot-id and inode continuity, fsync-durable recovery records with
eleven mutation phases, split authorization lanes, and a fault-injection
matrix — as a prerequisite for any live staging. That machinery is replaced by
one guarded script, test/live, for these reasons:

- The complete job is: copy one directory into the user plugin directory, add
  one entry to shell.json, run bounded checks, remove both. The realistic
  failure exposure is one stale config entry and one leftover directory, both
  under the user's own home.
- The sibling plugins community.window-switcher and community.smart-dock
  shipped complete with static test suites only and no staging controller.
  They are the working precedent for this exact host.
- shell.json is byte-backed-up before mutation and never blindly restored;
  cleanup removes only the exact run-created entry and reports any other
  difference. Anything test/live cannot recover (SIGKILL mid-run) is fixed by
  hand in seconds using the timestamped backup it already wrote.
- The registry watches the plugin directory with inotify and rescans on
  change (PluginRegistry.qml:603-627), so iteration after install is cheap
  and does not need orchestration.

Correction from live Milestone 2 work: the inotify rescan does not swap
running plugin code. finishPluginReload clears the QML component cache only
when `Qt.clearComponentCache` exists (shell.qml:757), and this Quickshell
build does not expose it, so the engine keeps serving the previously compiled
component for an unchanged URL. After syncing changed QML into the installed
copy, run `omarchy restart shell` to load it; `status()` fields (for example
metricsActive) distinguish the running version.

Everything else — payload normalization, the modal surface model, monitor
resolution, the visual and keyboard contract, configuration access, the
integration matrix, the deterministic MPRIS model, and the keepLoaded
benchmark — carries forward from V8 with the corrections below.

## Verified host contract

Facts confirmed in the Quattro source at 12af1883; paths are relative to
/home/user/omarchy/code.

- Third-party discovery is exactly
  ~/.config/omarchy/plugins/<id>/manifest.json, top level only
  (shell/services/PluginRegistry.qml:651-655). The directory name is not
  checked against the manifest id.
- Manifest validation requires schemaVersion === 1 (strict), id, name,
  version, kinds, entryPoints; keepLoaded is optional and read as
  `=== true` (PluginRegistry.qml:43-91, shell/shell.qml:600).
- The host marks a plugin open before delivering open(), discards the return
  value, and only warns when open() throws (shell.qml:462-476, 541-556).
  Payloads are opaque strings, never parsed by the host, and queue FIFO; for
  a non-keepLoaded panel, open() is delivered asynchronously after summon
  already returned ok.
- summon refuses (`unknown`) for an unknown or not-enabled plugin
  (shell.qml:443-454): live testing genuinely requires a real install plus a
  shell.json plugins[] entry.
- hide() calls the plugin's close() before clearing the host's open map;
  isPluginOpen prefers the plugin's own `opened` property (shell.qml:489-507),
  so `opened` must stay accurate or toggle desyncs.
- Injected properties (only when declared on the root): omarchyPath, shell,
  manifest, barWidgetRegistry, pluginRegistry, service (shell.qml:627-639).
  There is no screen injection and no settings injection.
- Enable of an unknown manifest is rejected; disable of an unknown or
  vanished manifest proceeds and splices the plugins[] entry
  (PluginRegistry.qml:424-427, 497-499). Caveat: disable answers ok even when
  no entry existed, so cleanup verification must inspect shell.json, not
  trust the IPC reply.
- Symlink rejection lives only in the CLI validator
  (bin/omarchy-plugin-validate:110-115); ship real files.
- IPC surface used by the tooling: ping, rescanPlugins,
  setPluginEnabled(id, true|false), summon(id, payload), hide(id),
  toggle(id, payload), call(id, method, arg), listPlugins
  (shell.qml:872-1006). There is no plugin-level health command; call()
  answers "unknown" when the plugin is not loaded, which doubles as an
  unload check.
- Screen-lock probe: `omarchy-shell lock isLocked`. Update-lock probe: a
  non-blocking flock attempt on $XDG_RUNTIME_DIR/omarchy-update.lock
  (pattern in bin/omarchy-migrate-notify:7-14).
- Theming comes from qs.Commons (Color, Style, Border, Util) and qs.Ui
  (BorderSurface, Button, Toggle, PanelSeparator, PanelKeyCatcher, and
  others). The live component reference is
  `omarchy-shell shell summon omarchy.dev-gallery '{}'`.
- First-party cockpit-relevant services: omarchy.media (direct Quickshell
  MPRIS), omarchy.battery (UPower), PipeWire audio panel, notifications DND
  (dndState/toggleDnd), nightlight and idle IPC targets. There is no
  first-party CPU/memory/storage sampler; Nexus owns its own.

## Test routing

### test/all — static, default, CI-safe

Runs Node model tests, Node contract tests, `omarchy plugin validate`, and
qmllint against $OMARCHY_PATH/shell. Never writes below ~/.config/omarchy,
never touches the running shell. This mirrors the sibling plugins' suites.
Status: implemented and green.

### test/live — guarded primary-session check

One script, one confirmation flag (--confirm-live), no environment opt-ins.
Sequence:

1. Refuse without the flag; refuse when omarchy-shell or jq is missing, the
   shell ping fails, the screen is locked, or the update lock is held.
2. Fresh-only: refuse when the target directory exists, shell.json contains
   the id, or the live registry knows the id. The script never replaces,
   backs up, or removes an existing installation.
3. Byte-backup shell.json to test-output/shell.json.<stamp>.backup.
4. Install trap cleanup (EXIT, INT, TERM), then copy the workspace to
   ~/.config/omarchy/plugins/community.omarchy-nexus (excluding .git and
   test-output), rescan, enable.
5. Bounded checks: cold summon with {} then status(); repeated summon with
   {"page":"controls"} then status(); malformed-payload summon normalizes to
   overview; hide; call() must answer "unknown" (proves unload).
6. Cleanup (also on failure/interrupt): disable, remove the staged directory,
   rescan, verify via jq that no Nexus entry remains, and report — without
   overwriting — any remaining byte difference against the backup.

Status: implemented; not yet run. Runs only when the user invokes it.

## Product contract

### Payload normalization

The host marks the plugin open before calling open and ignores the result, so
Nexus never declines to show a surface. NexusModel.normalizePayload treats
malformed JSON, empty payloads, arrays, and primitives as an empty object,
accepts only the whitelisted page field (exact match against overview,
controls, style), maps everything else to overview, and ignores unknown
fields. A repeated open while visible updates page and target screen without
creating a second surface. Payload values are session-scoped, never persisted.

### Surface and input-region model

A modal full-output overlay owns the target screen while open:

- transparent PanelWindow on the overlay layer, ExclusionMode.Ignore, no
  exclusive work area;
- themed scrim with an outside-click area that calls requestClose;
- right-aligned BorderSurface card that accepts panel interaction;
- exclusive keyboard focus only while logically open
  (keyboardFocus: opened ? Exclusive : None);
- close is immediate: no close animation, so focus and input release with
  the surface;
- open uses a 180 ms right-to-left slide plus fade;
- Escape, outside click, and any close affordance call shell.hide via
  requestClose; a closingFromHost guard prevents host/self close recursion;
- the root is an Item exposing `property bool opened` and `function status()`
  returning opened, page, screen, metrics-active state, pending action, and
  focus role as JSON.

### Monitor resolution and geometry

Resolve one target screen at open time: Hyprland.focusedMonitor matched into
Quickshell.screens, else the active toplevel's first screen, else the first
real screen. If the screen disappears while open, retarget or close. Never
mount a surface per monitor.

Card geometry: preferred width Style.space(420) capped at 42% of a wide
output and at output width minus margins; full height between safe margins;
internal scrolling for overflow (from Milestone 2). Milestone 1 uses
conservative token fallback margins (bar size + gaps on each edge); live
bar-edge geometry replaces them during Milestone 2 visual checks.

### Visual and keyboard contract

Dark, shell-themed right-side cockpit using menu surface tokens: hero card
with time, date, and workspace context; tabs for Overview, Controls, Style;
metric cards below the hero (Milestone 2); control rows with normal, hover,
focus, selected, pending, disabled, and error states (Milestone 3). No
constant animation while closed or idle — the clock timer runs only while
opened. Use Color, Style, Border, BorderSurface; never copy Caelestia code,
structure, colors, artwork, shaders, icons, or text.

Keyboard: Tab/Shift+Tab and Left/Right move through tabs (and controls, once
they exist, in visual order); Enter/Space activates; Escape closes via
shell.hide; pending actions cannot trigger twice. A fresh open focuses the
selected tab after the surface is ready; repeated summons preserve a valid
focused control when the page is unchanged and refocus the tab when it
changes; remembered focus clears on close.

### Manifest and configuration

The shipped manifest omits keepLoaded (see benchmark). Optional settings live
in the canonical top-level plugins[] entry:

    { "id": "community.omarchy-nexus", "defaultPage": "overview",
      "monitor": "focused", "showMedia": true, "showMetrics": true,
      "preferredMediaIdentity": "" }

Milestone 1 uses only the id. A later tested helper reads
shell.shellConfig.plugins, applies defaults, reacts to changes, and never
writes settings during open. Before distribution: replace the placeholder
author, keep the MIT LICENSE current, and initialize a Git repository
(omarchy plugin add/update expect Git).

### Integration contracts (Milestones 2–3)

Every control has one authoritative state source, one action path, a pending
state, and explicit failure/refresh behavior.

- Media: one direct Quickshell MPRIS adapter; never poll omarchy.media IPC in
  parallel.
- Battery: first-party battery service with a normal no-battery fallback.
- CPU/memory/storage: one bounded Nexus-owned sampler with documented units,
  cadence, timeout, and stale-state behavior; dormant while closed.
- Audio/microphone: reactive PipeWire state and one matching action path.
- DND, night light, stay awake: first-party reactive services where exposed;
  unavailable controls show the reason.
- Wallpaper and theme: close Nexus and delegate to the existing selectors.

Deferred: weather, network detail, Bluetooth, Tailscale/VPN, recording,
power actions, notifications, lyrics, CAVA, lock integration, persistent
layouts, drag customization.

Subprocesses use argument arrays and never interpolate titles, workspace
names, monitor names, URLs, or paths into shell strings. Pending actions are
serialized, refresh authoritative state on completion, and surface errors
instead of silently reverting.

### Deterministic MPRIS model

Carried unchanged from V8 section 12; it is the spec for the Milestone 2
media adapter. Summary of the invariants:

- Normalized player records: identityKey, preferredIdentity (from validated
  settings, same normalizer), sourceKey (exact, for deduplication only),
  isProxy (explicit alias table), activitySerial (monotonic, never
  wall-clock). No fuzzy or substring matching.
- sourceKey precedence: exact proxy/bus alias, normalized desktopEntry,
  normalized identity, exact bus name. Same source only on exact match.
- activitySerial increments only on transition into Playing, track change
  while Playing, successful user action on that player, or discovery of an
  already-playing player.
- Selection phase 1 picks one representative per sourceKey group (real
  players beat proxies; a vanished real player lets its proxy promote).
  Phase 2 orders representatives: playback state, exact preferredIdentity,
  larger activitySerial, identityKey byte order, bus-name byte order.
- Actions route only to the selected representative and only when it reports
  the capability. Artwork allows file, image, qrc, http, https schemes only,
  with bounded retries and a themed placeholder; artwork URLs never reach
  commands or configuration.
- Fixtures: playing proxy vs paused real, preferred proxy vs non-preferred
  real, proxy-only groups, multiple real records, real-player disappearance
  with proxy promotion, and permutation-stable ordering.

### keepLoaded benchmark

At the end of Milestone 2, measure 20 cold summon cycles from IPC invocation
to first usable state; record p50/p95, shell log errors, and closed-state CPU
and timer activity. Target: p95 ≤ 250 ms, no recurring closed-state work, no
stale surface after close. Keep keepLoaded omitted while the target is met;
add it only from measured need with all background activity dormant while
closed.

## Milestones

### Milestone 0 — contract verification (complete)

The host contract was verified in-source at 12af1883; the findings are the
"Verified host contract" section above.

### Milestone 1 — minimal installable panel (scaffold complete)

Implemented: LICENSE, manifest.json, Nexus.qml (Item root, payload
normalization through NexusModel, open/close/status, closingFromHost guard,
monitor targeting with retarget-on-screen-change, modal overlay with scrim
and outside click, right-aligned themed card, hero clock/date/workspace,
page tabs with keyboard cycling, Escape close, open-only entrance animation,
opened-gated clock timer), model/NexusModel.js, test/all (green), test/live
(implemented, not yet run).

Remaining to exit Milestone 1:

- a user-invoked `test/live --confirm-live` run passes on the primary
  session;
- visual inspection of the summoned panel (placement, margins, theme,
  entrance motion, Escape/outside-click close) on the current monitor
  layout;
- fix-ups the live run surfaces.

### Milestone 2 — overview vertical slice (complete)

Implemented and live-verified on the primary session:

- direct MPRIS adapter per the deterministic model (NexusMediaModel.js) with
  the full fixture suite in test/media.test.js; hero media card with
  whitelisted artwork, capability-gated controls, and a no-media state;
- one bounded sampler (NexusMetricsModel.js, test/metrics.test.js): cpu/mem
  via one `cat /proc/stat /proc/meminfo` every 2 s, storage via
  `df -P -k /` every 30 s, argument arrays only, running exactly while open;
  readings older than 3x cadence render stale;
- battery card from reactive UPower state with the no-battery fallback;
- bar-aware safe margins from shell.barConfig.position, shell.bar.barSize,
  and barHidden (only the bar's edge gets clearance);
- content-fitted card height with internal Flickable scrolling;
- keepLoaded benchmark (test/benchmark, 20 cold cycles, 2026-08-02):
  p50 84 ms, p95 88 ms against the 250 ms target; closed-state shell CPU
  0.00% over 5 s. keepLoaded stays omitted.

### Milestone 3 — controls and style (complete)

Implemented and live-verified on the primary session:

- audio and microphone through reactive PipeWire state (defaultAudioSink /
  defaultAudioSource, PwObjectTracker bound only while open) with one action
  path each: clamped volume writes, mute toggles;
- DND, night light, and stay awake through the first-party reactive services
  (serviceFor omarchy.notifications / omarchy.nightlight / omarchy.idle),
  resolved at each open; absent services render a disabled control with its
  unavailable reason. The DND path was verified live end-to-end (on -> off ->
  on, restored exactly);
- serialized pending actions: one dispatch at a time through
  dispatchControl, controls disabled while pending, pendingAction surfaced
  in status();
- controls keyboard cursor: Down/Up walks the six rows, Enter/Space
  activates, Left/Right adjusts the focused volume slider, hover and
  keyboard share one cursor; focus resets on page change and close;
- Style page delegates in-process: closes Nexus, then
  shell.summon("omarchy.menu", {menu: "style.theme" | "style.background"});
  fixed routes, no subprocess;
- validated settings reader (NexusSettingsModel.js, test/settings.test.js):
  defaultPage, monitor, showMedia, showMetrics, preferredMediaIdentity read
  from the canonical plugins[] entry, reactive to shell.json changes, never
  written during open.

### Milestone 4 — live visual validation and expansion

User-authorized test/live runs covering repeated summon, multi-monitor
layouts, scaling, vertical/right-bar placement, keyboard navigation, and
teardown; monitor-disappearance fixtures (physical hotplug only when the
user directs it); then expansion features, each with its own contract.

## Validation gates

- test/all green (manifest, models, contract, qmllint) — required for every
  change; CI runs only this.
- test/live green when the user invokes it: bounded checks pass, cleanup
  leaves no Nexus directory, registry record, or shell.json entry, and any
  non-Nexus shell.json difference is reported, never overwritten.
- Shell ping ok and no new loader/QML errors in shell logs after live runs.
- Visual artifacts are inspected, not merely captured.
- No route writes outside the workspace except test/live's declared staging
  path and shell.json entry.

## Current next step

Milestones 0–3 are complete; the plugin is installed, enabled, bound to
Super+Shift+J, benchmarked, and pushed to github.com/devmobasa/omarchy-nexus
(private). Next is Milestone 4: user-authorized live visual validation
(multi-monitor, scaling, vertical/right-bar placement, repeated summon,
teardown) and expansion features, each behind its own contract. Before
public distribution: replace the placeholder manifest author and consider
pruning the historical PLAN files.
