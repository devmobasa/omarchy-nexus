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

  // ---- validated settings (never written during open) ----------------------
  readonly property var settings: NexusSettingsModel.readSettings(
    shell && shell.shellConfig ? shell.shellConfig.plugins : null,
    manifest && manifest.id ? manifest.id : "community.omarchy-nexus",
    NexusModel.PAGES)

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
    onTriggered: root.now = new Date()
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

  // ---- per-page keyboard cursor --------------------------------------------
  // Every page's actionable rows are keyboard-reachable. Row order:
  //   overview: 0 media transport, 1 seek, 2 player switcher (when > 1);
  //   controls: 0 volume, 1 mute, 2 microphone, 3 dnd, 4 night light,
  //             5 stay awake, 6 bluetooth, 7 capture, 8 power;
  //   style:    0 theme, 1 background.
  // -1 means the tab row owns focus. The cursor resets on page change.
  property int controlCursor: -1
  onPageChanged: controlCursor = -1
  // The cursor must never outlive its row: when a page loses rows (player
  // vanished, chip hidden), clamp back into range.
  onLastCursorIndexChanged: if (controlCursor > lastCursorIndex) controlCursor = lastCursorIndex

  readonly property int lastCursorIndex: {
    if (page === "controls") return 8
    if (page === "overview") {
      if (!settings.showMedia || mediaSelected === null) return -1
      return mediaPlayerCount > 1 ? 2 : 1
    }
    if (page === "style") return 1
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
      else if (index === 7) openMenuRoute("trigger.capture")
      else if (index === 8) openMenuRoute("system")
    } else if (page === "style") {
      if (index === 0) openMenuRoute("style.theme")
      else if (index === 1) openMenuRoute("style.background")
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
            root.requestClose()
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

          // ---- page tabs (click or scroll) ---------------------------------
          Row {
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
              model: NexusModel.PAGES

              Button {
                required property string modelData
                text: NexusModel.pageTitle(modelData)
                active: root.page === modelData
                onClicked: root.setPage(modelData)
              }
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
              width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
              label: "CPU"
              percent: !root.statStale && root.cpuValue !== null ? root.cpuValue : null
              stale: root.statStaleShown
              detail: root.statStaleShown ? "Stale" : "Usage"
            }

            ArcMeter {
              width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
              label: "Memory"
              percent: !root.statStale && root.memValue !== null ? root.memValue : null
              stale: root.statStaleShown
              detail: root.statStaleShown ? "Stale" : "In use"
            }

            ArcMeter {
              width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
              label: "Storage"
              percent: !root.diskStale && root.diskValue ? root.diskValue.percent : null
              stale: root.diskStaleShown
              detail: !root.diskStale && root.diskValue
                ? NexusMetricsModel.formatGib(root.diskValue.availableKb) + " free on " + root.diskValue.mount
                : (root.diskStaleShown ? "Stale" : "Used on /")
            }

            ArcMeter {
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
          }

          // ---- controls: capture and power quick actions ------------------
          Row {
            visible: root.page === "controls"
            spacing: Style.spacing.controlGap

            Button {
              iconText: ""
              text: "Capture"
              hasCursor: root.controlCursor === 7 && root.page === "controls"
              onHovered: function (h) { if (h) root.controlCursor = 7 }
              onClicked: root.openMenuRoute("trigger.capture")
            }
            Button {
              iconText: "󰐥"
              text: "Power"
              hasCursor: root.controlCursor === 8 && root.page === "controls"
              onHovered: function (h) { if (h) root.controlCursor = 8 }
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
