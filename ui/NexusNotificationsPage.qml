import "../model/NexusModel.js" as NexusModel
import "../model/NexusSuiteModel.js" as NexusSuiteModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: notificationsPage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_ALERTS
    width: parent.width
    spacing: Style.space(4)

    Item {
        width: parent.width
        height: alertsTitle.implicitHeight

        Text {
            id: alertsTitle

            anchors.left: parent.left
            text: nexus.notificationRows.length + " recent notifications"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }

        Button {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: nexus.notificationRows.length > 0 && nexus.dndService !== null
            text: "Clear history"
            fontSize: Style.font.caption
            onClicked: nexus.clearNotificationHistory()
        }

    }

    Text {
        visible: nexus.notificationRows.length === 0
        width: parent.width
        text: "No recent notifications."
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    Repeater {
        model: nexus.notificationRows

        Column {
            required property var modelData

            width: parent.width
            spacing: Style.space(1)
            bottomPadding: Style.space(5)

            Item {
                width: parent.width
                height: alertApp.implicitHeight

                Text {
                    id: alertApp

                    anchors.left: parent.left
                    text: (modelData.pending ? "● " : "") + (modelData.app || "unknown")
                    color: modelData.urgency >= 2 ? Color.urgent : (modelData.pending ? Color.accent : Qt.darker(Color.menu.text, 1.25))
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }

                Text {
                    anchors.right: parent.right
                    text: NexusSuiteModel.relativeTime(modelData.timestamp, nexus.now.getTime())
                    color: Qt.darker(Color.menu.text, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }

            }

            Text {
                width: parent.width
                text: modelData.summary || "(no summary)"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: modelData.body
                color: Qt.darker(Color.menu.text, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }

        }

    }

}
