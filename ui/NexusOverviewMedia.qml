import "../model/NexusCavaModel.js" as NexusCavaModel
import "../model/NexusMediaModel.js" as NexusMediaModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
    id: overviewMedia

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_OVERVIEW && nexus.settings.showMedia
    width: parent.width
    implicitHeight: mediaColumn.implicitHeight + Style.spacing.rowPaddingX * 2
    radius: Style.cornerRadius
    color: nexus.softText(0.04)
    borderSpec: Border.flat(nexus.softText(0.1), 1)

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
                    text: nexus.mediaSelected ? (nexus.mediaSelected.trackTitle || nexus.mediaSelected.identity || "Unknown track") : "Nothing playing"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: nexus.mediaSelected ? (nexus.mediaSelected.trackArtist || "") : ""
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
                    enabled: nexus.mediaSelected !== null && nexus.mediaSelected.canGoPrevious
                    onHovered: function(h) {
                        if (h)
                            nexus.controlCursor = NexusModel.OVERVIEW_ROWS.TRANSPORT;

                    }
                    onClicked: nexus.mediaAction("previous")
                }

                Button {
                    iconText: nexus.mediaSelected && nexus.mediaSelected.isPlaying ? "󰏤" : "󰐊"
                    enabled: nexus.mediaSelected !== null && (nexus.mediaSelected.isPlaying ? nexus.mediaSelected.canPause : nexus.mediaSelected.canPlay)
                    hasCursor: nexus.controlCursor === NexusModel.OVERVIEW_ROWS.TRANSPORT && nexus.page === NexusModel.PAGE_OVERVIEW
                    onHovered: function(h) {
                        if (h)
                            nexus.controlCursor = NexusModel.OVERVIEW_ROWS.TRANSPORT;

                    }
                    onClicked: nexus.mediaAction("playpause")
                }

                Button {
                    iconText: "󰒭"
                    enabled: nexus.mediaSelected !== null && nexus.mediaSelected.canGoNext
                    onHovered: function(h) {
                        if (h)
                            nexus.controlCursor = NexusModel.OVERVIEW_ROWS.TRANSPORT;

                    }
                    onClicked: nexus.mediaAction("next")
                }

            }

        }

        // Seek bar: elapsed, draggable track, total. Display-only when
        // the player reports no usable length or cannot seek.
        Row {
            readonly property real barFraction: {
                if (nexus.seekDragging)
                    return nexus.seekPreviewFraction;

                if (!nexus.mediaSelected || nexus.mediaUsableLength <= 0)
                    return 0;

                var fraction = NexusMediaModel.positionFraction(nexus.mediaSelected.position, nexus.mediaUsableLength);
                return fraction === null ? 0 : fraction;
            }
            readonly property bool seekable: nexus.mediaSelected !== null && nexus.mediaSelected.canSeek && nexus.mediaSelected.positionSupported && nexus.mediaUsableLength > 0

            width: parent.width
            visible: nexus.mediaSelected !== null
            spacing: Style.space(8)

            Text {
                id: elapsedLabel

                // Reserve the total label's width so the growing elapsed
                // string cannot shift the track geometry mid-drag.
                width: totalLabel.width
                horizontalAlignment: Text.AlignLeft
                text: nexus.mediaSelected ? (nexus.mediaSelected.positionSupported ? NexusMediaModel.formatPlaybackTime(nexus.seekDragging ? nexus.seekPreviewFraction * nexus.mediaUsableLength : nexus.mediaSelected.position) : "─") : ""
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
                    color: nexus.softText(0.14)
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * parent.parent.barFraction
                    height: Style.space(3)
                    radius: height / 2
                    color: nexus.controlCursor === NexusModel.OVERVIEW_ROWS.SEEK && nexus.page === NexusModel.PAGE_OVERVIEW ? Color.accent : nexus.softAccent(0.75)
                }

                Rectangle {
                    visible: parent.parent.seekable && (seekMouse.containsMouse || nexus.seekDragging || (nexus.controlCursor === NexusModel.OVERVIEW_ROWS.SEEK && nexus.page === NexusModel.PAGE_OVERVIEW))
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
                    onEntered: nexus.controlCursor = NexusModel.OVERVIEW_ROWS.SEEK
                    onPressed: function(mouse) {
                        nexus.seekDragging = true;
                        nexus.seekPreviewFraction = Math.max(0, Math.min(1, mouse.x / width));
                    }
                    onPositionChanged: function(mouse) {
                        if (nexus.seekDragging)
                            nexus.seekPreviewFraction = Math.max(0, Math.min(1, mouse.x / width));

                    }
                    onReleased: {
                        if (!nexus.seekDragging)
                            return ;

                        nexus.seekDragging = false;
                        nexus.applySeekFraction(nexus.seekPreviewFraction);
                    }
                    onCanceled: nexus.seekDragging = false
                }

            }

            Text {
                id: totalLabel

                text: nexus.mediaUsableLength > 0 ? NexusMediaModel.formatPlaybackTime(nexus.mediaUsableLength) : "─"
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
            visible: nexus.cavaRunning
            spacing: Math.max(1, Math.floor(width / NexusCavaModel.BAR_COUNT * 0.25))

            Repeater {
                model: nexus.cavaBars

                Rectangle {
                    required property real modelData

                    width: Math.max(2, (parent.width - (NexusCavaModel.BAR_COUNT - 1) * parent.spacing) / NexusCavaModel.BAR_COUNT)
                    height: Math.max(2, parent.height * modelData)
                    y: parent.height - height
                    radius: 1
                    color: nexus.softAccent(0.45)
                }

            }

        }

        // Player switcher chip: visible only when more than one real
        // player is active; click or Enter steps the deterministic order.
        Button {
            visible: nexus.mediaPlayerCount > 1
            iconText: "󰲸"
            text: nexus.mediaSelected ? (nexus.mediaSelected.identity || nexus.mediaSelected.dbusName || "Player") : ""
            fontSize: Style.font.bodySmall
            hasCursor: nexus.controlCursor === NexusModel.OVERVIEW_ROWS.PLAYER_CHIP && nexus.page === NexusModel.PAGE_OVERVIEW
            tooltipText: "Switch player (" + nexus.mediaPlayerCount + " active)"
            onHovered: function(h) {
                if (h)
                    nexus.controlCursor = NexusModel.OVERVIEW_ROWS.PLAYER_CHIP;

            }
            onClicked: nexus.cycleMediaPlayer()
        }

    }

}
