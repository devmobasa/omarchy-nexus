# Omarchy Nexus — V8 implementation plan

Status: approved for Milestone 0; live staging held pending failure-safe tooling
Supersedes: PLAN-v7.md
Review basis: active Omarchy Quattro checkout verified at 12af1883
Plugin id: community.omarchy-nexus

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


Continued in [PLAN-v8-part-2.md](PLAN-v8-part-2.md).
