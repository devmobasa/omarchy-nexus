import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "model/NexusModel.js" as NexusModel
import "model/NexusMediaModel.js" as NexusMediaModel
import "model/NexusMetricsModel.js" as NexusMetricsModel

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
  readonly property var pendingAction: null
  readonly property string focusRole: "tab"

  // The host marks the plugin open before delivering open() and ignores the
  // return value, so every call must end with a visible surface. A repeated
  // open while visible updates page and target screen without a new surface.
  function open(payloadJson) {
    var normalized = NexusModel.normalizePayload(payloadJson)
    root.page = normalized.page
    root.targetScreen = targetScreenForOpen()
    root.now = new Date()
    root.opened = true
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

  // Clock state is owned here so closed-state activity is provably zero: the
  // timer only runs while the panel is open.
  property date now: new Date()
  Timer {
    running: root.opened
    interval: 1000
    repeat: true
    onTriggered: root.now = new Date()
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
    var chosen = NexusMediaModel.selectPlayer(recordsList, "", mediaSerials)
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
        value: !statStale && cpuValue !== null ? cpuValue + "%" : "—",
        detail: statStale && statSampledAt > 0 ? "Stale" : "Usage"
      },
      {
        label: "Memory",
        value: !statStale && memValue !== null ? memValue + "%" : "—",
        detail: statStale && statSampledAt > 0 ? "Stale" : "In use"
      },
      {
        label: "Storage",
        value: !diskStale && diskValue ? diskValue.percent + "%" : "—",
        detail: !diskStale && diskValue
          ? NexusMetricsModel.formatGib(diskValue.availableKb) + " free on " + diskValue.mount
          : (diskStale && diskSampledAt > 0 ? "Stale" : "Used on /")
      },
      {
        label: "Battery",
        value: batteryPresent ? batteryPercent + "%" : "—",
        detail: NexusMetricsModel.batteryDetail(batteryPresent, UPower.onBattery, batteryPercent)
      }
    ]
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
      width: Math.min(Style.space(420), Math.min(Math.floor(panel.width * 0.42),
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
          if (event.key === Qt.Key_Escape) {
            root.requestClose()
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

          // ---- hero: time and workspace context ---------------------------
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: Qt.formatTime(root.now, "HH:mm")
              color: Color.menu.text
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
            visible: root.page === "overview"
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

              Rectangle {
                id: artworkFrame
                width: Style.space(56)
                height: Style.space(56)
                radius: Style.cornerRadius
                color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.06)
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                Image {
                  id: artwork
                  anchors.fill: parent
                  asynchronous: true
                  fillMode: Image.PreserveAspectCrop
                  sourceSize.width: Style.space(112)
                  sourceSize.height: Style.space(112)
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

              Column {
                width: parent.width - artworkFrame.width - controlsRow.width - Style.space(24)
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
            visible: root.page === "overview"
            width: parent.width
            columns: width < Style.space(300) ? 1 : 2
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.md

            Repeater {
              model: root.metricCards

              BorderSurface {
                required property var modelData
                width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
                implicitHeight: metricColumn.implicitHeight + Style.spacing.rowPaddingX * 2
                radius: Style.cornerRadius
                color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
                borderSpec: Border.flat(Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10), 1)

                Column {
                  id: metricColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(2)

                  Text {
                    text: modelData.label
                    color: Qt.darker(Color.menu.text, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    text: modelData.value
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    text: modelData.detail
                    color: Qt.darker(Color.menu.text, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
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
