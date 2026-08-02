# Omarchy Nexus — V10: v0.2 feature pass + game-mode sibling plugin

Status: complete; all five features and the game-mode sibling implemented,
statically green, and live-verified 2026-08-02
Builds on: [PLAN-v9.md](PLAN-v9.md) (all v9 milestones complete and shipped)
Scope: five Nexus v0.2 features and a new sibling plugin, community.game-mode

## Design stances carried forward

Everything from V9 holds: reactive state over polling, argument-array
subprocesses only, models tested in Node, contract pins for every load-bearing
choice, dormant while closed, shared theme tokens only, no Canvas, and
`omarchy restart shell` after every sync (hot reload cannot swap compiled
QML).

New stance for v0.2: the bounded sampler may grow *files*, never *processes*.
The single `cat` sampler reads /proc/stat, /proc/meminfo, /proc/net/dev and
/proc/uptime in one invocation; static facts (hostname, kernel) are one-shot
FileView reads while open, not sampled at all.

## Feature 1 — media seek bar + player switcher

Seek bar under the title/artist row of the media block:

- elapsed label left, total right, a thin rounded progress track between,
  accent fill, subtle handle on hover; click or drag seeks when the player
  reports canSeek, otherwise the bar is display-only.
- MPRIS position does not tick continuously in Quickshell; a 1 s Timer,
  running only while the panel is open AND a player is selected AND playing,
  nudges the position read. Exact refresh API per the research notes below.
- All math through the tested model: NexusMediaModel.formatPlaybackTime
  (m:ss / h:mm:ss), NexusMediaModel.clampSeek (fraction x length, clamped,
  null when unseekable/lengthless).

Player switcher chip beside the media title (visible only when more than one
player is active): shows the selected player's identity, click cycles to the
next player in the deterministic order. Mechanics:

- NexusMediaModel.selectPlayer gains an optional override key argument; a
  manual override wins while that player still exists, then falls back to
  the deterministic choice. Override clears on panel close.
- NexusMediaModel.cyclePlayer(records, currentKey) returns the next source
  key in the same total order selectPlayer uses — no separate ordering to
  drift out of sync.

## Feature 2 — network throughput meter

- Sampler command becomes `cat /proc/stat /proc/meminfo /proc/net/dev
  /proc/uptime` — still exactly one process on the 2 s cadence.
- NexusMetricsModel.parseSample parses the concatenated stream. /proc/net/dev
  interface lines are `iface: rx_bytes ... tx_bytes(9th numeric field) ...`;
  virtual interfaces are excluded by name prefix (loopback, container
  bridges/veths, tunnels, VPNs, bonds — see the research notes for why) plus
  any dotted VLAN sub-interface; everything else is summed. /proc/uptime is
  the unique line of two decimal floats.
- Rates: rateBetween(prevBytes, prevMs, curBytes, curMs) → bytes/second,
  null across resets (counter went backwards) or zero/negative dt.
- History: pushHistory(list, value, cap) keeps the last 30 samples (~60 s)
  per direction. sparklinePoints(history, width, height, sharedMax)
  normalises both series against a shared max (floored at NET_SCALE_FLOOR
  so an idle link hugs the baseline) for PathPolyline point lists.
- UI: a full-width card under the metric grid — two declarative Shapes
  polylines (download in accent, upload in secondary), live labels via
  formatRate (B/s → KiB/s → MiB/s → GiB/s), stale dimming like the other
  metrics.
- New validated setting showNetwork (default true) gates the card.

## Feature 3 — battery time detail

- UPower time-to-empty / time-to-full (property names and units per the
  research notes; unknown values are reported as 0 and must fall back).
- batteryDetail grows the estimate: "On battery — 2 h 13 m left",
  "Charging — 45 m to full", with the existing no-battery fallbacks. The
  device's own state enum is primary (threshold-parked batteries read
  "Holding"/"Plugged in — not charging", never a fake "Charging").
  formatDuration(seconds) caps at two units.

## Feature 4 — system fetch row

A muted one-liner under the hero: `hostname · kernel · up 3 d 4 h`.

- hostname and kernel from one-shot FileView reads of
  /proc/sys/kernel/hostname and /proc/sys/kernel/osrelease, loaded only
  while open.
- uptime from the sampler (already reading /proc/uptime for free).
- NexusMetricsModel.fetchLine(host, kernel, uptimeSeconds) builds the string,
  dropping missing parts gracefully.
- New validated setting showFetch (default true).

## Feature 5 — interaction polish

- Mouse wheel over the tab row cycles pages (adjacentPage, same wrap rules).
- Directional page slide: on page change the content column slides in from
  the direction of travel (±20 logical px translate + fade, ~160 ms
  OutCubic). Direction from the adjacency model, wrap-aware.
- Full keyboard reach. The single controls cursor becomes a per-page cursor:
  - overview: media transport row (Left/Right = previous/next track,
    Enter/Space = play/pause), seek row (Left/Right = ±5 s), player chip
    (Enter cycles) — rows exist only when their controls do;
  - controls: the existing seven rows plus Capture and Power as rows 7-8;
  - style: Theme and Background as rows 0-1.
  Rule: Left/Right acts on the focused row when the row can use it
  (slider, seek, transport), otherwise cycles pages. Tab/Shift+Tab always
  cycles pages. Cursor resets on page change and close, as before.

## Sibling plugin — community.game-mode

A bar-widget plugin (separate repo-ready directory, same standards as
Nexus): one toggle that strips compositor effects for gaming and restores
them exactly.

- On enable: `mkdir -p` the sourced toggles directory, write the Lua flag
  file `community-game-mode.lua` (animations off, blur off, shadows off,
  gaps 0, rounding 0, tearing allowed; the focus border is left alone) with
  an atomic FileView write, then `hyprctl reload`. `hyprctl keyword` is not
  used — see the research note below.
- On disable: `rm -f` the flag file, then `hyprctl reload`. Removing the
  file is the exact restore, so no original values are ever read or stored.
- Subprocesses are argument arrays, fired only on user action — never
  polled. The flag file persists, so game mode survives shell restarts and
  reboots; a watching FileView re-probes it at construction and after each
  toggle (broadcast), so multi-instance state cannot diverge.
- Model (GameModeModel.js, Node-tested): flag basename, flag content, and
  XDG_STATE_HOME/HOME-aware state directory and flag path resolution.
- UI: a BarIconButton gamepad glyph in the bar's active color while on,
  tooltip with state and failure reasons; IPC-callable toggle/status for
  keybindings.
- Exact manifest kind, entry point, and injections per the bar-widget
  research notes.

## Validation

- All new model functions get fixture tests; contract pins updated: sampler
  command array (4 files), opened-gated timer count, FileView reads, wheel
  handler, per-page cursor dispatch, seek/cycle through tested model
  functions, still no Canvas / no shell-string subprocesses (Nexus).
- game-mode gets its own test/all (node tests, omarchy plugin validate,
  qmllint) and contract pins (argument arrays, no polling timers).
- Live: sync, restart shell, verify each feature on the session, run
  test/stress again, benchmark spot-check (media timer must not run while
  closed).
- Adversarial review workflow over the full diff before commit.

## Research notes (verified against this machine before implementation)

- MPRIS (quickshell-git 0.3.0.r18): `position`/`length` are seconds;
  position does not update reactively — the sanctioned refresh is emitting
  `player.positionChanged()` from a gated Timer (local extrapolation, no
  D-Bus). Absolute seek = write `position` (requires canSeek AND
  positionSupported); relative `seek(offset)` requires only canSeek. When
  lengthSupported is false, `length` mirrors `position` — a naive ratio
  pins to 100%, so the bar gates on a supported positive length.
- UPower: `timeToEmpty`/`timeToFull` in whole seconds; 0 means unknown or
  not-applicable, never -1; `percentage` is 0-1 in QML (scaled from the
  0-100 wire value).
- PathPolyline lives in QtQuick (not QtQuick.Shapes) and takes a JS array
  of Qt.point; verified at runtime. WheelHandler present since Qt 5.14.
- FileView: `text()`/`data()` are functions, not reactive properties; the
  default read is async (the shell's house pattern — no blocking reads
  anywhere in Quattro), so the fetch row uses onLoaded callbacks.
- /proc/net/dev: rx_bytes is numeric field 1, tx_bytes field 9. On this
  machine loopback alone carries ~3x the real NIC's bytes and tun0 mirrors
  eno1, so the parser excludes lo/docker/br-/veth/tun/tap/virbr/vnet/wg
  prefixes rather than just lo.
- hyprctl: `keyword` is unreliable under Omarchy's Lua config provider.
  The house mechanism (omarchy-hyprland-toggle) is a Lua flag file in
  ~/.local/state/omarchy/toggles/hypr/ plus `hyprctl reload` — game mode
  adopts it wholesale, which also makes restore exact and state
  restart-proof with zero bookkeeping.
- Bar-widget contract: kinds ["bar-widget"], entryPoints.barWidget,
  BarWidget root (bar/moduleName/settings injected; must tolerate a null
  bar at construction), BarIconButton for the glyph, `broadcast(method)`
  for multi-instance sync, own IpcHandler for CLI calls (`shell call` does
  not reach bar widgets), per-instance settings inline on the layout entry.

## Outcome

Everything above is implemented: Nexus 0.2.0 (seek bar + player switcher,
network sparkline, battery time estimates, fetch row, wheel tabs +
directional slide + full per-page keyboard reach) and community.game-mode
0.1.0 (flag-file toggle, IPC surface, its own model/contract suite).
Live-verified: page cycling, 9-cycle stress with unload proof, game-mode
on/off round trip with exact option restore (animations, gaps, blur).
