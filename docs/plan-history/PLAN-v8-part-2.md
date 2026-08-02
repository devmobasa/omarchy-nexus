# Omarchy Nexus — V8 implementation plan, part 2

Continued from [PLAN-v8.md](PLAN-v8.md).

## 4. Static versus live plugin discovery

The source workspace is valid for static checks but is outside the live
third-party discovery directory. A real shell summon requires a copied,
non-symlinked plugin at:

    ~/.config/omarchy/plugins/community.omarchy-nexus/

### Primary-session staging policy

Primary-session staging supports only a fresh Nexus installation.

Before copying anything, inspect:

1. the target plugin directory;
2. the top-level shell.json plugins array;
3. the live plugin registry.

Abort if any Nexus directory, configuration entry, or registry record exists.
Do not back up, replace, rename, or overwrite an existing primary-session
installation.

After the global lifecycle lock is held and the durable recovery record and
traps are active:

1. repeat all three absence checks under the lock;
2. allocate the exact target with the exclusive no-clobber procedure;
3. persist its marker and device/inode identity before copying source content;
4. copy and verify the complete candidate while continuing to own the same
   target;
5. rescan and temporarily enable Nexus;
6. run the bounded primary checks;
7. enter the idempotent cleanup controller.

Primary cleanup runs in this order:

1. request shell.hide for the recorded Nexus id;
2. use the exact baseline and run-created configuration entry to disable Nexus,
   even if the target vanished or no manifest is currently discovered;
3. verify the run-created entry is gone without reverting unrelated shell.json
   changes, then wait for its surface, focus, timers, and processes to disappear;
4. restore exact original shell.json bytes and permissions only when every
   remaining difference is Nexus-related; if the file did not originally exist,
   remove it only when it contains no unrelated state;
5. independently validate the target: remove it only with exact ownership proof,
   treat absence as already removed, and leave any replacement untouched as a
   filesystem conflict;
6. rescan only when the target is absent, then verify the fresh baseline and
   healthy shell.

When unrelated configuration changed, never restore the saved baseline over it.
Preserve unrelated changes, record the conflict, and identify the remaining
Nexus delta. A mismatched target prevents complete cleanup but must not leave
the recorded staged configuration enabled.

### Existing-installation boundary

Automated replacement testing is out of scope. Every live run requires Nexus to
be absent from the plugin directory, shell configuration, and live registry.
The controller never renames, removes, overwrites, backs up, or restores an
existing Nexus installation.

Fresh live staging must end with no Nexus installation or configuration entry.
Monitor resolution uses static fixtures by default; a live monitor hotplug is
performed only when the user explicitly directs the physical action. Do not
rescan or restart the shell while the Omarchy lock is active.

## 5. Payload normalization

The Omarchy host marks a plugin open before calling open and ignores the
entry-point return value. Nexus must never leave the host logically open while
declining to show a surface.

The open method must:

- treat malformed JSON, empty payloads, arrays, and primitive values as an
  empty object;
- accept only a whitelisted page field;
- map missing or invalid pages to overview;
- ignore unknown fields;
- resolve the target screen;
- set opened true and show the default or normalized page for every call.

A repeated open while visible updates page and target screen without creating a
second surface. Payload values are session-scoped and never persisted.

## 6. Chosen surface and input-region model

Use a modal full-output overlay with a visually right-aligned panel card.

The single target-screen window owns the full logical output while open:

- transparent modal surface at the overlay layer;
- ExclusionMode.Ignore and no exclusive work area;
- full input region while logically open;
- transparent outside-click area that requests shell.hide;
- inner right-side card that accepts panel interaction;
- exclusive keyboard focus only while logically open.

On logical close:

1. set opened false;
2. clear the input region and release modal keyboard focus immediately;
3. stop polling and transient work;
4. hide the modal surface.

Do not add a close animation initially. An open animation starts only after the
surface owns focus and input. Escape, outside click, and the close button call
shell.hide(manifest.id), not merely set visible false. Use a close-request guard
so host close and self-requested close cannot recurse.

The root is an Item, never a ShellRoot. It declares the host properties it uses
and exposes:

    property bool opened
    function status()

status returns opened, selected page, target screen, metrics-active state,
pending action, and current focus role.

## 7. Monitor resolution and geometry

Resolve one target screen at open time:

1. match Hyprland.focusedMonitor to Quickshell.screens;
2. otherwise use the active toplevel's first screen;
3. otherwise use the first real screen.

If that screen disappears while open, retarget or close cleanly. Never create a
permanently mounted surface for every monitor.

The inner card is right aligned:

- preferred width: 360–560 logical pixels;
- maximum width: 42 percent of a wide output;
- narrow-output width: output width minus safe margins;
- maximum height: output height minus safe margins and token spacing;
- vertical overflow: internal scrolling.

Safe margins use current screen and bar geometry when available, with a themed
fallback. Account for bars on every edge, including the right edge.

## 8. Visual and keyboard contract

The expected result is a dark, shell-themed right-side cockpit:

- hero card with time, workspace context, and media artwork;
- tabs for Overview, Controls, and Style;
- metric cards below the hero;
- control rows with normal, hover, focus, selected, pending, disabled, and error
  states;
- restrained accent glow and shallow entrance motion;
- no constant animation while closed or idle.

Use Color, Style, Border, and BorderSurface.

A fresh open always focuses the selected page tab after the surface is ready.

For repeated summons:

- preserve a still-valid enabled control when the page is unchanged;
- focus the new selected tab when the page changes;
- fall back to the selected tab when prior focus is invalid;
- normalize invalid payloads to Overview and focus its tab when page changes;
- clear remembered focus after close.

Keyboard behavior:

- Tab and Shift+Tab move through tabs and controls in visual order;
- Left/Right changes tabs or adjusts a focused slider;
- Up/Down moves between controls;
- Enter or Space activates the focused item;
- Escape calls shell.hide;
- pending actions cannot be triggered twice.

Open with a 160–220 ms right-to-left slide and opacity transition. Close
immediately. Collapse metrics to one column on narrow outputs and derive
vertical-bar offsets from the live bar edge.

## 9. Complete initial manifest

The initial manifest omits keepLoaded:

~~~json
{
  "schemaVersion": 1,
  "id": "community.omarchy-nexus",
  "name": "Omarchy Nexus",
  "version": "0.1.0",
  "author": "Omarchy Community",
  "description": "A themed desktop cockpit for media, system state, controls, and style",
  "license": "MIT",
  "kinds": ["panel"],
  "entryPoints": {
    "panel": "Nexus.qml"
  }
}
~~~

Before distribution, replace the placeholder author, add the MIT LICENSE, and
initialize a Git repository. Plugin files and entry points are real files, not
symlinks.

## 10. Configuration access

Optional settings live in the canonical top-level plugins array:

~~~json
{
  "id": "community.omarchy-nexus",
  "defaultPage": "overview",
  "monitor": "focused",
  "showMedia": true,
  "showMetrics": true,
  "preferredMediaIdentity": ""
}
~~~

Milestone 1 may use only the id. A later tested helper reads
shell.shellConfig.plugins, applies defaults, reacts to changes, and never writes
settings during open.

## 11. Authoritative integration contracts

Every control has one authoritative state source, one action path, a pending
state, and explicit failure or refresh behavior.

Retained first-slice integrations:

- Media uses one direct Quickshell MPRIS adapter. Do not poll omarchy.media IPC
  in parallel.
- Battery uses the first-party battery service with a normal no-battery
  fallback.
- CPU, memory, and storage use one bounded Nexus sampler with documented units,
  cadence, timeout, and stale-state behavior.
- Audio and microphone use reactive PipeWire state and one matching action path.
- DND, night light, and stay awake use first-party reactive services when
  exposed; unavailable controls show the reason.

Deferred: weather, network detail, Bluetooth, Tailscale/VPN, recording, power,
notifications, lyrics, CAVA, lock integration, persistent per-monitor layouts,
and drag customization.

Wallpaper and theme actions close Nexus and delegate to existing selectors.
Subprocesses use argument arrays and never interpolate media titles, workspace
names, monitor names, URLs, or paths into shell commands. Pending actions are
serialized, cannot overlap, refresh authoritative state after completion, and
surface unavailable or error states instead of silently reverting.

## 12. Deterministic MPRIS model

Milestone 0 defines and tests normalized player records with these exact inputs:

- identityKey: a stable exact identity normalized by the shared identity
  normalizer;
- preferredIdentity: preferredMediaIdentity from validated Nexus settings,
  normalized by the same function as identityKey; default empty;
- sourceKey: an adapter-provided exact source identity used only for
  deduplication;
- isProxy: a Boolean produced by one explicit proxy-alias table covered by
  fixtures;
- activitySerial: a monotonically increasing sequence number, never wall-clock
  time.

No fuzzy matching, substring matching, environment guessing, or display-name
preference is permitted. Invalid or deferred preferredMediaIdentity produces an
empty preferredIdentity.

Construct sourceKey in this exact order:

1. an exact configured or built-in alias for a known proxy or bus identity;
2. normalized non-empty desktopEntry;
3. normalized non-empty player identity;
4. exact unique MPRIS bus name.

Two players represent the same source only when sourceKey matches exactly.
Unknown players remain separate.

Increment activitySerial only when:

- a player transitions into Playing;
- track identity changes while that player is Playing;
- a successful user action explicitly targets that player;
- a newly discovered player is already Playing.

Position ticks, volume changes, artwork completion, and unrelated metadata do
not update it.

Selection has two explicit phases.

Phase 1 groups records by exact sourceKey and selects one representative per
group:

1. if the group contains any non-proxy records, discard every proxy from the
   representative candidate set;
2. otherwise use the proxy records;
3. if more than one candidate remains, choose among that candidate set using
   the exact Phase 2 total order below.

A playing or preferred proxy therefore never defeats a real same-source player.
If the real player disappears, recompute the group and allow its proxy to
become the representative.

Phase 2 applies this total order across the group representatives:

1. playback state: Playing, then Paused, then Stopped, then Unknown;
2. exact preferredIdentity match first within the same state;
3. larger activitySerial first;
4. identityKey in ascending locale-independent byte order;
5. exact MPRIS bus name in ascending locale-independent byte order.

Only representatives create cards. Actions route only to the selected
representative object and are enabled only when that object reports the
corresponding play, pause, previous, next, or seek capability.

Required fixtures include a playing proxy with a paused real player, a
preferred proxy with a non-preferred real player, proxy-only groups, multiple
real records, real-player disappearance with proxy promotion, and stable
ordering across input permutations.

When the selected player disappears, select the next eligible player or show
the no-media state. Clear stale artwork and pending actions.

Allow only file, image, qrc, http, and https artwork URLs. Reject every other
scheme, bound loading and retries, and show a themed placeholder after failure.
Never expose remote artwork URLs to commands or persist them as configuration.

## 13. keepLoaded benchmark

Milestone 0 defines the benchmark. At the end of Milestone 1, measure 20 cold
summon cycles from explicit IPC invocation to the first usable state. Record
p50 and p95 latency, shell log errors, and closed-state CPU and timer activity.

Target:

- p95 at or below 250 ms;
- no recurring closed-state poller, animation, artwork load, or subprocess;
- no stale surface after close.

Keep keepLoaded omitted when the target is met. Add it only from measured need,
with all background activity dormant while closed.

## 14. Milestones

### Milestone 0 — contract and safety spike

- Freeze the exact new-run, recovery, and listing route matrix.
- Specify the environment-independent per-uid lifecycle lock, same-boot inode
  continuity, post-reboot generation, and cross-run exclusion.
- Specify the durable recovery schema, fsync boundary, and atomic phase
  transitions.
- Specify idempotent EXIT, INT, TERM, timeout, and recovery behavior.
- Specify strict run-id, record-path, and saved-baseline validation.
- Specify exclusive target allocation, split configuration/filesystem cleanup
  authority, exact ownership checks, and conflict retention.
- Freeze fresh-only primary staging and the existing-installation refusal.
- Freeze payload, modal lifecycle, monitor, focus, and immediate-close behavior.
- Confirm validator, qmllint, and static test/all commands.
- Confirm MPRIS, battery, PipeWire, DND, night-light, and idle APIs.
- Test MPRIS identity, source grouping, real-over-proxy representative
  selection, cross-representative arbitration, capability, disappearance, and
  artwork rules.
- Define resource sampler and keepLoaded benchmark.
- Record clean-room provenance and maintainer decision.

### Milestone 1 — minimal installable panel and safe live controller

Add LICENSE, manifest.json, Nexus.qml, placeholder Overview, and test/all.

Implement panel lifecycle, payload normalization, status, monitor targeting,
modal input, outside click, deterministic focus, keyboard navigation, theme
tokens, right-side geometry, and open-only animation.

Implement test/live-primary with:

- route-specific command-and-environment opt-in;
- one trusted per-uid lifecycle lock independent of environment overrides,
  with boot id, inode continuity, and acquisition generations;
- fresh-only preflight under that lock;
- durable pre-mutation recovery record;
- exclusive no-clobber target allocation;
- traps and idempotent cleanup;
- separately authorized shell/configuration cleanup;
- exact staged-target marker and identity checks before every filesystem
  mutation;
- conflict-safe configuration comparison;
- separately guarded live-primary recovery and read-only recovery-list modes.

Before primary live staging, pass static fault-injection tests for:

- concurrent controllers with different run ids and conflicting HOME,
  XDG_STATE_HOME, and XDG_RUNTIME_DIR overrides;
- target creation between absence preflight and allocation;
- failure before allocation, after allocation, during copy, and after copy;
- failure after rescan and after enable;
- failure during a test;
- child timeout;
- INT and TERM;
- abrupt controller death followed by recovery at every mutation phase;
- target disappearance and target identity mismatch while proving the recorded
  Nexus entry is still disabled safely;
- unrelated shell.json change;
- invalid, escaping, symlinked, or incorrectly owned recovery paths;
- repeated and concurrent recovery invocation;
- same-boot lock-path replacement, post-reboot lock reacquisition, stale PID
  reuse, and active-listing flock probes.

Then run bounded primary tests and measure the keepLoaded benchmark.

### Milestone 2 — overview vertical slice

Add clock/workspace, direct MPRIS, dormant CPU/memory/storage sampling, battery,
and stale/unavailable states.

### Milestone 3 — controls and style

Add reduced reactive controls, pending/error feedback, and delegated wallpaper
or theme selectors. Add optional settings only after the reader is tested.

### Milestone 4 — live visual validation and expansion

Use the existing test/live-primary new-run route for explicitly authorized
visual and performance checks. Cover cold summon, repeated summon, current
multi-monitor layouts, scaling, vertical-bar and right-bar placement, keyboard
navigation, outside click, animations, and teardown. Capture and inspect visual
artifacts only when the user requests the live run.

Use fixtures for monitor disappearance and reappearance. A physical hotplug may
be observed only when the user directs it; the plugin tooling never changes the
monitor configuration. Expand features only after the static contracts and the
bounded fresh-install live checks pass.

## 15. Validation routing

| Route | Default safety | Scope |
|---|---|---|
| test/all | Non-mutating; ordinary local and CI route | Manifest, QML, models, route guards, lock generations, cleanup, MPRIS, and recovery fault injection |
| test/live-primary | Separate new-run and recovery opt-ins; fresh install only | Trusted per-uid lock, bounded lifecycle, cleanup-only recovery, and read-only listing |

Validation succeeds only when:

- static checks pass through test/all;
- live checks, when explicitly requested, leave the expected baseline;
- shell ping is ok and new logs have no loader/QML errors;
- visual artifacts are inspected rather than merely created;
- cleanup survives normal, failure, timeout, signal, and abrupt-death recovery
  paths;
- concurrent controllers cannot both pass preflight even with different HOME
  and XDG overrides;
- target publication never merges with or overwrites an object that appeared
  after preflight;
- a missing or mismatched target does not prevent safe removal of the exact
  run-created configuration entry;
- the exact route matrix rejects missing, conflicting, or cross-route guards;
- live-primary recovery never copies plugin content or enables a plugin;
- same-boot lock identity requires inode continuity, post-reboot recovery records
  a new generation, and active listing never trusts PID alone;
- MPRIS deduplication chooses a real same-source representative before
  cross-source arbitration;
- recovery rejects every run-id or path escape;
- conflicts retain recovery evidence;
- no route writes to or removes a target it cannot prove belongs to its run.

## Current next step

Execute Milestone 0 documentation and fixture discovery only. Do not stage,
enable, or modify the primary live configuration until test/live-primary's
trusted per-uid lifecycle lock and reboot generations, durable record, exact
route matrix, exclusive target allocation, split cleanup authority, traps,
exact-target validation, conflict behavior, and baseline-limited recovery are
implemented and pass static fault-injection tests.
