import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
    id: volumeControl

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_CONTROLS
    width: parent.width
    implicitHeight: volumeRow.implicitHeight + Style.spacing.rowPaddingX * 2
    outline: true
    foreground: Color.menu.text
    hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.VOLUME

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.VOLUME;
            }
        }
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
            text: nexus.outputMuted ? "󰝟" : "󰕾"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            width: Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
            id: volumeSlider

            bar: nexus.sliderBar
            width: parent.width - Style.space(80)
            anchors.verticalCenter: parent.verticalCenter
            enabled: nexus.audioSink !== null
            value: nexus.outputVolume
            onMoved: function(v) {
                nexus.setOutputVolume(v);
            }
        }

        Text {
            text: Math.round((volumeSlider.dragging ? volumeSlider.liveValue : nexus.outputVolume) * 100) + "%"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            width: Style.space(38)
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
        }

    }

}
