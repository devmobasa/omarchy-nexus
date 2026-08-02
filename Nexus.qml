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
    root.controlCursor = -1
    root.pendingActionName = ""
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

  // ---- controls keyboard cursor --------------------------------------------
  // Row order: 0 volume, 1 mute, 2 microphone, 3 dnd, 4 night light,
  // 5 stay awake, 6 bluetooth. -1 means the tab row owns focus.
  property int controlCursor: -1
  readonly property int lastControlIndex: 6
  onPageChanged: controlCursor = -1

  function activateControl(index) {
    if (index === 1) dispatchControl("mute-output", toggleOutputMute)
    else if (index === 2) dispatchControl("mute-microphone", toggleInputMute)
    else if (index === 3) dispatchControl("dnd", toggleDnd)
    else if (index === 4) dispatchControl("night-light", toggleNightlight)
    else if (index === 5) dispatchControl("stay-awake", toggleStayAwake)
    else if (index === 6) dispatchControl("bluetooth", toggleBluetooth)
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
    var chosen = NexusMediaModel.selectPlayer(recordsList, settings.preferredMediaIdentity, mediaSerials)
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

  // Actions route only to the selected representative and only when it
  // reports the capability; a successful action bumps its activity serial.
  function mediaAction(kind) {
    var player = mediaSelected
    if (!player) return
    if (kind === "playpause") {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else return
    } else if (kind === "next") {
      if (!player.canGoNext) return
      player.next()
    } else if (kind === "previous") {
      if (!player.canGoPrevious) return
      player.previous()
    } else {
      return
    }
    var bumped = NexusMediaModel.bumpUserAction(mediaSerials, String(player.dbusName || ""), mediaLastSerial)
    mediaSerials = bumped.serials
    mediaLastSerial = bumped.lastSerial
    refreshMedia()
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

  Process {
    id: statProcess
    command: ["cat", "/proc/stat", "/proc/meminfo"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NexusMetricsModel.parseStatAndMem(text)
        if (parsed.cpu) {
          root.cpuValue = NexusMetricsModel.cpuPercent(root.cpuPrevSample, parsed.cpu)
          root.cpuPrevSample = parsed.cpu
        }
        if (parsed.mem) root.memValue = parsed.mem.percent
        if (parsed.cpu || parsed.mem) root.statSampledAt = Date.now()
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

  // ---- metric cards --------------------------------------------------------
  readonly property var metricCards: {
    var nowMs = now.getTime()
    var statStale = NexusMetricsModel.isStale(statSampledAt, nowMs, NexusMetricsModel.CPU_MEM_INTERVAL_MS)
    var diskStale = NexusMetricsModel.isStale(diskSampledAt, nowMs, NexusMetricsModel.DISK_INTERVAL_MS)
    return [
      {
        label: "CPU",
        percent: !statStale && cpuValue !== null ? cpuValue : null,
        stale: statStale && statSampledAt > 0,
        detail: statStale && statSampledAt > 0 ? "Stale" : "Usage"
      },
      {
        label: "Memory",
        percent: !statStale && memValue !== null ? memValue : null,
        stale: statStale && statSampledAt > 0,
        detail: statStale && statSampledAt > 0 ? "Stale" : "In use"
      },
      {
        label: "Storage",
        percent: !diskStale && diskValue ? diskValue.percent : null,
        stale: diskStale && diskSampledAt > 0,
        detail: !diskStale && diskValue
          ? NexusMetricsModel.formatGib(diskValue.availableKb) + " free on " + diskValue.mount
          : (diskStale && diskSampledAt > 0 ? "Stale" : "Used on /")
      },
      {
        label: "Battery",
        percent: batteryPresent ? batteryPercent : null,
        stale: false,
        detail: NexusMetricsModel.batteryDetail(batteryPresent, UPower.onBattery, batteryPercent)
      }
    ]
  }

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

        Keys.onPressed: function (event) {
          var onControls = root.page === "controls"
          if (event.key === Qt.Key_Escape) {
            root.requestClose()
            event.accepted = true
          } else if (event.key === Qt.Key_Down && onControls) {
            root.controlCursor = Math.min(root.controlCursor + 1, root.lastControlIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up && onControls && root.controlCursor >= 0) {
            root.controlCursor = root.controlCursor - 1
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
              || event.key === Qt.Key_Space) && onControls && root.controlCursor >= 0) {
            root.activateControl(root.controlCursor)
            event.accepted = true
          } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right)
              && onControls && root.controlCursor === 0) {
            root.setOutputVolume(root.outputVolume + (event.key === Qt.Key_Left ? -0.05 : 0.05))
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
            root.page = NexusModel.adjacentPage(root.page, -1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.page = NexusModel.adjacentPage(root.page, 1)
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

          PanelSeparator { foreground: Color.menu.text }

          // ---- page tabs ---------------------------------------------------
          Row {
            spacing: Style.spacing.controlGap

            Repeater {
              model: NexusModel.PAGES

              Button {
                required property string modelData
                text: NexusModel.pageTitle(modelData)
                active: root.page === modelData
                onClicked: root.page = modelData
              }
            }
          }

          // ---- overview: media card ---------------------------------------
          BorderSurface {
            visible: root.page === "overview" && root.settings.showMedia
            width: parent.width
            implicitHeight: mediaRow.implicitHeight + Style.spacing.rowPaddingX * 2
            radius: Style.cornerRadius
            color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
            borderSpec: Border.flat(Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10), 1)

            Row {
              id: mediaRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
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
                  onClicked: root.mediaAction("previous")
                }
                Button {
                  iconText: root.mediaSelected && root.mediaSelected.isPlaying ? "󰏤" : "󰐊"
                  enabled: root.mediaSelected !== null
                    && (root.mediaSelected.isPlaying ? root.mediaSelected.canPause : root.mediaSelected.canPlay)
                  onClicked: root.mediaAction("playpause")
                }
                Button {
                  iconText: "󰒭"
                  enabled: root.mediaSelected !== null && root.mediaSelected.canGoNext
                  onClicked: root.mediaAction("next")
                }
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

            Repeater {
              model: root.metricCards

              ArcMeter {
                required property var modelData
                width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
                label: modelData.label
                percent: modelData.percent
                stale: modelData.stale
                detail: modelData.detail
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
              onClicked: root.openMenuRoute("trigger.capture")
            }
            Button {
              iconText: "󰐥"
              text: "Power"
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
                onClicked: root.openMenuRoute("style.theme")
              }
              Button {
                iconText: ""
                text: "Background"
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
