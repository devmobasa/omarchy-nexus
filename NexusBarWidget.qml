import QtQuick
import qs.Ui

// Bar shortcut for the Nexus panel: one glyph that toggles the panel and
// lights up while it is open. The panel itself stays a normal panel-kind
// plugin — this widget only drives the host's toggle/isPluginOpen surface,
// so summon/hide/keybindings and the widget can never disagree about state.
// `bar` is injected after construction and may be null; every read guards.
BarWidget {
  id: root
  moduleName: "community.omarchy-nexus"

  readonly property var shellRoot: bar ? bar.shell : null
  readonly property bool nexusOpen: shellRoot
    ? shellRoot.isPluginOpen("community.omarchy-nexus") === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    bar: root.bar
    text: "󰕮"
    active: root.nexusOpen
    tooltipText: root.nexusOpen ? "Close Nexus" : "Open Nexus"
    onPressed: if (root.shellRoot) root.shellRoot.toggle("community.omarchy-nexus", "{}")
  }
}
