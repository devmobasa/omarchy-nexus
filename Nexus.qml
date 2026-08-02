import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "model/NexusModel.js" as NexusModel

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

  // Milestone 1 placeholders; real adapters arrive with the overview slice.
  readonly property bool metricsActive: false
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

      // Conservative token fallback margins that clear a bar on any edge;
      // live bar-edge geometry replaces these during the Milestone 2 checks.
      readonly property int marginY: Style.bar.sizeHorizontal + Style.gapsOut
      readonly property int marginX: Style.bar.sizeVertical + Style.gapsOut

      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: marginX
      anchors.topMargin: marginY
      anchors.bottomMargin: marginY
      width: Math.min(Style.space(420), Math.min(Math.floor(panel.width * 0.42), panel.width - marginX * 2))

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

        Column {
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

          // ---- placeholder page body --------------------------------------
          Text {
            width: parent.width
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
