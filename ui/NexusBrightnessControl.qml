import "../model/NexusBrightnessModel.js" as NexusBrightnessModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

// Brightness of the focused monitor (DDC or backlight, via omarchy's own
// CLI). Drags preview optimistically and debounce into one coalesced set;
// hidden entirely when the display cannot be controlled.
CursorSurface {
    id: brightnessControl

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_CONTROLS && nexus.brightnessAvailable
    width: parent.width
    implicitHeight: brightnessRow.implicitHeight + Style.spacing.rowPaddingX * 2
    outline: true
    foreground: Color.menu.text

    Row {
        id: brightnessRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(10)

        Text {
            text: "󰃟"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            width: Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
            id: brightnessSlider

            bar: nexus.sliderBar
            width: parent.width - Style.space(80)
            anchors.verticalCenter: parent.verticalCenter
            value: nexus.brightnessPercent / 100
            onMoved: function(v) {
                nexus.previewBrightness(Math.round(v * 100));
            }
        }

        Text {
            text: (brightnessSlider.dragging ? Math.round(brightnessSlider.liveValue * 100) : nexus.brightnessPercent) + "%"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            width: Style.space(38)
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
        }

    }

}
