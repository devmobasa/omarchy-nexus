import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
    id: panel

    required property var nexus

    function focusCurrentPage() {
        if (nexus.page === NexusModel.PAGE_NOTES)
            notesPage.focusEditor();
        else
            keyCatcher.forceActiveFocus();
    }

    visible: nexus.opened
    screen: nexus.targetScreen
    color: "transparent"
    WlrLayershell.namespace: "omarchy-nexus"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: nexus.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim
    }

    MouseArea {
        anchors.fill: parent
        onClicked: nexus.requestClose()
    }

    BorderSurface {
        id: card

        readonly property string barPosition: nexus.shell && nexus.shell.barConfig ? String(nexus.shell.barConfig.position || "top") : "top"
        readonly property bool barVisible: nexus.shell && nexus.shell.bar ? nexus.shell.bar.barHidden !== true : false
        readonly property int liveBarSize: nexus.shell && nexus.shell.bar && nexus.shell.bar.barSize !== undefined ? Math.max(0, Number(nexus.shell.bar.barSize)) : (barPosition === "left" || barPosition === "right" ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
        readonly property int preferredWidth: Math.min(Style.space(420), 560)
        readonly property int maxHeight: panel.height - edgeClearance("top") - edgeClearance("bottom")
        property real entrance: nexus.opened ? 0 : 1

        function edgeClearance(edge) {
            return (barVisible && barPosition === edge ? liveBarSize : 0) + Style.gapsOut;
        }

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: edgeClearance("right")
        anchors.topMargin: edgeClearance("top")
        width: Math.min(preferredWidth, Math.min(Math.floor(panel.width * 0.42), panel.width - edgeClearance("left") - edgeClearance("right")))
        height: Math.min(contentColumn.implicitHeight + contentTopInset + contentBottomInset, maxHeight)
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.panelPadding
        opacity: 1 - card.entrance

        MouseArea {
            anchors.fill: parent
            onClicked: {
            }
        }

        Item {
            id: keyCatcher

            anchors.fill: parent
            anchors.topMargin: card.contentTopInset
            anchors.rightMargin: card.contentRightInset
            anchors.bottomMargin: card.contentBottomInset
            anchors.leftMargin: card.contentLeftInset
            focus: true
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (nexus.page === NexusModel.PAGE_KEYS && nexus.keysQuery !== "")
                        nexus.keysQuery = "";
                    else
                        nexus.requestClose();
                    event.accepted = true;
                } else if (nexus.page === NexusModel.PAGE_KEYS && event.key === Qt.Key_Backspace) {
                    nexus.keysQuery = nexus.keysQuery.slice(0, -1);
                    event.accepted = true;
                } else if (nexus.page === NexusModel.PAGE_KEYS && event.text.length === 1 && event.text >= " " && event.key !== Qt.Key_Tab) {
                    nexus.keysQuery += event.text;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down && nexus.lastCursorIndex >= 0) {
                    nexus.controlCursor = Math.min(nexus.controlCursor + 1, nexus.lastCursorIndex);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up && nexus.controlCursor >= 0) {
                    nexus.controlCursor--;
                    event.accepted = true;
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && nexus.controlCursor >= 0) {
                    nexus.activateControl(nexus.controlCursor);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    const forward = event.key === Qt.Key_Right;
                    let consumed = false;
                    if (nexus.page === NexusModel.PAGE_CONTROLS && nexus.controlCursor === NexusModel.CONTROLS_ROWS.VOLUME) {
                        nexus.setOutputVolume(nexus.outputVolume + (forward ? nexus.volumeStep : -nexus.volumeStep));
                        consumed = true;
                    } else if (nexus.page === NexusModel.PAGE_OVERVIEW && nexus.controlCursor === NexusModel.OVERVIEW_ROWS.TRANSPORT) {
                        consumed = nexus.mediaAction(forward ? "next" : "previous");
                    } else if (nexus.page === NexusModel.PAGE_OVERVIEW && nexus.controlCursor === NexusModel.OVERVIEW_ROWS.SEEK) {
                        consumed = nexus.seekBy(forward ? nexus.seekStepSeconds : -nexus.seekStepSeconds);
                    } else if (nexus.page === NexusModel.PAGE_MEDIA && nexus.controlCursor >= 0) {
                        const player = nexus.mediaAllPlayers[nexus.controlCursor];
                        if (player) {
                            if (forward && player.canGoNext) {
                                player.next();
                                consumed = true;
                            } else if (!forward && player.canGoPrevious) {
                                player.previous();
                                consumed = true;
                            }
                        }
                    }
                    if (!consumed)
                        nexus.setPage(NexusModel.adjacentPage(nexus.page, forward ? 1 : -1));

                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    nexus.setPage(NexusModel.adjacentPage(nexus.page, -1));
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    nexus.setPage(NexusModel.adjacentPage(nexus.page, 1));
                    event.accepted = true;
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

                    NexusHero {
                        nexus: panel.nexus
                    }

                    PanelSeparator {
                        foreground: Color.menu.text
                    }

                    NexusTabs {
                        nexus: panel.nexus
                    }

                    Column {
                        width: parent.width
                        spacing: Style.spacing.md
                        opacity: 1 - Math.abs(nexus.pageShift) * 0.5

                        NexusOverviewMedia {
                            nexus: panel.nexus
                        }

                        NexusMetricGrid {
                            nexus: panel.nexus
                        }

                        NexusNetworkCard {
                            nexus: panel.nexus
                        }

                        NexusSensorsCard {
                            nexus: panel.nexus
                        }

                        NexusScreenTimeCard {
                            nexus: panel.nexus
                        }

                        NexusMediaPage {
                            nexus: panel.nexus
                        }

                        NexusNotesPage {
                            id: notesPage

                            nexus: panel.nexus
                        }

                        NexusClipboardPage {
                            nexus: panel.nexus
                        }

                        NexusMinimizerPage {
                            nexus: panel.nexus
                        }

                        NexusNotificationsPage {
                            nexus: panel.nexus
                        }

                        NexusKeysPage {
                            nexus: panel.nexus
                        }

                        NexusVolumeControl {
                            nexus: panel.nexus
                        }

                        NexusControlsPage {
                            nexus: panel.nexus
                        }

                        NexusQuickActions {
                            nexus: panel.nexus
                        }

                        NexusStylePage {
                            nexus: panel.nexus
                        }

                        NexusSettingsPage {
                            nexus: panel.nexus
                        }

                        transform: Translate {
                            x: nexus.pageShift * Style.space(20)
                        }

                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: nexus.gameModeError !== "" ? nexus.gameModeError : nexus.settingsError
                        color: Color.urgent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }

                }

            }

        }

        Behavior on entrance {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }

        }

        transform: Translate {
            x: card.entrance * Style.space(24)
        }

    }

}
