# Omarchy Nexus

A themed desktop cockpit panel for [Omarchy](https://omarchy.org) v4
("Quattro"): clock, media, system state, quick controls, and style — one
keystroke away, fully dormant when closed.

## Features

- **Header (every page)** — accent clock, date, and focused workspace beside
  now-playing artwork (accent glow while something plays), over a quiet
  hostname · kernel · uptime line.
- **Overview** — media with a draggable seek bar (elapsed/total labels,
  capability-gated) and a player-switcher chip when several players are
  active; capability-gated transport; CPU, memory, storage, and battery arc
  meters — battery with time-to-empty/full when UPower knows it; live
  network throughput as a dual down/up sparkline (loopback, container
  bridges, tunnels, and other common virtual interfaces are excluded so
  their mirrored traffic does not double-count).
- **Controls** — output volume slider, output/input mute, Do Not Disturb,
  night light, stay awake, Bluetooth, and Game Mode (strip compositor
  effects via Omarchy's toggle mechanism — shared state with the
  [community.game-mode](https://github.com/devmobasa/omarchy-game-mode) bar
  widget), plus Capture and Power quick actions that hand off to the
  Omarchy menu (its own second click confirms destructive power actions).
- **Style** — theme and background pickers, delegated to the built-in
  Omarchy selectors.
- **Keys** (parked) — a searchable cheatsheet of every live Hyprland keybind
  (from `hyprctl binds`, so it never goes stale). Currently unlisted from the
  tab row; re-add `PAGE_KEYS` to `PAGES` in `model/NexusModel.js` to restore.
- **Media page** — every active player with its own transport, selection,
  and per-player Left/Right track skipping.
- **Notes** — one quick markdown scratch file with debounced autosave.
- **Clipboard** — recent text clips, click to copy back; image clips hand
  off to the full first-party manager.
- **Minimizer** — windows stashed on `special:minimized` (pairs with a
  Super+M minimize-to-tray script setup), newest first with their origin
  workspace, a hover/cursor preview (the scripts' pre-captured thumbnail,
  falling back to a live toplevel capture), and click/Enter to restore to
  the current workspace. The scripts' sidecar files are read-only to Nexus.
- **Alerts** — pending and recent notification history with one-click
  clearing through the first-party service.
- **Sensors** — CPU/GPU/NVMe temperatures and fan RPMs on Overview,
  discovered per machine (hybrid-GPU aware: an NVIDIA display GPU is read
  via `nvidia-smi`, AMD via sysfs; fans hide when a machine has none).
- **Audio visualizer** — subtle spectrum bars inside the media card while
  something plays (needs the `cava` package; hides cleanly without it).
- **Settings** — the cog in the tab row: choose which Overview cards show
  (hide the battery meter on a desktop, drop the media card, and so on)
  and pick exactly which effects Game Mode strips (animations, blur,
  shadows, gaps, rounding, tearing). Changes persist immediately to
  `~/.local/state/omarchy/settings/nexus.json`.
- **Bar shortcut** — an optional bar widget that toggles the panel and
  lights up while it is open.
- **Deterministic media** — one MPRIS adapter with proxy-aware player
  selection (playerctld and browser-integration proxies never shadow the
  real player) and stable ordering, so the shown player never flaps.
- **Theme-native** — colors, borders, and spacing derive from the shared
  Omarchy tokens; the panel re-themes with your shell.
- **Dormant when closed** — no timers, no processes, no media or PipeWire
  bindings while hidden; the panel unloads entirely between summons
  (measured cold summon: p95 88 ms).
- **Keyboard-driven** — every actionable row on every page is reachable
  without a pointer: media transport, seek, and player switcher on
  Overview; all toggles plus Capture and Power on Controls; Theme and
  Background on Style (see the table below). The tab row also cycles on
  mouse wheel, and page changes slide in from the direction of travel.

## Install

```sh
omarchy plugin add https://github.com/devmobasa/omarchy-nexus --enable
```

Then toggle it:

```sh
omarchy-shell shell toggle community.omarchy-nexus '{}'
```

The payload may name a page directly: `'{"page":"controls"}'` (pages:
`overview`, `media`, `controls`, `style`, `notes`, `clipboard`,
`minimizer`, `alerts`, `settings`).

### Bar shortcut

The manifest also ships a bar widget. If it does not appear after
installing, add it to your bar layout in `~/.config/omarchy/shell.json`:

```json
{ "bar": { "layout": { "right": [ { "id": "community.omarchy-nexus" } ] } } }
```

(append the entry to your existing `right` array), then
`omarchy bar move community.omarchy-nexus <left|center|right>` to
reposition it.

### Keybinding

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + J", "Nexus cockpit", "omarchy-shell shell toggle community.omarchy-nexus '{}'")
```

Then reload Hyprland and check for config errors:

```sh
hyprctl reload
hyprctl configerrors
```

## Keyboard

| Key | Action |
| --- | --- |
| `Esc` | Close the panel |
| `Tab` / `Shift+Tab` | Cycle pages |
| `Down` / `Up` | Walk the current page's rows |
| `Enter` / `Space` | Activate the focused row — on the volume row it toggles mute; the seek bar has no activate action |
| `Left` / `Right` | Act on the focused row when it can — volume slider (±5%), media transport (previous/next), seek bar (±5 s) — otherwise cycle pages |

## Settings

All optional, read from your plugin entry in
`~/.config/omarchy/shell.json` — the fields sit inline on the entry itself.
Invalid values fall back to defaults; Nexus never writes settings.

```json
{
  "version": 1,
  "plugins": [
    {
      "id": "community.omarchy-nexus",
      "defaultPage": "controls",
      "monitor": "DP-3",
      "showMedia": true,
      "showMetrics": true,
      "showNetwork": true,
      "showFetch": true,
      "preferredMediaIdentity": "spotify"
    }
  ]
}
```

Presence of the entry is what enables the plugin; remove it or run
`omarchy plugin disable community.omarchy-nexus` to switch Nexus off.

| Field | Default | Meaning |
| --- | --- | --- |
| `defaultPage` | `"overview"` | Page shown when the summon payload names none |
| `monitor` | `"focused"` | Output name to open on, or `"focused"` |
| `showMedia` | `true` | Show the media artwork, transport, and seek bar |
| `showMetrics` | `true` | Show the metric arc meters |
| `showNetwork` | `true` | Show the network throughput sparkline (needs `showMetrics`) |
| `showFetch` | `true` | Show the hostname · kernel · uptime line |
| `showCpu` / `showMemory` / `showStorage` / `showBattery` | `true` | Per-meter visibility |
| `showSensors` | `true` | Hardware sensors card |
| `showVisualizer` | `true` | Audio spectrum in the media card (needs `cava`) |
| `gmAnimations` / `gmBlur` / `gmShadows` / `gmGaps` / `gmRounding` / `gmTearing` | `true` | What Game Mode strips |
| `preferredMediaIdentity` | `""` | Prefer this player identity (case-insensitive) among active players |

The boolean toggles are also editable interactively on the Settings page
(the cog); interactive changes are stored in
`~/.local/state/omarchy/settings/nexus.json` and win over the shell.json
layer. Nexus never writes shell.json itself.

## Tests

The static suite (model fixtures, manifest validation, contract pins,
qmllint) runs against the Omarchy shell source, which it reads from
`/usr/share/omarchy` by default, and needs `node`, `omarchy`, and `qmllint`
on `PATH`:

```sh
./test/all
```

Set `OMARCHY_PATH` to point at a different Omarchy source tree:

```sh
OMARCHY_PATH=/path/to/omarchy ./test/all
```

`test/live` installs a throwaway copy into your running session, so it needs
a system where Nexus is *not* installed (it refuses if the plugin directory,
a `shell.json` entry, or a registry record already exists), and it removes
everything it created:

```sh
./test/live --confirm-live   # guarded install/summon/teardown round trip
```

`test/benchmark` and `test/stress` measure an existing install instead, so
they need Nexus already installed and enabled. They leave the panel closed
and the install in place; `test/benchmark` writes its report into
`test-output/`:

```sh
./test/benchmark             # cold-summon latency (keepLoaded decision data)
./test/stress                # repeated summon cycles, surface + unload proof
```

CI runs the node model and contract tests on every push.

## Development

The plugin entry point is intentionally a thin composition facade:

- `Nexus.qml` owns the shell lifecycle and routes interactions.
- `state/` owns effectful integrations such as media, metrics, and files.
- `ui/` owns the panel shell and focused visual sections.
- `model/` contains dependency-free calculations shared with Node tests.

`omarchy plugin add` leaves a git checkout at
`~/.config/omarchy/plugins/community.omarchy-nexus/`, so you can edit there
directly. If you work in a separate clone, copy it over first:

```sh
cp -RP -- . ~/.config/omarchy/plugins/community.omarchy-nexus/
```

Either way, restart the shell after every change:

```sh
omarchy restart shell
```

The restart matters: current Quickshell builds do not expose
`Qt.clearComponentCache`, so the shell's plugin hot-reload cannot swap
already-compiled QML — a rescan alone keeps serving the old component.

Design notes and the full milestone history live in
[docs/PLAN-v10.md](docs/PLAN-v10.md).

## License

[MIT](LICENSE)
