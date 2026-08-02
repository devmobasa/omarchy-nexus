import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
    id: sensorsCard

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_OVERVIEW && nexus.settings.showMetrics && nexus.settings.showSensors && nexus.sensorReadings.length > 0
    width: parent.width
    implicitHeight: sensorsColumn.implicitHeight + Style.spacing.rowPaddingX * 2
    radius: Style.cornerRadius
    color: nexus.softText(0.04)
    borderSpec: Border.flat(nexus.softText(0.1), 1)

    Column {
        id: sensorsColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(3)

        Text {
            text: "Sensors"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }

        Repeater {
            model: nexus.sensorReadings

            Item {
                required property var modelData

                width: parent.width
                height: sensorLabel.implicitHeight

                Text {
                    id: sensorLabel

                    anchors.left: parent.left
                    text: modelData.label
                    color: Qt.darker(Color.menu.text, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }

                Text {
                    anchors.right: parent.right
                    text: modelData.value
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }

            }

        }

    }

}
