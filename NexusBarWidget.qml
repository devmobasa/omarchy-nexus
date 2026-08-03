import "model/NexusSuiteModel.js" as NexusSuiteModel
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar shortcut for the Nexus panel: one glyph that toggles the panel and
// lights up while it is open. The panel itself stays a normal panel-kind
// plugin — this widget only drives the host's toggle/isPluginOpen surface,
// so summon/hide/keybindings and the widget can never disagree about state.
// `bar` is injected after construction and may be null; every read guards.
//
// The badge counts unseen notifications from the watched state file the
// notification service maintains — one FileView, no processes, no timers.
BarWidget {
  id: root
  moduleName: "community.omarchy-nexus"

  readonly property var shellRoot: bar ? bar.shell : null
  readonly property bool nexusOpen: shellRoot
    ? shellRoot.isPluginOpen("community.omarchy-nexus") === true : false
  property int pendingCount: 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    bar: root.bar
    text: "󰕮"
    active: root.nexusOpen
    tooltipText: (root.nexusOpen ? "Close Nexus" : "Open Nexus")
      + (root.pendingCount > 0 ? " · " + root.pendingCount + " unseen alerts" : "")
    onPressed: if (root.shellRoot) root.shellRoot.toggle("community.omarchy-nexus", "{}")
  }

  Rectangle {
    visible: root.pendingCount > 0
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: -Style.space(1)
    anchors.topMargin: Style.space(1)
    width: Math.max(badgeText.implicitWidth + Style.space(4), height)
    height: badgeText.implicitHeight + Style.space(2)
    radius: height / 2
    color: Color.accent

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.pendingCount > 99 ? "99+" : String(root.pendingCount)
      color: Color.menu.background
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  FileView {
    path: NexusSuiteModel.notificationsPath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    printErrors: false
    watchChanges: true
    onLoaded: root.pendingCount = NexusSuiteModel.pendingCount(text())
    onLoadFailed: root.pendingCount = 0
    onFileChanged: reload()
  }
}
