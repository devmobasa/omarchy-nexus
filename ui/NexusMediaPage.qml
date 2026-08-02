import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: mediaPage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_MEDIA
    width: parent.width
    spacing: Style.space(4)

    Text {
        visible: nexus.mediaAllPlayers.length === 0
        width: parent.width
        text: "No active media players."
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    Repeater {
        model: nexus.mediaAllPlayers

        CursorSurface {
            id: playerRow

            required property var modelData
            required property int index
            readonly property bool isSelected: nexus.mediaSelected === modelData

            width: parent.width
            implicitHeight: playerInner.implicitHeight + Style.spacing.rowPaddingX * 2
            outline: true
            foreground: Color.menu.text
            hasCursor: nexus.controlCursor === index && nexus.page === NexusModel.PAGE_MEDIA
            current: isSelected

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        nexus.controlCursor = playerRow.index;
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: nexus.selectPlayerByObject(playerRow.modelData)
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
                        text: (playerRow.isSelected ? "● " : "") + (playerRow.modelData.identity || playerRow.modelData.dbusName || "Player")
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
                            var title = playerRow.modelData.trackTitle || "";
                            var artist = playerRow.modelData.trackArtist || "";
                            return title + (artist !== "" ? " — " + artist : "");
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
                        enabled: playerRow.modelData.isPlaying ? playerRow.modelData.canPause === true : playerRow.modelData.canPlay === true
                        onClicked: playerRow.modelData.isPlaying ? playerRow.modelData.pause() : playerRow.modelData.play()
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
