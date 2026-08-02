# Omarchy Nexus — V8 implementation plan

Status: approved for Milestone 0; live staging held pending failure-safe tooling
Supersedes: PLAN-v7.md
Review basis: active Omarchy Quattro checkout verified at 12af1883
Plugin id: community.omarchy-nexus
Source workspace: /home/user/omarchy/plugins/community.omarchy-nexus

The intervening commits from the earlier review basis were reviewed as
contract-neutral for plugin hosting, discovery, validation, and retained
services. Implementation must still recheck the live checkout before consuming
those contracts.

## Decision

Proceed with Milestone 0. Do not perform primary-session live staging until:

- payload and modal lifecycle behavior is statically tested;
- one trusted per-uid lifecycle lock, independent of HOME, XDG_STATE_HOME, and
  XDG_RUNTIME_DIR overrides, serializes preflight, staging, testing, cleanup,
  and recovery across every run;
- the fresh-only staging preflight is implemented;
- a durable recovery record is persisted before mutation;
- idempotent EXIT, INT, and TERM cleanup is tested with fault injection;
- the target is allocated with exclusive no-clobber semantics before any source
  content is copied;
- shell and configuration cleanup is authorized independently from filesystem
  ownership, while every target write, rename, or removal requires exact
  ownership proof;
- new-run, recovery, and read-only listing routes have separate exact command,
  environment, and mutation guards;
- recovery validates a controller-generated run id, record mode, every path it
  consumes, and its permitted operation set;
- same-boot lock identity and post-reboot lock generation are explicit;
- live-primary tests require explicit opt-in and support only a fresh Nexus
  installation that the same controller removes after the bounded checks.

The product remains a summonable right-side desktop cockpit implemented as one
third-party panel plugin. It does not replace the Omarchy bar, start a second
Quickshell process, or create a parallel configuration file.

Nexus is standalone within Omarchy Quattro. It uses the standard third-party
QML plugin contract, the existing Omarchy plugin registry and shell
configuration, and the running Omarchy Quickshell process. It has no external
runtime, deployment, or test-harness dependency.

## 1. Test routing and mutation boundary

Ordinary validation must never mutate the primary desktop.

### test/all

test/all is the default local and CI entry point. It runs only:

- manifest validation;
- QML linting;
- pure model tests;
- payload, focus, MPRIS, metrics, formatting, and navigation tests;
- lifecycle and command-safety contract tests;
- staging-controller tests against temporary fake homes and fixture registries.

test/all must not:

- write below ~/.config/omarchy;
- copy into the live plugin discovery directory;
- call plugin rescan, enable, disable, or remove against the running shell;
- restart or reload the live shell;
- alter monitors;
- capture primary-session screenshots;
- invoke test/live-primary under any environment condition.

It may write only inside the source workspace's declared test-output directory
or a unique temporary directory. CI runs test/all only.

### test/live-primary

A new-run test/live-primary invocation is the only route that starts primary
staging. It performs the fresh-only preflight, stages a new Nexus copy,
temporarily enables it, runs the bounded primary checks, and invokes
failure-safe cleanup.

A new-run invocation must refuse unless both are present:

- the exact command-line flag --confirm-primary-session-mutation;
- the exact environment opt-in NEXUS_LIVE_PRIMARY=1.

It also refuses when:

- another staging or recovery controller holds the global lifecycle lock;
- Nexus already exists in the target directory, shell configuration, or live
  registry;
- an incomplete recovery record already exists;
- the Omarchy lock is active;
- shell health or baseline capture fails;
- the coordination root, recovery root, record path, plugin parent, or target
  path cannot be resolved and validated exactly.

These are new-run guards. Recovery and listing use the separate matrix below.
No generic --force option may bypass any route guard.

### Exact command and guard matrix

| Route | Required command guard | Required environment | Mutation authority |
|---|---|---|---|
| test/all | none | none | Static fake roots only |
| test/live-primary --list-recovery | exact listing mode | none | Read-only record metadata |
| test/live-primary new run | --confirm-primary-session-mutation | NEXUS_LIVE_PRIMARY=1 | Fresh candidate staging and cleanup |
| test/live-primary --recover RUN | --confirm-primary-session-recovery | NEXUS_LIVE_PRIMARY_RECOVERY=1 | Cleanup of one live-primary record only |

RUN is the exact 32-character lowercase hexadecimal run id. New-run, recovery,
and listing modes are mutually exclusive. Unknown flags, conflicting modes,
missing or extra confirmation flags, wrong environment variables, and
records whose mode is not exactly live-primary cause refusal. An environment
variable alone never selects or upgrades a route.

Listing never acquires mutation authority, reads saved baseline payloads, calls
shell IPC, or repairs state. Recovery guards do not authorize new staging or
tests, and new-run guards do not authorize recovery.

A higher-level wrapper may dispatch these scripts only when the caller names
the mode explicitly. There is no implicit live mode and no environment-only
upgrade from static to live testing.

## 2. Durable recovery record

The live controller persists recovery state before its first mutation.

Derive the real numeric uid from the process credentials and resolve its account
home through the system account database. Do not trust HOME, XDG_STATE_HOME,
XDG_RUNTIME_DIR, USER, LOGNAME, or caller-provided paths for coordination,
recovery storage, plugin discovery, or shell.json.

Require the real and effective uid to match, refuse uid 0, and require exactly
one account-database record whose canonical home is owned by that uid. The live
controllers do not support setuid, sudo, or alternate-user execution.

Use these fixed per-uid roots:

    coordination: /run/user/<real-uid>/omarchy-nexus/
    recovery:     <account-home>/.local/state/omarchy-nexus/staging/

The coordination root is for the global lock only; durable records remain under
the account-home recovery root. Validate that /run/user/<real-uid> is the real
systemd user runtime directory owned by the uid and not a symlink. Validate that
the resolved account home is a real directory owned by the uid.

Set umask 077 before creating private state. The coordination root, recovery
root, and run directory must be real, non-symlinked directories owned by the
current uid with mode 0700. Lock and record files must be real, non-symlinked
files owned by the current uid with mode 0600.
Canonicalize each existing ancestor. Reject an unexpected path or type, an owner
other than the current uid or root, and a group- or other-writable ancestor
unless its sticky bit prevents another user from replacing this user's entry.

Static fake-home tests inject roots only into the pure controller module through
a test-only interface. The live-primary new-run and recovery routes have no
root-override option and ignore root-changing environment variables.

The controller generates a run id from 128 bits of randomness encoded as
exactly 32 lowercase hexadecimal characters. User input never selects a path.
The only valid record location is the direct child:

    <canonical-recovery-root>/<run-id>/record.json

Create recovery and run directories with mode 0700 and recovery files with
mode 0600. Reject collisions rather than reusing an existing run directory.

The record includes:

- schema version and unique run id;
- mode: live-primary;
- controller PID and process-start ticks for diagnostics only, start time, and
  requested test set;
- originating boot id;
- canonical coordination root, recovery root, lock path, and exact record path;
- ordered lock-acquisition history containing boot id, device, inode, random
  generation, run id, acquisition time, PID, and process-start ticks;
- absolute source workspace for provenance only;
- exact target, target-parent, and shell.json paths derived by the controller
  from the real uid, account-database home, and plugin id;
- expected manifest id;
- source-tree checksum;
- whether shell.json originally existed;
- exact original shell.json bytes, checksum, owner, and permissions;
- normalized original JSON;
- registry baseline and shell health;
- mutation phase;
- cleanup attempts and latest result;
- conflict details and unresolved recovery actions.

Write records durably before mutation: write a same-directory
temporary file, set its final mode, flush its contents, atomically rename it,
flush the containing directory, then read it back and verify its schema,
checksum, and expected paths. Apply the same durability sequence to every
record update. Do not treat a buffered write or rename without directory
persistence as a durable checkpoint.

Update the phase atomically before and after each mutation. A recovery decision
uses both the recorded phase and observed live state; it never assumes that a
process survived long enough to write the post-mutation phase.

Recommended phases:

    prepared
    target-allocated
    copying
    copied
    rescanned
    enabled
    testing
    cleaning
    conflict
    recovered
    complete

A new staging run refuses to start while a non-complete recovery record exists.

### Global lifecycle lock

Use one exclusive advisory lock at:

    /run/user/<real-uid>/omarchy-nexus/community.omarchy-nexus.lock

The path is derived only from the real uid and validated systemd runtime
directory. It is independent of caller-controlled environment and serializes
every live-primary staging or recovery operation, regardless of run id or
environment overrides.

### Lock acquisition identity and reboot behavior

Every acquisition identity is the tuple:

    canonical path, boot id, device, inode, random generation, run id

Read boot id from /proc/sys/kernel/random/boot_id. After opening the canonical
lock file without following links and acquiring flock, obtain device and inode
from the open descriptor, generate a fresh 128-bit acquisition generation, and
write lock metadata containing the tuple plus PID and process-start ticks. PID
is diagnostic only. Durably append the acquisition identity to the applicable
recovery record and verify it before the first mutation. Read-only
incomplete-record checks, requested-record validation, and baseline capture may
precede this persistence; no shell or filesystem mutation may.

The raw flock may be acquired before a new run id is reserved or a recovery
record is validated, but it grants no mutation authority by itself. After
incomplete-record checks, a new route generates its run id; a recovery route
validates its requested run id and record. Only then may the controller publish
run-bound lock metadata and persist the acquisition identity.

Within one boot, the controller requires the canonical path's device and inode
to remain identical to the held descriptor before every mutation. Recovery in
the same boot must acquire that same inode with a new generation. A missing,
replaced, or different-inode lock path in the same boot is a conflict and does
not authorize mutation.

After reboot, the recorded boot id differs and /run is expected to be new.
Recovery may create and acquire the same canonical lock path with a new device,
inode, and generation. It appends this acquisition to the durable history and
retains the prior boot's identity as evidence; it never requires cross-boot
inode equality. For an incomplete record, a boot-id change permits only explicit
recovery of that validated record, not an implicit new staging route. Completed
records from earlier boots do not restrict a separately guarded new run.

The controller acquires the lock non-blockingly before it enumerates records in
the fixed account-home recovery root, captures a baseline, reserves a run id, or
checks target absence. It holds the same open descriptor through staging, child
tests, cleanup, baseline verification, and the durable transition to complete.
Recovery mode acquires this same lock before inspecting or mutating live state.
A busy lock causes a clear refusal; it is never bypassed with --force.

The controller owns the lock descriptor. Child tests must not inherit it, and a
child cannot outlive the controller. Process termination releases the advisory
lock, while the durable non-complete record remains for recovery. Add
parallel-invocation tests proving that controllers with different run ids,
HOME, XDG_STATE_HOME, and XDG_RUNTIME_DIR values still contend on the same lock
and cannot both pass preflight.

The read-only recovery-list command consumes only atomically published record
metadata. It never creates a missing lock file. When the canonical lock file
exists, listing opens it without following links and performs a non-blocking
exclusive flock probe using the same lock mode as the controller:

- acquiring the probe means no controller currently owns the lock; release it
  immediately without changing metadata;
- a busy result is active only when current boot id, lock device/inode, and
  generation metadata match the current acquisition recorded for that run;
- a record from an earlier boot is incomplete and recoverable, never active;
- PID and process-start ticks may corroborate output but never determine
  activity.

Listing must never mutate or repair state and must tolerate races by reporting
an indeterminate snapshot rather than guessing.

## 3. Failure-safe cleanup controller

Install idempotent cleanup handlers for EXIT, INT, and TERM immediately after
the durable prepared record is verified and before the first mutation.

The controller must:

- preserve the original command or signal exit status;
- require the global lifecycle lock for every cleanup mutation;
- serialize recursive or repeated cleanup for the same record with a per-run
  state guard;
- tolerate already-hidden, already-disabled, or already-removed state;
- update the recovery phase before and after each cleanup mutation;
- run cleanup after command failure, test assertion failure, timeout, Ctrl+C,
  INT, TERM, and normal completion;
- retain recovery data whenever cleanup is incomplete or conflicted.

The controller process must remain alive while child tests run. Do not replace
it with a child process in a way that discards its traps. Timeouts terminate the
child test and then execute controller cleanup.

SIGKILL, power loss, and machine failure cannot run traps. The durable record
therefore remains the authority for a later recovery-only invocation.

### Cleanup authority separation

Cleanup has two independent authorization lanes.

The shell/configuration lane is authorized by the durable baseline, the exact
recorded Nexus entry, and the observed Nexus-only configuration delta. It does
not require the staged directory to exist or pass filesystem ownership checks.
It may:

- request shell.hide for the recorded plugin id;
- call setPluginEnabled(id, false) or the matching disable route even when the
  manifest is no longer discovered;
- verify that only the run-attributable Nexus entry was removed while preserving
  unrelated shell.json changes;
- wait for recorded Nexus runtime surfaces, focus, timers, and processes to
  disappear.

The current Omarchy contract rejects an unknown manifest only for enable.
Disable remains valid and removes a matching configuration entry. For a fresh
live-primary baseline, Nexus was absent, so every current plugins entry with
the exact Nexus id is run-scoped and must be removed even if its inline Nexus
settings changed. Repeated disable calls are allowed only while exact-id entries
remain; verify after each call that no non-Nexus configuration changed. A
changed Nexus entry is recorded as a Nexus-scoped conflict, not mistaken for
unrelated state and not left enabled. If shell.json becomes unparseable or the
exact id cannot be isolated safely, stop, retain the record, and report manual
configuration recovery rather than overwriting the file.

The filesystem lane is authorized only by canonical path, marker, device,
inode, ownership, phase-aware content, and checksum proof. A missing target is
already absent. A replaced or mismatched target is never written, renamed, or
removed and produces a retained conflict.

Rescan only after the target is proven absent. Never rescan a mismatched unowned
target as part of automated cleanup. A filesystem conflict does not prevent safe
shell/configuration disable, but it does prevent a complete result.

### Exclusive target publication and exact ownership

The absence preflight is advisory; it does not authorize a later merging copy.
While holding the global lifecycle lock, publish a fresh target as follows:

1. recheck that the canonical target has no directory, file, or symlink;
2. create the exact target directory with one exclusive, non-recursive operation
   that fails if any object already exists;
3. verify the new directory's canonical parent, current-uid ownership, mode,
   device, and inode;
4. create the run marker without following or replacing a link, persist the
   target identity and target-allocated phase, and verify the record;
5. copy source contents only into that already-owned directory, refusing source
   symlinks and never using copy semantics that merge into a pre-existing
   destination;
6. revalidate the marker, device, inode, manifest id, and complete staged
   checksum before rescan or enable.

If another installation or object appears at any point, stop before writing
source content, record a conflict, and retain the recovery record. The
controller must never solve a target collision by deleting, renaming, merging,
or overwriting the existing object.

Before every later target write, enable, rename, or removal, and again
immediately before removing the staged directory, validate all of these.
Hide and disable use the separate shell/configuration authority above:

1. the canonical target path exactly equals the recorded target;
2. the canonical parent exactly equals the user plugin discovery directory;
3. the target is a real directory, not a symlink, and remains owned by the
   current uid;
4. a staging marker inside the copied directory contains the same run id;
5. the recorded device and inode identity match the staged directory;
6. the marker references the expected source checksum;
7. content matches the validation rule for the recorded phase.

For target-allocated and copying, every present entry must be either the exact
run marker or an expected source entry with matching type and content; no
unrecorded entry is allowed. The manifest may be absent or incomplete in these
two phases. From copied onward, require the complete staged checksum and a
manifest id exactly equal to community.omarchy-nexus. This phase-aware rule
allows safe cleanup of an interrupted copy without weakening ownership proof.

The marker is added only to the staged test copy. If any check fails, do not
write, remove, or rename the target. Continue any independently authorized
shell/configuration cleanup, record a filesystem conflict, preserve recovery
data, and report the exact mismatch.

### Recovery-only mode

Use the recovery commands and guards from the route matrix:

    NEXUS_LIVE_PRIMARY_RECOVERY=1 test/live-primary \
      --recover <run-id> --confirm-primary-session-recovery

test/live-primary accepts only records whose mode is exactly live-primary
before live inspection or mutation.

Recovery mode:

- accepts only a run id matching exactly 32 lowercase hexadecimal characters;
- derives the record path as a direct child of the canonical recovery root and
  rejects absolute paths, separators, dot segments, alternate encodings,
  symlinks, unexpected owners, and any canonical-path escape;
- never copies candidate or source-workspace content, allocates a new candidate,
  starts staging, or starts tests;
- never copies plugin content or enables a plugin;
- reads and validates the existing durable record, saved baseline checksums,
  mode, uid, run id, and schema;
- derives the permitted coordination root, recovery root, shell.json, plugin
  parent, and target from current trusted process and account-database inputs,
  then requires the recorded paths to match those derived values;
- treats recorded source, target, and command strings as data and
  never executes or follows them blindly;
- acquires the global lifecycle lock before live inspection or mutation;
- checks the Omarchy lock before shell operations;
- resumes the idempotent cleanup state machine;
- performs shell/configuration cleanup from its separate recorded-delta
  authority even when the target is absent or mismatched;
- validates the exact staged target before every filesystem write, rename, or
  removal;
- permits rescan only after the staged target is proven absent;
- performs the unrelated-configuration conflict check;
- reports remaining manual actions when automatic recovery is unsafe.

Also provide a read-only listing mode for incomplete recovery records.

Successful cleanup marks the record complete after baseline verification.
Conflict or partial cleanup leaves the record intact. Do not delete recovery
evidence merely to permit a new run.

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

Use Color, Style, Border, and BorderSurface. Do not copy Caelestia code,
structure, colors, artwork, shaders, icons, or text.

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
