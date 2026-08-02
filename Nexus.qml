import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "model/NexusModel.js" as NexusModel
import "model/NexusMediaModel.js" as NexusMediaModel
import "model/NexusMetricsModel.js" as NexusMetricsModel
import "model/NexusSettingsModel.js" as NexusSettingsModel
import "model/NexusGameModeModel.js" as NexusGameModeModel
import "model/NexusKeybindsModel.js" as NexusKeybindsModel
import "model/NexusSensorsModel.js" as NexusSensorsModel
import "model/NexusCavaModel.js" as NexusCavaModel
import "model/NexusSuiteModel.js" as NexusSuiteModel
import "model/NexusAgendaModel.js" as NexusAgendaModel
import "model/NexusPomodoroModel.js" as NexusPomodoroModel

Item {
  id: root

  // ---- host injections (assigned by the shell when declared) ---------------
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // ---- lifecycle state -----------------------------------------------------
  property bool opened: false
  property string page: NexusModel.DEFAULT_PAGE
  property var targetScreen: null
  property bool closingFromHost: false

  // The sampler runs exactly while the panel is open.
  readonly property bool metricsActive: opened
  readonly property string focusRole: controlCursor >= 0 ? "control" : "tab"

  // ---- validated settings ---------------------------------------------------
  // Two layers: the read-only shell.json entry, overridden by the Settings
  // page's state file. Nexus never writes shell.json.
  property var stateOverrides: ({})
  readonly property var settings: NexusSettingsModel.applyState(
    NexusSettingsModel.readSettings(
      shell && shell.shellConfig ? shell.shellConfig.plugins : null,
      manifest && manifest.id ? manifest.id : "community.omarchy-nexus",
      NexusModel.PAGES),
    stateOverrides)

  readonly property string settingsDir: NexusSettingsModel.stateDir(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  readonly property string settingsFile: NexusSettingsModel.statePath(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  property string settingsError: ""

  FileView {
    path: root.opened ? root.settingsFile : ""
    printErrors: false
    watchChanges: true
    onLoaded: root.stateOverrides = NexusSettingsModel.parseState(text())
    onFileChanged: reload()
  }

  FileView {
    id: stateWriter
    path: root.settingsFile
    printErrors: false
    atomicWrites: true
    // Re-read after every save so the write-compare cache tracks disk
    // (setText silently no-ops on identical cached content).
    onSaved: {
      root.settingsError = ""
      reload()
    }
    onSaveFailed: root.settingsError = "Could not write the settings file"
  }

  function updateSetting(key, value) {
    var next = {}
    for (var existing in stateOverrides) next[existing] = stateOverrides[existing]
    next[key] = value === true
    stateOverrides = next
    ensureDirsProcess.writeStateAfter = true
    runProcess(ensureDirsProcess)
  }

  // ---- serialized pending actions ------------------------------------------
  // One control action at a time: the pending window blocks overlapping
  // dispatch and clears after the reactive state has had time to refresh.
  property string pendingActionName: ""
  readonly property var pendingAction: pendingActionName === "" ? null : pendingActionName

  function dispatchControl(name, action) {
    if (!opened || pendingActionName !== "") return
    pendingActionName = name
    action()
    pendingClearTimer.restart()
  }

  Timer {
    id: pendingClearTimer
    interval: 400
    onTriggered: root.pendingActionName = ""
  }

  // The host marks the plugin open before delivering open() and ignores the
  // return value, so every call must end with a visible surface. A repeated
  // open while visible updates page and target screen without a new surface.
  function open(payloadJson) {
    var normalized = NexusModel.normalizePayload(payloadJson, root.settings.defaultPage)
    root.page = normalized.page
    root.targetScreen = targetScreenForOpen()
    root.now = new Date()
    root.opened = true
    refreshServices()
    refreshMedia()
    if (root.settings.showSensors && !sensorDiscoveryProcess.running)
      sensorDiscoveryProcess.running = true
    if (!cavaConfWritten && cavaAvailable && root.settings.showVisualizer) {
      ensureDirsProcess.writeCavaAfter = true
      runProcess(ensureDirsProcess)
    }
    if (root.page === "keys" && !bindsProcess.running) bindsProcess.running = true
    Qt.callLater(function () {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  // Host-initiated close (`shell hide`). Immediate: no close animation, so
  // the input region and exclusive keyboard focus release with the surface.
  function close() {
    closingFromHost = true
    root.opened = false
    root.targetScreen = null
    root.mediaSelected = null
    root.mediaOverrideKey = ""
    root.mediaPlayerCount = 0
    root.seekDragging = false
    root.controlCursor = -1
    root.pendingActionName = ""
    root.netPrevSample = null
    root.netRxRate = null
    root.netTxRate = null
    root.netRxHistory = []
    root.netTxHistory = []
    root.gameModePending = false
    root.gameModeError = ""
    root.settingsError = ""
    saveNotes()
    closingFromHost = false
  }

  // Self-initiated close (Escape, outside click) must go through shell.hide
  // so the host's open-panel map stays in sync; closingFromHost keeps host
  // close and self-requested close from recursing.
  function requestClose() {
    if (closingFromHost) return
    if (shell && typeof shell.hide === "function")
      shell.hide(manifest && manifest.id ? manifest.id : "community.omarchy-nexus")
    else root.opened = false
  }

  function status() {
    return JSON.stringify({
      opened: root.opened,
      page: root.page,
      screen: root.targetScreen ? String(root.targetScreen.name || "") : "",
      metricsActive: root.metricsActive,
      pendingAction: root.pendingAction,
      focusRole: root.focusRole
    })
  }

  function targetScreenForOpen() {
    var screens = Quickshell.screens || []
    var wanted = root.settings.monitor
    if (wanted && wanted !== "focused") {
      for (var w = 0; w < screens.length; w++) {
        if (String(screens[w].name || "") === wanted) return screens[w]
      }
    }
    var focused = Hyprland.focusedMonitor
    for (var i = 0; i < screens.length; i++) {
      var monitor = Hyprland.monitorFor(screens[i])
      if (focused && monitor === focused) return screens[i]
      if (focused && monitor && monitor.id === focused.id) return screens[i]
      if (focused && String(screens[i].name || "") === String(focused.name || "")) return screens[i]
    }
    var active = ToplevelManager.activeToplevel
    if (active && active.screens && active.screens.length > 0) return active.screens[0]
    return screens.length > 0 ? screens[0] : null
  }

  readonly property string workspaceLabel: {
    var parts = []
    var workspace = Hyprland.focusedWorkspace
    if (workspace && workspace.id !== undefined) parts.push("Workspace " + workspace.id)
    var monitor = Hyprland.focusedMonitor
    if (monitor && monitor.name) parts.push(String(monitor.name))
    return parts.join(" · ")
  }

  // Shared bar shim for PanelSlider, which styles itself from a bar object.
  readonly property var sliderBar: QtObject {
    readonly property color foreground: Color.menu.text
    readonly property color background: Color.menu.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: Style.font.family
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }

  // Clock state is owned here so closed-state activity is provably zero: the
  // timer only runs while the panel is open.
  property date now: new Date()
  Timer {
    running: root.opened
    interval: 1000
    repeat: true
    onTriggered: {
      root.now = new Date()
      root.resolvePomodoroExpiry()
    }
  }

  // ---- first-party reactive services ---------------------------------------
  // Resolved at each open. These are keepLoaded services; when one is absent
  // its control shows the unavailable reason instead of an action.
  property var dndService: null
  property var nightlightService: null
  property var idleService: null

  function refreshServices() {
    var host = shell && typeof shell.serviceFor === "function" ? shell : null
    dndService = host ? host.serviceFor("omarchy.notifications") : null
    nightlightService = host ? host.serviceFor("omarchy.nightlight") : null
    idleService = host ? host.serviceFor("omarchy.idle") : null
  }

  // ---- audio (reactive PipeWire state; one action path) --------------------
  readonly property var audioSink: Pipewire.defaultAudioSink
  readonly property var audioSource: Pipewire.defaultAudioSource
  readonly property real outputVolume: audioSink && audioSink.audio ? audioSink.audio.volume : 0
  readonly property bool outputMuted: audioSink && audioSink.audio ? audioSink.audio.muted === true : false
  readonly property bool inputMuted: audioSource && audioSource.audio ? audioSource.audio.muted === true : false

  // PipeWire node properties stay bound only while the panel is open.
  PwObjectTracker {
    objects: root.opened ? [root.audioSink, root.audioSource].filter(Boolean) : []
  }

  function setOutputVolume(value) {
    if (audioSink && audioSink.audio)
      audioSink.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
  }

  function toggleOutputMute() {
    if (audioSink && audioSink.audio) audioSink.audio.muted = !audioSink.audio.muted
  }

  function toggleInputMute() {
    if (audioSource && audioSource.audio) audioSource.audio.muted = !audioSource.audio.muted
  }

  function toggleDnd() {
    if (dndService && typeof dndService.setDoNotDisturb === "function")
      dndService.setDoNotDisturb(!(dndService.doNotDisturb === true))
  }

  function toggleNightlight() {
    if (nightlightService && typeof nightlightService.toggle === "function")
      nightlightService.toggle()
  }

  function toggleStayAwake() {
    if (idleService && typeof idleService.setIdleEnabled === "function")
      idleService.setIdleEnabled(!(idleService.idleEnabled === true))
  }

  // ---- bluetooth (native reactive adapter state) ---------------------------
  readonly property var btAdapter: Bluetooth.defaultAdapter

  function toggleBluetooth() {
    if (btAdapter) btAdapter.enabled = !(btAdapter.enabled === true)
  }

  // ---- keybind cheatsheet (plain-text hyprctl binds) -----------------------
  // The JSON form blanks the key for every code:NN bind, so the text output
  // is the source of truth. Fetched on each entry to the keys page; typing
  // filters (the key catcher feeds keysQuery), Backspace edits, Escape
  // clears the query before it closes the panel.
  property var keybindRows: []
  property string keysQuery: ""

  Process {
    id: bindsProcess
    command: ["hyprctl", "binds"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.keybindRows = NexusKeybindsModel.parseBindsText(text)
    }
  }

  readonly property var filteredKeybinds: NexusKeybindsModel.filterBinds(keybindRows, keysQuery)

  // ---- hardware sensors ----------------------------------------------------
  // Discovery once per open (hwmon indices are probe-order); sampling greps
  // exactly the selected paths (self-labeling, shift-immune). An NVIDIA
  // display GPU has no sysfs telemetry, so nvidia-smi joins the cadence;
  // its absence just drops the GPU row.
  property var sensorsCatalog: null
  property var sensorsSpec: null
  property var sensorSampleMap: ({})
  property var nvidiaInfo: null
  property bool nvidiaAvailable: true

  readonly property var sensorReadings: sensorsSpec
    ? NexusSensorsModel.readings(sensorsSpec, sensorSampleMap, nvidiaInfo, sensorsCatalog) : []

  Process {
    id: sensorDiscoveryProcess
    command: NexusSensorsModel.discoveryCommand()

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.sensorsCatalog = NexusSensorsModel.parseDiscovery(text)
        root.sensorsSpec = NexusSensorsModel.selectSensors(root.sensorsCatalog)
        root.runSensorSample()
      }
    }

    // find -L reports harmless sysfs symlink loops; keep them out of the log.
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: sensorSampleProcess
    command: ["grep", "-H", ".", "/dev/null"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sensorSampleMap = NexusSensorsModel.parseLines(text)
    }
  }

  Process {
    id: nvidiaProcess
    property bool exitSeen: false
    command: NexusSensorsModel.nvidiaCommand()
    onRunningChanged: if (!running && !exitSeen) root.nvidiaAvailable = false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        nvidiaProcess.exitSeen = true
        root.nvidiaInfo = NexusSensorsModel.parseNvidiaSmi(text)
      }
    }
  }

  function runSensorSample() {
    if (!sensorsSpec || !sensorsCatalog) return
    var paths = NexusSensorsModel.samplePaths(sensorsSpec, sensorsCatalog)
    if (paths.length > 0) {
      sensorSampleProcess.command = NexusSensorsModel.sampleCommand(paths)
      if (!sensorSampleProcess.running) sensorSampleProcess.running = true
    }
    if (sensorsSpec.gpu && sensorsSpec.gpu.kind === "nvidia" && nvidiaAvailable
        && !nvidiaProcess.running) {
      nvidiaProcess.exitSeen = false
      nvidiaProcess.running = true
    }
  }

  Timer {
    running: root.opened && root.sensorsSpec !== null && root.settings.showSensors
    interval: NexusSensorsModel.SENSOR_INTERVAL_MS
    repeat: true
    onTriggered: root.runSensorSample()
  }

  // ---- cava visualizer (behind the media card) -----------------------------
  // Raw ascii frames from cava, one line per frame, parsed through the
  // model. Runs only while the panel is open on Overview with media playing;
  // a start failure (cava not installed) hides the strip for the session.
  property bool cavaAvailable: true
  property bool cavaConfWritten: false
  property var cavaBars: NexusCavaModel.silentFrame()
  readonly property string cavaConfFile: NexusCavaModel.confPath(settingsDir)

  FileView {
    id: cavaConfWriter
    path: root.cavaConfFile
    printErrors: false
    atomicWrites: true
    onSaved: {
      root.cavaConfWritten = true
      reload()
    }
  }

  Process {
    id: cavaProcess
    property bool exitSeen: false
    running: root.opened && root.page === "overview" && root.cavaConfWritten
      && root.cavaAvailable && root.settings.showMedia && root.settings.showVisualizer
      && root.mediaSelected !== null && root.mediaSelected.isPlaying
    command: NexusCavaModel.cavaCommand(root.cavaConfFile)
    onStarted: exitSeen = true
    onRunningChanged: {
      if (!running && !exitSeen) root.cavaAvailable = false
      if (!running) root.cavaBars = NexusCavaModel.silentFrame()
      if (running) exitSeen = false
    }

    stdout: SplitParser {
      onRead: function (line) {
        var frame = NexusCavaModel.parseFrame(line)
        if (frame !== null) root.cavaBars = frame
      }
    }
  }

  // ---- suite integrations --------------------------------------------------
  // Read-only views over the state files sibling plugins maintain. Every
  // reader is opened-gated and watch-driven; absent files just hide their
  // card. No subprocesses anywhere in this section.

  // Screen time (community.screen-time day files).
  readonly property string screenTimeFile: NexusSuiteModel.screenTimeDayPath(
    NexusSuiteModel.screenTimeDir(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME")),
    NexusSuiteModel.dayKey(now.getTime()))
  property string screenTimeText: ""
  readonly property var screenTimeSummary: NexusSuiteModel.screenTimeSummary(
    screenTimeText, NexusSuiteModel.dayKey(now.getTime()))

  FileView {
    path: root.opened && root.settings.showScreenTime ? root.screenTimeFile : ""
    printErrors: false
    watchChanges: true
    onLoaded: root.screenTimeText = text()
    onLoadFailed: root.screenTimeText = ""
    onFileChanged: reload()
  }

  // Calendar (community.calendar-agenda ICS caches).
  readonly property string calendarCacheDir: NexusAgendaModel.stateDir(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  property var calendarTexts: []

  Repeater {
    model: 8

    Item {
      id: calendarDelegate
      required property int index

      FileView {
        path: root.opened && root.settings.showNextEvent
          ? NexusAgendaModel.cachePath(root.calendarCacheDir, calendarDelegate.index) : ""
        printErrors: false
        watchChanges: true
        onLoaded: root.storeCalendarText(calendarDelegate.index, text())
        onFileChanged: reload()
      }
    }
  }

  function storeCalendarText(index, text) {
    var next = calendarTexts.slice()
    while (next.length <= index) next.push("")
    next[index] = text
    calendarTexts = next
  }

  readonly property var nextEvent: NexusAgendaModel.upcoming(
    NexusAgendaModel.mergeAgendas(calendarTexts, 7, now.getTime()), now.getTime())

  // Pomodoro (shared state file with community.pomodoro). Nexus reads and
  // starts/pauses sessions; expiry is resolved here too while open, which
  // is benign alongside the bar widget (identical resolved content).
  readonly property string pomodoroFile: NexusPomodoroModel.statePath(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  readonly property var pomodoroConfig: NexusPomodoroModel.readConfig({})
  property var pomodoroSession: NexusPomodoroModel.idleState()

  FileView {
    path: root.opened ? root.pomodoroFile : ""
    printErrors: false
    watchChanges: true
    onLoaded: root.pomodoroSession = NexusPomodoroModel.parseState(text())
    onLoadFailed: root.pomodoroSession = NexusPomodoroModel.idleState()
    onFileChanged: reload()
  }

  FileView {
    id: pomodoroWriter
    path: root.pomodoroFile
    printErrors: false
    atomicWrites: true
    onSaved: reload()
  }

  function persistPomodoro(next) {
    pomodoroSession = next
    pomodoroWriter.setText(NexusPomodoroModel.serializeState(next))
  }

  function togglePomodoro() {
    var nowMs = Date.now()
    if (pomodoroSession.phase === "idle")
      persistPomodoro(NexusPomodoroModel.startPhase(pomodoroSession, "work", nowMs, pomodoroConfig))
    else if (NexusPomodoroModel.isPaused(pomodoroSession))
      persistPomodoro(NexusPomodoroModel.resume(pomodoroSession, nowMs))
    else
      persistPomodoro(NexusPomodoroModel.pause(pomodoroSession, nowMs))
  }

  function resolvePomodoroExpiry() {
    if (pomodoroSession.phase === "idle" || NexusPomodoroModel.isPaused(pomodoroSession)) return
    if (NexusPomodoroModel.remainingMs(pomodoroSession, Date.now()) > 0) return
    persistPomodoro(NexusPomodoroModel.resolveState(pomodoroSession, Date.now(), pomodoroConfig))
  }

  // Notification history (the omarchy.notifications state file; clearing
  // goes through the already-resolved service).
  readonly property string notificationsFile: NexusSuiteModel.notificationsPath(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  property string notificationsText: ""
  readonly property var notificationRows: NexusSuiteModel.parseNotifications(notificationsText, 40)

  FileView {
    path: root.opened ? root.notificationsFile : ""
    printErrors: false
    watchChanges: true
    onLoaded: root.notificationsText = text()
    onLoadFailed: root.notificationsText = ""
    onFileChanged: reload()
  }

  function clearNotificationHistory() {
    if (dndService && typeof dndService.clearPast === "function") dndService.clearPast()
  }

  // Quick notes: one markdown file, debounce-autosaved.
  readonly property string notesFile: NexusSuiteModel.notesPath(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  property bool notesLoaded: false
  property bool notesDirty: false

  FileView {
    id: notesReader
    path: root.opened ? root.notesFile : ""
    printErrors: false
    watchChanges: true
    onLoaded: {
      if (!root.notesDirty) notesEditor.text = text()
      root.notesLoaded = true
    }
    onLoadFailed: root.notesLoaded = true
    onFileChanged: reload()
  }

  FileView {
    id: notesWriter
    path: root.notesFile
    printErrors: false
    atomicWrites: true
    onSaved: {
      root.notesDirty = false
      reload()
    }
  }

  function saveNotes() {
    if (!notesDirty) return
    notesWriter.setText(notesEditor.text)
  }

  Timer {
    id: notesSaveTimer
    running: root.notesDirty
    interval: 1500
    onTriggered: root.saveNotes()
  }

  // ---- game mode (flag file shared with community.game-mode) ---------------
  // Presence of the flag in Omarchy's sourced toggles directory is the whole
  // state; removing it restores the user's exact config. The strip set comes
  // from the gm* settings, so the Settings page decides what game mode does.
  readonly property string gameModeDir: NexusGameModeModel.stateDir(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  readonly property string gameModeFile: NexusGameModeModel.flagPath(
    Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
  readonly property var gameModeFlagContent: NexusGameModeModel.buildFlagContent(settings)
  property bool gameModeOn: false
  property bool gameModePending: false
  property string gameModeError: ""

  FileView {
    id: gameModeProbe
    path: root.opened ? root.gameModeFile : ""
    printErrors: false
    watchChanges: true
    onLoaded: root.gameModeOn = true
    onLoadFailed: root.gameModeOn = false
    onFileChanged: root.syncGameMode()
  }

  function syncGameMode() {
    gameModeProbe.reload()
    // The writer's write-compare cache must track disk (setText de-dupes).
    flagWriter.reload()
  }

  // Quickshell emits no `exited` when a binary cannot be started, only
  // runningChanged — an exit that was never seen is a start failure.
  function runProcess(proc) {
    proc.exitSeen = false
    proc.running = true
  }

  function toggleGameMode() {
    if (gameModePending || !opened) return
    gameModeError = ""
    if (gameModeOn) {
      gameModePending = true
      runProcess(removeFlagProcess)
    } else {
      if (gameModeFlagContent === null) {
        gameModeError = "Nothing selected to strip — pick effects in Settings."
        return
      }
      gameModePending = true
      ensureDirsProcess.writeFlagAfter = true
      runProcess(ensureDirsProcess)
    }
  }

  function finishGameMode(ok, message) {
    gameModePending = false
    gameModeError = ok ? "" : message
    syncGameMode()
  }

  // One idempotent dir-ensure serves both writers (game-mode flag and the
  // settings state file); fixed argument array, fired only on user action.
  Process {
    id: ensureDirsProcess
    property bool exitSeen: false
    property bool writeFlagAfter: false
    property bool writeStateAfter: false
    property bool writeCavaAfter: false
    command: ["mkdir", "-p", root.gameModeDir, root.settingsDir]
    onRunningChanged: if (!running && !exitSeen) {
      if (writeFlagAfter) root.finishGameMode(false, "mkdir could not be started")
      if (writeStateAfter) root.settingsError = "mkdir could not be started"
      writeFlagAfter = false
      writeStateAfter = false
      writeCavaAfter = false
    }
    onExited: function (exitCode) {
      exitSeen = true
      var flagWanted = writeFlagAfter
      var stateWanted = writeStateAfter
      var cavaWanted = writeCavaAfter
      writeFlagAfter = false
      writeStateAfter = false
      writeCavaAfter = false
      if (exitCode !== 0) {
        if (flagWanted) root.finishGameMode(false, "could not create the state directories")
        if (stateWanted) root.settingsError = "Could not create the state directories"
        return
      }
      if (flagWanted) flagWriter.setText(root.gameModeFlagContent)
      if (stateWanted) stateWriter.setText(NexusSettingsModel.buildStateJson(root.stateOverrides))
      if (cavaWanted) cavaConfWriter.setText(NexusCavaModel.buildConfig())
    }
  }

  FileView {
    id: flagWriter
    path: root.gameModeFile
    printErrors: false
    atomicWrites: true
    onSaved: root.runProcess(hyprReloadProcess)
    onSaveFailed: root.finishGameMode(false, "could not write the flag file")
  }

  Process {
    id: removeFlagProcess
    property bool exitSeen: false
    command: ["rm", "-f", root.gameModeFile]
    onRunningChanged: if (!running && !exitSeen)
      root.finishGameMode(false, "rm could not be started")
    onExited: function (exitCode) {
      exitSeen = true
      if (exitCode === 0) root.runProcess(hyprReloadProcess)
      else root.finishGameMode(false, "could not remove the flag file")
    }
  }

  Process {
    id: hyprReloadProcess
    property bool exitSeen: false
    command: ["hyprctl", "reload"]
    onRunningChanged: if (!running && !exitSeen)
      root.finishGameMode(false, "hyprctl could not be started")
    onExited: function (exitCode) {
      exitSeen = true
      root.finishGameMode(exitCode === 0, "hyprctl reload failed")
    }
  }

  // ---- per-page keyboard cursor --------------------------------------------
  // Every page's actionable rows are keyboard-reachable. Row order:
  //   overview: 0 media transport, 1 seek, 2 player switcher (when > 1);
  //   controls: 0 volume, 1 mute, 2 microphone, 3 dnd, 4 night light,
  //             5 stay awake, 6 bluetooth, 7 game mode, 8 capture, 9 power;
  //   style:    0 theme, 1 background;
  //   settings: one row per settingsRows entry.
  // -1 means the tab row owns focus. The cursor resets on page change.
  property int controlCursor: -1
  onPageChanged: {
    controlCursor = -1
    keysQuery = ""
    if (page === "keys" && opened && !bindsProcess.running) bindsProcess.running = true
    if (opened) Qt.callLater(function () {
      if (!root.opened) return
      if (root.page === "notes") notesEditor.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }
  // The cursor must never outlive its row: when a page loses rows (player
  // vanished, chip hidden), clamp back into range.
  onLastCursorIndexChanged: if (controlCursor > lastCursorIndex) controlCursor = lastCursorIndex

  // The Settings page's rows, in cursor order. Two sections: what shows on
  // the panel, and what game mode strips.
  readonly property var settingsRows: [
    { key: "showMedia", label: "Media card", desc: "Artwork, transport, and seek bar on Overview." },
    { key: "showMetrics", label: "Metric meters", desc: "Master switch for the arc meters and network card." },
    { key: "showCpu", label: "CPU meter", desc: "" },
    { key: "showMemory", label: "Memory meter", desc: "" },
    { key: "showStorage", label: "Storage meter", desc: "" },
    { key: "showBattery", label: "Battery meter", desc: "Hide on desktops without a battery." },
    { key: "showNetwork", label: "Network card", desc: "Live down/up throughput sparkline." },
    { key: "showSensors", label: "Sensors card", desc: "CPU/GPU/NVMe temperatures and fans." },
    { key: "showVisualizer", label: "Audio visualizer", desc: "Spectrum bars while media plays (needs cava installed)." },
    { key: "showScreenTime", label: "Screen time card", desc: "Today's focused time (needs community.screen-time)." },
    { key: "showNextEvent", label: "Next event line", desc: "Calendar countdown in the hero (needs community.calendar-agenda)." },
    { key: "showFetch", label: "System info line", desc: "hostname · kernel · uptime under the clock." },
    { key: "gmAnimations", label: "Animations", desc: "", section: "game" },
    { key: "gmBlur", label: "Blur", desc: "", section: "game" },
    { key: "gmShadows", label: "Shadows", desc: "", section: "game" },
    { key: "gmGaps", label: "Gaps", desc: "", section: "game" },
    { key: "gmRounding", label: "Rounding", desc: "", section: "game" },
    { key: "gmTearing", label: "Allow tearing", desc: "Master tearing switch; windowed games may also need an immediate window rule.", section: "game" }
  ]

  readonly property int lastCursorIndex: {
    if (page === "controls") return 10
    if (page === "overview") {
      if (!settings.showMedia || mediaSelected === null) return -1
      return mediaPlayerCount > 1 ? 2 : 1
    }
    if (page === "style") return 1
    if (page === "settings") return settingsRows.length - 1
    if (page === "media") return mediaAllPlayers.length - 1
    return -1
  }

  function activateControl(index) {
    if (page === "overview") {
      if (index === 0) mediaAction("playpause")
      else if (index === 2) cycleMediaPlayer()
    } else if (page === "controls") {
      if (index === 0) dispatchControl("mute-output", toggleOutputMute)
      else if (index === 1) dispatchControl("mute-output", toggleOutputMute)
      else if (index === 2) dispatchControl("mute-microphone", toggleInputMute)
      else if (index === 3) dispatchControl("dnd", toggleDnd)
      else if (index === 4) dispatchControl("night-light", toggleNightlight)
      else if (index === 5) dispatchControl("stay-awake", toggleStayAwake)
      else if (index === 6) dispatchControl("bluetooth", toggleBluetooth)
      else if (index === 7) toggleGameMode()
      else if (index === 8) togglePomodoro()
      else if (index === 9) openMenuRoute("trigger.capture")
      else if (index === 10) openMenuRoute("system")
    } else if (page === "style") {
      if (index === 0) openMenuRoute("style.theme")
      else if (index === 1) openMenuRoute("style.background")
    } else if (page === "settings") {
      var row = settingsRows[index]
      if (row) updateSetting(row.key, settings[row.key] !== true)
    } else if (page === "media") {
      var player = mediaAllPlayers[index]
      if (player) {
        selectPlayerByObject(player)
        if (player.isPlaying && player.canPause) player.pause()
        else if (!player.isPlaying && player.canPlay) player.play()
      }
    }
  }

  // ---- directional page slide ----------------------------------------------
  // The page content slides in from the direction of travel. Direction comes
  // from the same adjacency model the keyboard uses, so wrapping moves feel
  // continuous instead of jumping the long way.
  property real pageShift: 0
  NumberAnimation {
    id: pageSlideAnim
    target: root
    property: "pageShift"
    to: 0
    duration: 160
    easing.type: Easing.OutCubic
  }

  function setPage(next) {
    if (next === page || NexusModel.PAGES.indexOf(next) === -1) return
    var forward = NexusModel.adjacentPage(page, 1) === next
    pageSlideAnim.stop()
    pageShift = forward ? 1 : -1
    page = next
    pageSlideAnim.restart()
  }

  // ---- menu delegation -----------------------------------------------------
  // Style, capture, and power actions close Nexus and open the existing
  // Omarchy menu in-process; the routes are fixed strings, never user input.
  // Destructive power actions get their confirming second interaction inside
  // the menu itself.
  function openMenuRoute(route) {
    var host = shell
    requestClose()
    if (host && typeof host.summon === "function")
      host.summon("omarchy.menu", JSON.stringify({ menu: String(route) }))
  }

  // Cross-plugin hand-off to a sibling panel (screen-time, calendar): close
  // first so overlays never stack.
  function summonSibling(pluginId) {
    var host = shell
    requestClose()
    if (host && typeof host.summon === "function") host.summon(String(pluginId), "{}")
  }

  // ---- media adapter -------------------------------------------------------
  // One direct MPRIS adapter; selection is the deterministic two-phase model
  // in NexusMediaModel. All reactivity is gated on `opened` (the watcher
  // Repeater below has an empty model while closed), so closed-state media
  // activity is zero. Serial history is session-scoped.
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  property var mediaSerials: ({})
  property int mediaLastSerial: 0
  property var mediaSelected: null
  // Manual player choice from the switcher chip; wins while that player
  // exists, cleared on close. Count drives the chip's visibility.
  property string mediaOverrideKey: ""
  property int mediaPlayerCount: 0
  property var mediaAllPlayers: []
  // Seek preview while dragging, so the bar tracks the pointer instead of
  // the (as yet unmoved) player position.
  property bool seekDragging: false
  property real seekPreviewFraction: 0

  // The player's usable track length: only a supported, positive length may
  // drive the seek bar (an unsupported length mirrors position and would pin
  // the bar to 100%).
  readonly property real mediaUsableLength: mediaSelected
    && mediaSelected.lengthSupported && mediaSelected.length > 0
    ? mediaSelected.length : 0

  function playbackStateOf(player) {
    if (player.playbackState === MprisPlaybackState.Playing) return "playing"
    if (player.playbackState === MprisPlaybackState.Paused) return "paused"
    if (player.playbackState === MprisPlaybackState.Stopped) return "stopped"
    return "unknown"
  }

  function mediaRecordOf(player) {
    return NexusMediaModel.buildRecord({
      busName: player.dbusName || "",
      identity: player.identity || "",
      desktopEntry: player.desktopEntry || "",
      state: playbackStateOf(player),
      trackKey: [player.trackTitle || "", player.trackArtist || ""].join("\u0000"),
      canPlay: !!player.canPlay,
      canPause: !!player.canPause,
      canGoNext: !!player.canGoNext,
      canGoPrevious: !!player.canGoPrevious
    })
  }

  function refreshMedia() {
    if (!opened) return
    var players = mprisPlayers
    var recordsList = []
    for (var i = 0; i < players.length; i++) {
      if (players[i]) recordsList.push(mediaRecordOf(players[i]))
    }
    var activity = NexusMediaModel.reconcileActivity(mediaSerials, recordsList, mediaLastSerial)
    mediaSerials = activity.serials
    mediaLastSerial = activity.lastSerial
    mediaPlayerCount = NexusMediaModel.countPlayers(recordsList)
    // The full ordered representative list backs the Media page.
    var representatives = NexusMediaModel.orderedRepresentatives(
      recordsList, NexusMediaModel.normalizeIdentity(settings.preferredMediaIdentity), mediaSerials)
    var ordered = []
    for (var r = 0; r < representatives.length; r++) {
      for (var p = 0; p < players.length; p++) {
        if (players[p] && String(players[p].dbusName || "") === representatives[r].busName) {
          ordered.push(players[p])
          break
        }
      }
    }
    mediaAllPlayers = ordered
    var chosen = NexusMediaModel.selectPlayer(
      recordsList, settings.preferredMediaIdentity, mediaSerials, mediaOverrideKey)
    var next = null
    if (chosen) {
      for (var j = 0; j < players.length; j++) {
        if (players[j] && String(players[j].dbusName || "") === chosen.busName) {
          next = players[j]
          break
        }
      }
    }
    mediaSelected = next
  }

  function selectPlayerByObject(player) {
    if (!player) return
    mediaOverrideKey = mediaRecordOf(player).sourceKey
    refreshMedia()
  }

  // Chip action: step to the next player in the deterministic order and pin
  // it as the manual override.
  function cycleMediaPlayer() {
    var players = mprisPlayers
    var recordsList = []
    for (var i = 0; i < players.length; i++) {
      if (players[i]) recordsList.push(mediaRecordOf(players[i]))
    }
    var currentKey = mediaSelected ? mediaRecordOf(mediaSelected).sourceKey : ""
    var nextKey = NexusMediaModel.cyclePlayer(
      recordsList, currentKey, settings.preferredMediaIdentity, mediaSerials)
    if (nextKey === "") return
    mediaOverrideKey = nextKey
    refreshMedia()
  }

  // Seek paths per the verified Quickshell contract: an absolute position
  // write needs canSeek AND positionSupported; the relative seek() needs only
  // canSeek. clampSeek returns null rather than letting a blind seek through.
  function applySeekFraction(fraction) {
    var player = mediaSelected
    if (!player) return
    var target = NexusMediaModel.clampSeek(
      fraction, mediaUsableLength, player.canSeek && player.positionSupported)
    if (target === null) return
    player.position = target
  }

  function seekBy(offsetSeconds) {
    var player = mediaSelected
    if (!player || !player.canSeek) return false
    player.seek(offsetSeconds)
    return true
  }

  // MPRIS position does not tick on its own; emitting positionChanged() once
  // a second re-reads the locally extrapolated value (no D-Bus traffic).
  // Runs only while the panel is open, a player is selected, and playing.
  Timer {
    running: root.opened && root.mediaSelected !== null && root.mediaSelected.isPlaying
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: if (root.mediaSelected) root.mediaSelected.positionChanged()
  }

  // Actions route only to the selected representative and only when it
  // reports the capability; a successful action bumps its activity serial.
  // Returns whether the action was consumed, so the key handler can fall
  // back to page cycling instead of swallowing the keystroke.
  function mediaAction(kind) {
    var player = mediaSelected
    if (!player) return false
    if (kind === "playpause") {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else return false
    } else if (kind === "next") {
      if (!player.canGoNext) return false
      player.next()
    } else if (kind === "previous") {
      if (!player.canGoPrevious) return false
      player.previous()
    } else {
      return false
    }
    var bumped = NexusMediaModel.bumpUserAction(mediaSerials, String(player.dbusName || ""), mediaLastSerial)
    mediaSerials = bumped.serials
    mediaLastSerial = bumped.lastSerial
    refreshMedia()
    return true
  }

  // Player lifecycle and state watcher; empty model while closed.
  Repeater {
    model: root.opened ? root.mprisPlayers : []
    onItemAdded: root.refreshMedia()
    onItemRemoved: root.refreshMedia()

    Item {
      required property var modelData

      Connections {
        target: modelData
        function onPlaybackStateChanged() { root.refreshMedia() }
        function onTrackTitleChanged() { root.refreshMedia() }
        function onTrackArtistChanged() { root.refreshMedia() }
      }
    }
  }

  // ---- metrics sampler -----------------------------------------------------
  // One bounded sampler: cpu/mem via one cat of /proc/stat + /proc/meminfo
  // every 2 s, storage via df every 30 s, both only while open (the timers
  // below stop with `opened`). Units: integer percent; storage in GiB.
  // Readings older than 3x their cadence render as stale ("—").
  property var cpuPrevSample: null
  property var cpuValue: null
  property var memValue: null
  property var diskValue: null
  property double statSampledAt: 0
  property double diskSampledAt: 0

  // Network throughput shares the same single sampler process; rates derive
  // from cumulative counter deltas, histories feed the sparkline.
  property var netPrevSample: null
  property var netRxRate: null
  property var netTxRate: null
  property var netRxHistory: []
  property var netTxHistory: []
  property var uptimeSeconds: null

  // Static system facts for the fetch row: one-shot async reads while open,
  // following the shell's FileView house pattern (never blocking).
  property string hostName: ""
  property string kernelVersion: ""

  FileView {
    path: root.opened ? "/proc/sys/kernel/hostname" : ""
    printErrors: false
    onLoaded: root.hostName = text().trim()
  }

  FileView {
    path: root.opened ? "/proc/sys/kernel/osrelease" : ""
    printErrors: false
    onLoaded: root.kernelVersion = text().trim()
  }

  Process {
    id: statProcess
    command: ["cat", "/proc/stat", "/proc/meminfo", "/proc/net/dev", "/proc/uptime"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NexusMetricsModel.parseSample(text)
        var nowMs = Date.now()
        if (parsed.cpu) {
          root.cpuValue = NexusMetricsModel.cpuPercent(root.cpuPrevSample, parsed.cpu)
          root.cpuPrevSample = parsed.cpu
        }
        if (parsed.mem) root.memValue = parsed.mem.percent
        if (parsed.uptimeSeconds !== null) root.uptimeSeconds = parsed.uptimeSeconds
        if (parsed.net) {
          var prev = root.netPrevSample
          root.netRxRate = NexusMetricsModel.rateBetween(
            prev ? prev.rxBytes : null, prev ? prev.atMs : 0, parsed.net.rxBytes, nowMs)
          root.netTxRate = NexusMetricsModel.rateBetween(
            prev ? prev.txBytes : null, prev ? prev.atMs : 0, parsed.net.txBytes, nowMs)
          root.netPrevSample = { rxBytes: parsed.net.rxBytes, txBytes: parsed.net.txBytes, atMs: nowMs }
          if (root.netRxRate !== null || root.netTxRate !== null) {
            root.netRxHistory = NexusMetricsModel.pushHistory(
              root.netRxHistory, root.netRxRate, NexusMetricsModel.NET_HISTORY_CAP)
            root.netTxHistory = NexusMetricsModel.pushHistory(
              root.netTxHistory, root.netTxRate, NexusMetricsModel.NET_HISTORY_CAP)
          }
        }
        if (parsed.cpu || parsed.mem) root.statSampledAt = nowMs
      }
    }
  }

  Process {
    id: diskProcess
    command: ["df", "-P", "-k", "/"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NexusMetricsModel.parseDiskFree(text)
        if (parsed) {
          root.diskValue = parsed
          root.diskSampledAt = Date.now()
        }
      }
    }
  }

  Timer {
    running: root.opened
    interval: NexusMetricsModel.CPU_MEM_INTERVAL_MS
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statProcess.running) statProcess.running = true
  }

  Timer {
    running: root.opened
    interval: NexusMetricsModel.DISK_INTERVAL_MS
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!diskProcess.running) diskProcess.running = true
  }

  // ---- battery (reactive UPower state; no polling) -------------------------
  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: batteryDevice ? batteryDevice.isPresent === true : false
  readonly property int batteryPercent: batteryPresent
    ? NexusMetricsModel.clampPercent(batteryDevice.percentage) : 0

  // ---- metric staleness ----------------------------------------------------
  // Plain bool bindings: they re-evaluate with the clock but only notify on
  // an actual flip, so the meters are not rebuilt every second.
  readonly property bool statStale: NexusMetricsModel.isStale(
    statSampledAt, now.getTime(), NexusMetricsModel.CPU_MEM_INTERVAL_MS)
  readonly property bool diskStale: NexusMetricsModel.isStale(
    diskSampledAt, now.getTime(), NexusMetricsModel.DISK_INTERVAL_MS)
  readonly property bool statStaleShown: statStale && statSampledAt > 0
  readonly property bool diskStaleShown: diskStale && diskSampledAt > 0

  // ---- arc meter (declarative Shapes; no Canvas repaints) ------------------
  component ArcMeter: Item {
    id: meter
    property string label: ""
    property var percent: null
    property bool stale: false
    property string detail: ""
    implicitHeight: meterColumn.implicitHeight

    readonly property color trackColor: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.12)
    readonly property color valueColor: stale || percent === null
      ? Qt.darker(Color.menu.text, 1.6) : Color.accent

    Column {
      id: meterColumn
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(4)

      Item {
        width: Style.space(64)
        height: Style.space(64)
        anchors.horizontalCenter: parent.horizontalCenter

        Shape {
          id: arcShape
          anchors.fill: parent

          ShapePath {
            strokeWidth: Style.space(5)
            strokeColor: meter.trackColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
              centerX: arcShape.width / 2
              centerY: arcShape.height / 2
              radiusX: arcShape.width / 2 - Style.space(4)
              radiusY: arcShape.height / 2 - Style.space(4)
              startAngle: 135
              sweepAngle: 270
            }
          }

          ShapePath {
            strokeWidth: Style.space(5)
            strokeColor: meter.valueColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
              centerX: arcShape.width / 2
              centerY: arcShape.height / 2
              radiusX: arcShape.width / 2 - Style.space(4)
              radiusY: arcShape.height / 2 - Style.space(4)
              startAngle: 135
              sweepAngle: meter.percent === null ? 0
                : 270 * Math.min(100, Math.max(0, meter.percent)) / 100
            }
          }
        }

        Text {
          anchors.centerIn: parent
          text: meter.percent === null ? "—" : meter.percent + "%"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: meter.label
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: meter.detail
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }
  }

  // If the target output disappears while open, retarget; close when no real
  // screen remains.
  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (!root.opened) return
      var screens = Quickshell.screens || []
      if (!root.targetScreen || screens.indexOf(root.targetScreen) === -1) {
        root.targetScreen = root.targetScreenForOpen()
        if (!root.targetScreen) root.requestClose()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-nexus"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.requestClose()
    }

    BorderSurface {
      id: card

      // Bar-aware safe margins: clear the live bar only on the edge it
      // occupies, with token gaps everywhere else and a themed fallback size.
      readonly property string barPosition: root.shell && root.shell.barConfig
        ? String(root.shell.barConfig.position || "top") : "top"
      readonly property bool barVisible: root.shell && root.shell.bar
        ? root.shell.bar.barHidden !== true : false
      readonly property int liveBarSize: root.shell && root.shell.bar && root.shell.bar.barSize !== undefined
        ? Math.max(0, Number(root.shell.bar.barSize))
        : (barPosition === "left" || barPosition === "right" ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
      function edgeClearance(edge) {
        return (barVisible && barPosition === edge ? liveBarSize : 0) + Style.gapsOut
      }

      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: edgeClearance("right")
      anchors.topMargin: edgeClearance("top")
      // Preferred width stays inside the 360-560 logical-pixel band even
      // when the theme spacing scale inflates Style.space().
      readonly property int preferredWidth: Math.min(Style.space(420), 560)
      width: Math.min(preferredWidth, Math.min(Math.floor(panel.width * 0.42),
        panel.width - edgeClearance("left") - edgeClearance("right")))

      // Content-fitted height up to the safe maximum; overflow scrolls inside.
      readonly property int maxHeight: panel.height - edgeClearance("top") - edgeClearance("bottom")
      height: Math.min(contentColumn.implicitHeight + contentTopInset + contentBottomInset, maxHeight)

      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      // Right-to-left slide with fade on open only; close hides immediately.
      property real entrance: root.opened ? 0 : 1
      Behavior on entrance {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }
      transform: Translate { x: card.entrance * Style.space(24) }
      opacity: 1 - card.entrance

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true

        // Left/Right acts on the focused row when the row can use it (volume,
        // transport, seek), otherwise it cycles pages. Tab always cycles.
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            // On the keys page Escape clears the filter first.
            if (root.page === "keys" && root.keysQuery !== "") root.keysQuery = ""
            else root.requestClose()
            event.accepted = true
          } else if (root.page === "keys" && event.key === Qt.Key_Backspace) {
            root.keysQuery = root.keysQuery.slice(0, -1)
            event.accepted = true
          } else if (root.page === "keys" && event.text.length === 1
              && event.text >= " " && event.key !== Qt.Key_Tab) {
            root.keysQuery += event.text
            event.accepted = true
          } else if (event.key === Qt.Key_Down && root.lastCursorIndex >= 0) {
            root.controlCursor = Math.min(root.controlCursor + 1, root.lastCursorIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up && root.controlCursor >= 0) {
            root.controlCursor = root.controlCursor - 1
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
              || event.key === Qt.Key_Space) && root.controlCursor >= 0) {
            root.activateControl(root.controlCursor)
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            var forward = event.key === Qt.Key_Right
            var consumed = false
            if (root.page === "controls" && root.controlCursor === 0) {
              root.setOutputVolume(root.outputVolume + (forward ? 0.05 : -0.05))
              consumed = true
            } else if (root.page === "overview" && root.controlCursor === 0) {
              consumed = root.mediaAction(forward ? "next" : "previous")
            } else if (root.page === "overview" && root.controlCursor === 1) {
              consumed = root.seekBy(forward ? 5 : -5)
            } else if (root.page === "media" && root.controlCursor >= 0) {
              var focusedPlayer = root.mediaAllPlayers[root.controlCursor]
              if (focusedPlayer) {
                if (forward && focusedPlayer.canGoNext) { focusedPlayer.next(); consumed = true }
                else if (!forward && focusedPlayer.canGoPrevious) { focusedPlayer.previous(); consumed = true }
              }
            }
            if (!consumed)
              root.setPage(NexusModel.adjacentPage(root.page, forward ? 1 : -1))
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            root.setPage(NexusModel.adjacentPage(root.page, -1))
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.setPage(NexusModel.adjacentPage(root.page, 1))
            event.accepted = true
          }
        }

        Flickable {
          anchors.fill: parent
          contentHeight: contentColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
          id: contentColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.spacing.md

          // ---- hero: time, workspace context, media artwork ---------------
          Row {
            width: parent.width
            spacing: Style.spacing.md

            Column {
              width: parent.width - (heroArt.visible ? heroArt.width + Style.spacing.md : 0)
              spacing: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                text: Qt.formatTime(root.now, "HH:mm")
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
              Text {
                text: Qt.formatDate(root.now, "dddd, MMMM d")
                color: Qt.darker(Color.menu.text, 1.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Text {
                visible: root.settings.showNextEvent && root.nextEvent !== null
                width: parent.width
                text: "󰃭 " + NexusAgendaModel.countdownLabel(root.nextEvent, root.now.getTime())
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.summonSibling("community.calendar-agenda")
                }
              }
              Text {
                visible: text.length > 0
                text: root.workspaceLabel
                color: Qt.darker(Color.menu.text, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            Rectangle {
              id: heroArt
              visible: root.settings.showMedia
              width: Style.space(72)
              height: Style.space(72)
              radius: Style.cornerRadius
              anchors.verticalCenter: parent.verticalCenter
              color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.06)
              clip: true
              // Restrained accent glow while something is playing.
              border.width: 1
              border.color: root.mediaSelected && root.mediaSelected.isPlaying
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.65)
                : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)

              Image {
                id: artwork
                anchors.fill: parent
                anchors.margins: 1
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: Style.space(144)
                sourceSize.height: Style.space(144)
                source: root.mediaSelected
                  ? NexusMediaModel.allowedArtUrl(root.mediaSelected.trackArtUrl || "")
                  : ""
                visible: status === Image.Ready
              }

              Text {
                anchors.centerIn: parent
                visible: !artwork.visible
                text: "󰝚"
                color: Qt.darker(Color.menu.text, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
              }
            }
          }

          // ---- fetch row: quiet system facts ------------------------------
          Text {
            width: parent.width
            visible: root.settings.showFetch && text.length > 0
            text: NexusMetricsModel.fetchLine(root.hostName, root.kernelVersion, root.uptimeSeconds)
            color: Qt.darker(Color.menu.text, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          PanelSeparator { foreground: Color.menu.text }

          // ---- page tabs (click or scroll) with the settings cog -----------
          Item {
            width: parent.width
            height: tabRow.implicitHeight

            Row {
              id: tabRow
              spacing: Style.spacing.controlGap

              WheelHandler {
                // Touchpads deliver a stream of small deltas (and horizontal
                // scrolls report y === 0); without the guard and the notch
                // threshold one flick would spin through several pages.
                property real wheelAccum: 0
                onActiveChanged: if (!active) wheelAccum = 0
                onWheel: function (event) {
                  if (event.angleDelta.y === 0) return
                  wheelAccum += event.angleDelta.y
                  if (Math.abs(wheelAccum) < 120) return
                  var step = wheelAccum < 0 ? 1 : -1
                  wheelAccum = 0
                  root.setPage(NexusModel.adjacentPage(root.page, step))
                }
              }

              Repeater {
                model: NexusModel.tabPages()

                Button {
                  required property string modelData
                  // Narrow pages render icon-only so the row fits the card.
                  readonly property string icon: NexusModel.pageIcon(modelData)
                  text: icon === "" ? NexusModel.pageTitle(modelData) : ""
                  iconText: icon
                  tooltipText: icon === "" ? "" : NexusModel.pageTitle(modelData)
                  active: root.page === modelData
                  onClicked: root.setPage(modelData)
                }
              }
            }

            Button {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒓"
              active: root.page === "settings"
              tooltipText: "Nexus settings"
              onClicked: root.setPage("settings")
            }
          }

          // ---- page content (slides in from the direction of travel) -------
          Column {
            width: parent.width
            spacing: Style.spacing.md
            opacity: 1 - Math.abs(root.pageShift) * 0.5
            transform: Translate { x: root.pageShift * Style.space(20) }

          // ---- overview: media card ---------------------------------------
          BorderSurface {
            visible: root.page === "overview" && root.settings.showMedia
            width: parent.width
            implicitHeight: mediaColumn.implicitHeight + Style.spacing.rowPaddingX * 2
            radius: Style.cornerRadius
            color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
            borderSpec: Border.flat(Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10), 1)

            Column {
              id: mediaColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(6)

              Row {
                id: mediaRow
                width: parent.width
                spacing: Style.space(12)

                Column {
                  width: parent.width - controlsRow.width - Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: root.mediaSelected
                      ? (root.mediaSelected.trackTitle || root.mediaSelected.identity || "Unknown track")
                      : "Nothing playing"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.mediaSelected ? (root.mediaSelected.trackArtist || "") : ""
                    color: Qt.darker(Color.menu.text, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: controlsRow
                  spacing: Style.spacing.controlGap
                  anchors.verticalCenter: parent.verticalCenter

                  Button {
                    iconText: "󰒮"
                    enabled: root.mediaSelected !== null && root.mediaSelected.canGoPrevious
                    onHovered: function (h) { if (h) root.controlCursor = 0 }
                    onClicked: root.mediaAction("previous")
                  }
                  Button {
                    iconText: root.mediaSelected && root.mediaSelected.isPlaying ? "󰏤" : "󰐊"
                    enabled: root.mediaSelected !== null
                      && (root.mediaSelected.isPlaying ? root.mediaSelected.canPause : root.mediaSelected.canPlay)
                    hasCursor: root.controlCursor === 0 && root.page === "overview"
                    onHovered: function (h) { if (h) root.controlCursor = 0 }
                    onClicked: root.mediaAction("playpause")
                  }
                  Button {
                    iconText: "󰒭"
                    enabled: root.mediaSelected !== null && root.mediaSelected.canGoNext
                    onHovered: function (h) { if (h) root.controlCursor = 0 }
                    onClicked: root.mediaAction("next")
                  }
                }
              }

              // Seek bar: elapsed, draggable track, total. Display-only when
              // the player reports no usable length or cannot seek.
              Row {
                width: parent.width
                visible: root.mediaSelected !== null
                spacing: Style.space(8)

                readonly property real barFraction: {
                  if (root.seekDragging) return root.seekPreviewFraction
                  if (!root.mediaSelected || root.mediaUsableLength <= 0) return 0
                  var fraction = NexusMediaModel.positionFraction(
                    root.mediaSelected.position, root.mediaUsableLength)
                  return fraction === null ? 0 : fraction
                }
                readonly property bool seekable: root.mediaSelected !== null
                  && root.mediaSelected.canSeek && root.mediaSelected.positionSupported
                  && root.mediaUsableLength > 0

                Text {
                  id: elapsedLabel
                  // Reserve the total label's width so the growing elapsed
                  // string cannot shift the track geometry mid-drag.
                  width: totalLabel.width
                  horizontalAlignment: Text.AlignLeft
                  text: root.mediaSelected
                    ? (root.mediaSelected.positionSupported
                        ? NexusMediaModel.formatPlaybackTime(root.seekDragging
                            ? root.seekPreviewFraction * root.mediaUsableLength
                            : root.mediaSelected.position)
                        : "─")
                    : ""
                  color: Qt.darker(Color.menu.text, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                  id: seekTrack
                  width: parent.width - elapsedLabel.width - totalLabel.width - 2 * parent.spacing
                  height: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Style.space(3)
                    radius: height / 2
                    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.14)
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * parent.parent.barFraction
                    height: Style.space(3)
                    radius: height / 2
                    color: root.controlCursor === 1 && root.page === "overview"
                      ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.75)
                  }

                  Rectangle {
                    visible: parent.parent.seekable
                      && (seekMouse.containsMouse || root.seekDragging
                          || (root.controlCursor === 1 && root.page === "overview"))
                    x: parent.width * parent.parent.barFraction - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(10)
                    height: Style.space(10)
                    radius: width / 2
                    color: Color.accent
                  }

                  MouseArea {
                    id: seekMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: parent.parent.seekable
                    onEntered: root.controlCursor = 1
                    onPressed: function (mouse) {
                      root.seekDragging = true
                      root.seekPreviewFraction = Math.max(0, Math.min(1, mouse.x / width))
                    }
                    onPositionChanged: function (mouse) {
                      if (root.seekDragging)
                        root.seekPreviewFraction = Math.max(0, Math.min(1, mouse.x / width))
                    }
                    onReleased: {
                      if (!root.seekDragging) return
                      root.seekDragging = false
                      root.applySeekFraction(root.seekPreviewFraction)
                    }
                    onCanceled: root.seekDragging = false
                  }
                }

                Text {
                  id: totalLabel
                  text: root.mediaUsableLength > 0
                    ? NexusMediaModel.formatPlaybackTime(root.mediaUsableLength) : "─"
                  color: Qt.darker(Color.menu.text, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              // Audio spectrum: subtle accent bars fed by cava while
              // something plays; absent cleanly when cava is not installed.
              Row {
                width: parent.width
                height: Style.space(18)
                visible: cavaProcess.running
                spacing: Math.max(1, Math.floor(width / NexusCavaModel.BAR_COUNT * 0.25))

                Repeater {
                  model: root.cavaBars

                  Rectangle {
                    required property real modelData
                    width: Math.max(2, (parent.width - (NexusCavaModel.BAR_COUNT - 1) * parent.spacing)
                      / NexusCavaModel.BAR_COUNT)
                    height: Math.max(2, parent.height * modelData)
                    y: parent.height - height
                    radius: 1
                    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)
                  }
                }
              }

              // Player switcher chip: visible only when more than one real
              // player is active; click or Enter steps the deterministic order.
              Button {
                visible: root.mediaPlayerCount > 1
                iconText: "󰲸"
                text: root.mediaSelected
                  ? (root.mediaSelected.identity || root.mediaSelected.dbusName || "Player")
                  : ""
                fontSize: Style.font.bodySmall
                hasCursor: root.controlCursor === 2 && root.page === "overview"
                tooltipText: "Switch player (" + root.mediaPlayerCount + " active)"
                onHovered: function (h) { if (h) root.controlCursor = 2 }
                onClicked: root.cycleMediaPlayer()
              }
            }
          }

          // ---- overview: metric cards -------------------------------------
          Grid {
            visible: root.page === "overview" && root.settings.showMetrics
            width: parent.width
            columns: width < Style.space(300) ? 1 : 2
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.md

            ArcMeter {
              visible: root.settings.showCpu
              width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
              label: "CPU"
              percent: !root.statStale && root.cpuValue !== null ? root.cpuValue : null
              stale: root.statStaleShown
              detail: root.statStaleShown ? "Stale" : "Usage"
            }

            ArcMeter {
              visible: root.settings.showMemory
              width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
              label: "Memory"
              percent: !root.statStale && root.memValue !== null ? root.memValue : null
              stale: root.statStaleShown
              detail: root.statStaleShown ? "Stale" : "In use"
            }

            ArcMeter {
              visible: root.settings.showStorage
              width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
              label: "Storage"
              percent: !root.diskStale && root.diskValue ? root.diskValue.percent : null
              stale: root.diskStaleShown
              detail: !root.diskStale && root.diskValue
                ? NexusMetricsModel.formatGib(root.diskValue.availableKb) + " free on " + root.diskValue.mount
                : (root.diskStaleShown ? "Stale" : "Used on /")
            }

            ArcMeter {
              visible: root.settings.showBattery
              width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
              label: "Battery"
              percent: root.batteryPresent ? root.batteryPercent : null
              stale: false
              detail: NexusMetricsModel.batteryDetail(root.batteryPresent,
                root.batteryDevice ? root.batteryDevice.state : 0,
                UPower.onBattery, root.batteryPercent,
                root.batteryDevice ? root.batteryDevice.timeToEmpty : 0,
                root.batteryDevice ? root.batteryDevice.timeToFull : 0)
            }
          }

          // ---- overview: network throughput -------------------------------
          BorderSurface {
            id: netCard
            visible: root.page === "overview" && root.settings.showMetrics && root.settings.showNetwork
            width: parent.width
            implicitHeight: netColumn.implicitHeight + Style.spacing.rowPaddingX * 2
            radius: Style.cornerRadius
            color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
            borderSpec: Border.flat(Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10), 1)

            readonly property bool netStale: NexusMetricsModel.isStale(
              root.statSampledAt, root.now.getTime(), NexusMetricsModel.CPU_MEM_INTERVAL_MS)
            readonly property real netSharedMax: Math.max(
              NexusMetricsModel.historyMax(root.netRxHistory, root.netTxHistory),
              NexusMetricsModel.NET_SCALE_FLOOR)

            function polylineFor(history, w, h) {
              var normalized = NexusMetricsModel.sparklinePoints(history, w, h, netSharedMax)
              var points = []
              for (var i = 0; i < normalized.length; i++)
                points.push(Qt.point(normalized[i].x, normalized[i].y))
              return points
            }

            Column {
              id: netColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(6)

              Item {
                width: parent.width
                height: netTitle.implicitHeight

                Text {
                  id: netTitle
                  anchors.left: parent.left
                  text: "Network"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Row {
                  anchors.right: parent.right
                  spacing: Style.space(10)

                  Text {
                    text: "󰇚 " + (netCard.netStale ? "—" : NexusMetricsModel.formatRate(root.netRxRate))
                    color: netCard.netStale ? Qt.darker(Color.menu.text, 1.6) : Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "󰕒 " + (netCard.netStale ? "—" : NexusMetricsModel.formatRate(root.netTxRate))
                    color: Qt.darker(Color.menu.text, netCard.netStale ? 1.6 : 1.2)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              Item {
                id: netSparkline
                width: parent.width
                height: Style.space(48)

                Text {
                  anchors.centerIn: parent
                  visible: root.netRxHistory.length < 2
                  text: "Sampling…"
                  color: Qt.darker(Color.menu.text, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Shape {
                  anchors.fill: parent
                  visible: root.netRxHistory.length >= 2

                  ShapePath {
                    strokeWidth: 2
                    strokeColor: Qt.darker(Color.menu.text, 1.35)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathPolyline {
                      path: netCard.polylineFor(root.netTxHistory, netSparkline.width, netSparkline.height)
                    }
                  }

                  ShapePath {
                    strokeWidth: 2
                    strokeColor: Color.accent
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathPolyline {
                      path: netCard.polylineFor(root.netRxHistory, netSparkline.width, netSparkline.height)
                    }
                  }
                }
              }
            }
          }

          // ---- overview: hardware sensors ---------------------------------
          BorderSurface {
            visible: root.page === "overview" && root.settings.showMetrics
              && root.settings.showSensors && root.sensorReadings.length > 0
            width: parent.width
            implicitHeight: sensorsColumn.implicitHeight + Style.spacing.rowPaddingX * 2
            radius: Style.cornerRadius
            color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
            borderSpec: Border.flat(Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10), 1)

            Column {
              id: sensorsColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(3)

              Text {
                text: "Sensors"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Repeater {
                model: root.sensorReadings

                Item {
                  required property var modelData
                  width: parent.width
                  height: sensorLabel.implicitHeight

                  Text {
                    id: sensorLabel
                    anchors.left: parent.left
                    text: modelData.label
                    color: Qt.darker(Color.menu.text, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.right: parent.right
                    text: modelData.value
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          // ---- overview: screen time (community.screen-time day file) -----
          BorderSurface {
            visible: root.page === "overview" && root.settings.showScreenTime
              && root.screenTimeSummary !== null
            width: parent.width
            implicitHeight: screenTimeRow.implicitHeight + Style.spacing.rowPaddingX * 2
            radius: Style.cornerRadius
            color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
            borderSpec: Border.flat(Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10), 1)

            Item {
              id: screenTimeRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              implicitHeight: screenTimeLabel.implicitHeight

              Text {
                id: screenTimeLabel
                anchors.left: parent.left
                text: "󱎫 Screen time"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                anchors.right: parent.right
                text: NexusSuiteModel.screenTimeLine(root.screenTimeSummary)
                color: Qt.darker(Color.menu.text, 1.25)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.summonSibling("community.screen-time")
            }
          }

          // ---- media page: every active player ----------------------------
          Column {
            visible: root.page === "media"
            width: parent.width
            spacing: Style.space(4)

            Text {
              visible: root.mediaAllPlayers.length === 0
              width: parent.width
              text: "No active media players."
              color: Qt.darker(Color.menu.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.mediaAllPlayers

              CursorSurface {
                id: playerRow
                required property var modelData
                required property int index
                readonly property bool isSelected: root.mediaSelected === modelData
                width: parent.width
                implicitHeight: playerInner.implicitHeight + Style.spacing.rowPaddingX * 2
                outline: true
                foreground: Color.menu.text
                hasCursor: root.controlCursor === index && root.page === "media"
                current: isSelected

                HoverHandler {
                  onHoveredChanged: if (hovered) root.controlCursor = playerRow.index
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.selectPlayerByObject(playerRow.modelData)
                }

                Row {
                  id: playerInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(10)

                  Column {
                    width: parent.width - playerButtons.width - Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: (playerRow.isSelected ? "● " : "")
                        + (playerRow.modelData.identity || playerRow.modelData.dbusName || "Player")
                      color: playerRow.isSelected ? Color.accent : Color.menu.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      visible: text.length > 0
                      text: {
                        var title = playerRow.modelData.trackTitle || ""
                        var artist = playerRow.modelData.trackArtist || ""
                        return title + (artist !== "" ? " — " + artist : "")
                      }
                      color: Qt.darker(Color.menu.text, 1.35)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Row {
                    id: playerButtons
                    spacing: Style.spacing.controlGap
                    anchors.verticalCenter: parent.verticalCenter

                    Button {
                      iconText: "󰒮"
                      enabled: playerRow.modelData.canGoPrevious === true
                      onClicked: playerRow.modelData.previous()
                    }
                    Button {
                      iconText: playerRow.modelData.isPlaying ? "󰏤" : "󰐊"
                      enabled: playerRow.modelData.isPlaying
                        ? playerRow.modelData.canPause === true
                        : playerRow.modelData.canPlay === true
                      onClicked: playerRow.modelData.isPlaying
                        ? playerRow.modelData.pause() : playerRow.modelData.play()
                    }
                    Button {
                      iconText: "󰒭"
                      enabled: playerRow.modelData.canGoNext === true
                      onClicked: playerRow.modelData.next()
                    }
                  }
                }
              }
            }
          }

          // ---- notes page: autosaving scratchpad --------------------------
          Column {
            visible: root.page === "notes"
            width: parent.width
            spacing: Style.space(4)

            BorderSurface {
              width: parent.width
              implicitHeight: Math.max(Style.space(220), notesEditor.implicitHeight + Style.space(20))
              radius: Style.cornerRadius
              color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
              borderSpec: Border.flat(Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10), 1)

              TextEdit {
                id: notesEditor
                anchors.fill: parent
                anchors.margins: Style.space(10)
                wrapMode: TextEdit.Wrap
                color: Color.menu.text
                selectionColor: Color.accent
                selectedTextColor: Color.menu.background
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                onTextChanged: if (root.notesLoaded && root.page === "notes") root.notesDirty = true
                Keys.onEscapePressed: root.requestClose()
              }
            }

            Text {
              width: parent.width
              text: (root.notesDirty ? "Saving…" : "Saved")
                + " · " + notesEditor.text.length + " characters · markdown at "
                + root.notesFile.replace(/^.*omarchy\//, "…/omarchy/")
              color: Qt.darker(Color.menu.text, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }

          // ---- alerts page: notification history --------------------------
          Column {
            visible: root.page === "alerts"
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              height: alertsTitle.implicitHeight

              Text {
                id: alertsTitle
                anchors.left: parent.left
                text: root.notificationRows.length + " recent notifications"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Button {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.notificationRows.length > 0 && root.dndService !== null
                text: "Clear history"
                fontSize: Style.font.caption
                onClicked: root.clearNotificationHistory()
              }
            }

            Text {
              visible: root.notificationRows.length === 0
              width: parent.width
              text: "No recent notifications."
              color: Qt.darker(Color.menu.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.notificationRows

              Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(1)
                bottomPadding: Style.space(5)

                Item {
                  width: parent.width
                  height: alertApp.implicitHeight

                  Text {
                    id: alertApp
                    anchors.left: parent.left
                    text: (modelData.pending ? "● " : "") + (modelData.app || "unknown")
                    color: modelData.urgency >= 2 ? Color.urgent
                      : (modelData.pending ? Color.accent : Qt.darker(Color.menu.text, 1.25))
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    anchors.right: parent.right
                    text: NexusSuiteModel.relativeTime(modelData.timestamp, root.now.getTime())
                    color: Qt.darker(Color.menu.text, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  text: modelData.summary || "(no summary)"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: text.length > 0
                  text: modelData.body
                  color: Qt.darker(Color.menu.text, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          // ---- keys: searchable keybind cheatsheet ------------------------
          Column {
            visible: root.page === "keys"
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: root.keysQuery === ""
                ? "Type to filter " + root.keybindRows.length + " keybinds · Esc clears"
                : "Filter: " + root.keysQuery + "▏ (" + root.filteredKeybinds.length + " matches)"
              color: root.keysQuery === "" ? Qt.darker(Color.menu.text, 1.4) : Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideLeft
            }

            Repeater {
              model: root.filteredKeybinds.slice(0, 60)

              Item {
                required property var modelData
                width: parent.width
                height: Math.max(comboChip.implicitHeight, bindDesc.implicitHeight) + Style.space(4)

                Rectangle {
                  id: comboChip
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: comboText.implicitWidth + Style.space(12)
                  implicitHeight: comboText.implicitHeight + Style.space(4)
                  height: implicitHeight
                  radius: Style.cornerRadius / 2
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)

                  Text {
                    id: comboText
                    anchors.centerIn: parent
                    text: modelData.combo
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Text {
                  id: bindDesc
                  anchors.left: comboChip.right
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.description !== "" ? modelData.description : "(no description)"
                  color: modelData.description !== "" ? Color.menu.text : Qt.darker(Color.menu.text, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            Text {
              width: parent.width
              visible: root.filteredKeybinds.length > 60
              text: "+" + (root.filteredKeybinds.length - 60) + " more — refine the filter"
              color: Qt.darker(Color.menu.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // ---- controls: volume slider ------------------------------------
          CursorSurface {
            visible: root.page === "controls"
            width: parent.width
            implicitHeight: volumeRow.implicitHeight + Style.spacing.rowPaddingX * 2
            outline: true
            foreground: Color.menu.text
            hasCursor: root.controlCursor === 0

            HoverHandler {
              onHoveredChanged: if (hovered) root.controlCursor = 0
            }

            Row {
              id: volumeRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              Text {
                text: root.outputMuted ? "󰝟" : "󰕾"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                width: Style.space(24)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              PanelSlider {
                id: volumeSlider
                bar: root.sliderBar
                width: parent.width - Style.space(80)
                anchors.verticalCenter: parent.verticalCenter
                enabled: root.audioSink !== null
                value: root.outputVolume
                onMoved: function (v) { root.setOutputVolume(v) }
              }

              Text {
                text: Math.round((volumeSlider.dragging ? volumeSlider.liveValue : root.outputVolume) * 100) + "%"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                width: Style.space(38)
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          // ---- controls: toggles ------------------------------------------
          Column {
            visible: root.page === "controls"
            width: parent.width
            spacing: Style.space(4)

            Toggle {
              width: parent.width
              label: "Mute output"
              description: root.audioSink ? "Silence the default output device." : "No output device available."
              enabled: root.audioSink !== null && root.pendingActionName === ""
              checked: root.outputMuted
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 1
              onHovered: function (h) { if (h) root.controlCursor = 1 }
              onClicked: {
                root.controlCursor = 1
                root.dispatchControl("mute-output", root.toggleOutputMute)
              }
            }

            Toggle {
              width: parent.width
              label: "Mute microphone"
              description: root.audioSource ? "Silence the default input device." : "No input device available."
              enabled: root.audioSource !== null && root.pendingActionName === ""
              checked: root.inputMuted
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 2
              onHovered: function (h) { if (h) root.controlCursor = 2 }
              onClicked: {
                root.controlCursor = 2
                root.dispatchControl("mute-microphone", root.toggleInputMute)
              }
            }

            Toggle {
              width: parent.width
              label: "Do not disturb"
              description: root.dndService ? "Silence notification popups." : "Notifications service unavailable."
              enabled: root.dndService !== null && root.pendingActionName === ""
              checked: root.dndService !== null && root.dndService.doNotDisturb === true
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 3
              onHovered: function (h) { if (h) root.controlCursor = 3 }
              onClicked: {
                root.controlCursor = 3
                root.dispatchControl("dnd", root.toggleDnd)
              }
            }

            Toggle {
              width: parent.width
              label: "Night light"
              description: root.nightlightService ? "Warm the display color temperature." : "Night light service unavailable."
              enabled: root.nightlightService !== null && root.pendingActionName === ""
              checked: root.nightlightService !== null && root.nightlightService.enabled === true
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 4
              onHovered: function (h) { if (h) root.controlCursor = 4 }
              onClicked: {
                root.controlCursor = 4
                root.dispatchControl("night-light", root.toggleNightlight)
              }
            }

            Toggle {
              width: parent.width
              label: "Stay awake"
              description: root.idleService ? "Prevent idle lock and screen off." : "Idle service unavailable."
              enabled: root.idleService !== null && root.pendingActionName === ""
              checked: root.idleService !== null && root.idleService.idleEnabled === false
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 5
              onHovered: function (h) { if (h) root.controlCursor = 5 }
              onClicked: {
                root.controlCursor = 5
                root.dispatchControl("stay-awake", root.toggleStayAwake)
              }
            }

            Toggle {
              width: parent.width
              label: "Bluetooth"
              description: root.btAdapter ? "Power the default Bluetooth adapter." : "No Bluetooth adapter."
              enabled: root.btAdapter !== null && root.pendingActionName === ""
              checked: root.btAdapter !== null && root.btAdapter.enabled === true
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 6
              onHovered: function (h) { if (h) root.controlCursor = 6 }
              onClicked: {
                root.controlCursor = 6
                root.dispatchControl("bluetooth", root.toggleBluetooth)
              }
            }

            Toggle {
              width: parent.width
              label: "Game mode"
              description: root.gameModeError !== ""
                ? root.gameModeError
                : (root.gameModePending
                  ? "Applying…"
                  : (!root.gameModeOn && root.gameModeFlagContent === null
                    ? "Nothing selected to strip — pick effects in Settings."
                    : "Strip compositor effects; configure the set in Settings."))
              enabled: !root.gameModePending
                && (root.gameModeOn || root.gameModeFlagContent !== null)
              checked: root.gameModeOn
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 7 && root.page === "controls"
              onHovered: function (h) { if (h) root.controlCursor = 7 }
              onClicked: {
                root.controlCursor = 7
                root.toggleGameMode()
              }
            }

            Toggle {
              width: parent.width
              label: "Pomodoro"
              description: root.pomodoroSession.phase === "idle"
                ? "Start a focus session (" + root.pomodoroSession.todayCount + " done today)."
                : NexusPomodoroModel.labelFor(root.pomodoroSession.phase)
                  + (NexusPomodoroModel.isPaused(root.pomodoroSession) ? " (paused)" : "")
                  + " — " + NexusPomodoroModel.formatRemaining(
                      NexusPomodoroModel.remainingMs(root.pomodoroSession, root.now.getTime()))
                  + " left. Click to " + (NexusPomodoroModel.isPaused(root.pomodoroSession) ? "resume" : "pause") + "."
              checked: root.pomodoroSession.phase !== "idle"
                && !NexusPomodoroModel.isPaused(root.pomodoroSession)
              foreground: Color.menu.text
              accent: Color.accent
              fontFamily: Style.font.family
              hasCursor: root.controlCursor === 8 && root.page === "controls"
              onHovered: function (h) { if (h) root.controlCursor = 8 }
              onClicked: {
                root.controlCursor = 8
                root.togglePomodoro()
              }
            }
          }

          // ---- controls: capture and power quick actions ------------------
          Row {
            visible: root.page === "controls"
            spacing: Style.spacing.controlGap

            Button {
              iconText: ""
              text: "Capture"
              hasCursor: root.controlCursor === 9 && root.page === "controls"
              onHovered: function (h) { if (h) root.controlCursor = 9 }
              onClicked: root.openMenuRoute("trigger.capture")
            }
            Button {
              iconText: "󰐥"
              text: "Power"
              hasCursor: root.controlCursor === 10 && root.page === "controls"
              onHovered: function (h) { if (h) root.controlCursor = 10 }
              onClicked: root.openMenuRoute("system")
            }
          }

          // ---- style: delegate to the existing selectors ------------------
          Column {
            visible: root.page === "style"
            width: parent.width
            spacing: Style.spacing.md

            Text {
              width: parent.width
              text: "Style actions close Nexus and open the Omarchy selector."
              color: Qt.darker(Color.menu.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.spacing.controlGap

              Button {
                iconText: "󰸌"
                text: "Theme"
                hasCursor: root.controlCursor === 0 && root.page === "style"
                onHovered: function (h) { if (h) root.controlCursor = 0 }
                onClicked: root.openMenuRoute("style.theme")
              }
              Button {
                iconText: ""
                text: "Background"
                hasCursor: root.controlCursor === 1 && root.page === "style"
                onHovered: function (h) { if (h) root.controlCursor = 1 }
                onClicked: root.openMenuRoute("style.background")
              }
            }
          }

          // ---- settings: panel cards and the game-mode strip set -----------
          Column {
            visible: root.page === "settings"
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: "Overview cards"
              color: Qt.darker(Color.menu.text, 1.3)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Repeater {
              model: root.settingsRows.filter(function (row) { return row.section !== "game" })

              Toggle {
                required property var modelData
                required property int index
                width: parent.width
                label: modelData.label
                description: modelData.desc
                checked: root.settings[modelData.key] === true
                foreground: Color.menu.text
                accent: Color.accent
                fontFamily: Style.font.family
                hasCursor: root.controlCursor === index && root.page === "settings"
                onHovered: function (h) { if (h) root.controlCursor = index }
                onClicked: {
                  root.controlCursor = index
                  root.updateSetting(modelData.key, root.settings[modelData.key] !== true)
                }
              }
            }

            Text {
              width: parent.width
              topPadding: Style.space(8)
              text: "Game mode strips"
              color: Qt.darker(Color.menu.text, 1.3)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            // Presets batch-set the six toggles below; "custom" is whatever
            // the individual switches say.
            Row {
              spacing: Style.spacing.controlGap

              Repeater {
                model: NexusSuiteModel.GAME_MODE_PRESETS

                Button {
                  required property var modelData
                  text: modelData.label
                  active: NexusSuiteModel.activePreset(root.settings) === modelData.key
                  fontSize: Style.font.caption
                  onClicked: {
                    for (var key in modelData.settings)
                      root.updateSetting(key, modelData.settings[key])
                  }
                }
              }
            }

            Repeater {
              id: gameRowsRepeater
              model: root.settingsRows.filter(function (row) { return row.section === "game" })
              readonly property int indexOffset: root.settingsRows.length - count

              Toggle {
                required property var modelData
                required property int index
                readonly property int cursorIndex: gameRowsRepeater.indexOffset + index
                width: parent.width
                label: modelData.label
                description: modelData.desc
                checked: root.settings[modelData.key] === true
                foreground: Color.menu.text
                accent: Color.accent
                fontFamily: Style.font.family
                hasCursor: root.controlCursor === cursorIndex && root.page === "settings"
                onHovered: function (h) { if (h) root.controlCursor = cursorIndex }
                onClicked: {
                  root.controlCursor = cursorIndex
                  root.updateSetting(modelData.key, root.settings[modelData.key] !== true)
                }
              }
            }

            Text {
              width: parent.width
              visible: root.settingsError !== ""
              text: root.settingsError
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Changes save to the Nexus state file immediately; the shell.json entry still works for scripted overrides."
              color: Qt.darker(Color.menu.text, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---- placeholder for pages without content yet ------------------
          Text {
            width: parent.width
            visible: text.length > 0
            text: NexusModel.pagePlaceholder(root.page)
            color: Qt.darker(Color.menu.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
          }
          }
        }
      }
    }
  }
}
