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

    // ---- failed systemd units -----------------------------------------------
    Text {
        visible: nexus.failedUnits.length > 0
        width: parent.width
        text: nexus.failedUnits.length + " failed " + (nexus.failedUnits.length === 1 ? "unit" : "units")
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
    }

    Repeater {
        model: nexus.failedUnits

        Item {
            id: unitRow

            required property var modelData

            readonly property bool busy: nexus.unitBusy === modelData.scope + ":" + modelData.unit

            width: parent.width
            height: unitName.implicitHeight + Style.space(6)

            Text {
                id: unitName

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - unitActions.width - Style.space(8)
                text: unitRow.modelData.display + " · " + unitRow.modelData.scope + (unitRow.modelData.description !== "" ? " — " + unitRow.modelData.description : "")
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
            }

            Row {
                id: unitActions

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Button {
                    text: unitRow.busy ? "…" : "Restart"
                    fontSize: Style.font.caption
                    onClicked: nexus.restartUnit(unitRow.modelData)
                }

                Button {
                    text: "Reset"
                    fontSize: Style.font.caption
                    onClicked: nexus.resetFailedUnit(unitRow.modelData)
                }

            }

        }

    }

    Text {
        visible: nexus.unitError !== ""
        width: parent.width
        text: nexus.unitError
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
    }

    // ---- notification history -----------------------------------------------
    Item {
        width: parent.width
        height: alertsTitle.implicitHeight

        Text {
            id: alertsTitle

            anchors.left: parent.left
            width: parent.width - alertsButtons.width - Style.space(8)
            text: nexus.notificationRows.length + " recent notifications"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
        }

        Row {
            id: alertsButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
                visible: nexus.pendingNotificationCount > 0 && nexus.dndService !== null
                text: "Mark seen"
                fontSize: Style.font.caption
                onClicked: nexus.markAllNotificationsSeen()
            }

            Button {
                visible: nexus.notificationRows.length > 0 && nexus.dndService !== null
                text: "Clear history"
                fontSize: Style.font.caption
                onClicked: nexus.clearNotificationHistory()
            }

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
            id: alertRow

            required property var modelData

            // Live actions only exist while the sender is still connected;
            // evaluated when the row builds (rows rebuild on every file
            // change), never bound — liveRefs mutates without signals.
            readonly property bool actionable: nexus.notificationLiveAction(modelData) !== null

            width: parent.width
            spacing: Style.space(1)
            bottomPadding: Style.space(5)

            Item {
                width: parent.width
                height: alertApp.implicitHeight

                Text {
                    id: alertApp

                    anchors.left: parent.left
                    text: (alertRow.modelData.pending ? "● " : "") + (alertRow.modelData.app || "unknown")
                    color: alertRow.modelData.urgency >= 2 ? Color.urgent : (alertRow.modelData.pending ? Color.accent : Qt.darker(Color.menu.text, 1.25))
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }

                Row {
                    anchors.right: parent.right
                    spacing: Style.space(8)

                    Text {
                        visible: alertRow.actionable
                        text: "open"
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Style.space(3)
                            onClicked: nexus.invokeNotificationAction(alertRow.modelData)
                        }

                    }

                    Text {
                        text: NexusSuiteModel.relativeTime(alertRow.modelData.timestamp, nexus.now.getTime())
                        color: Qt.darker(Color.menu.text, 1.5)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    Text {
                        text: "󰅖"
                        color: Qt.darker(Color.menu.text, 1.6)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Style.space(3)
                            onClicked: nexus.dismissNotificationRow(alertRow.modelData)
                        }

                    }

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
