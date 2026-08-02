import "../model/NexusSuiteModel.js" as NexusSuiteModel
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
    id: screenTimeCard

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_OVERVIEW && nexus.settings.showScreenTime && nexus.screenTimeSummary !== null
    width: parent.width
    implicitHeight: screenTimeRow.implicitHeight + Style.spacing.rowPaddingX * 2
    radius: Style.cornerRadius
    color: nexus.softText(0.04)
    borderSpec: Border.flat(nexus.softText(0.1), 1)

    Item {
        id: screenTimeRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        implicitHeight: screenTimeLabel.implicitHeight

        Text {
            id: screenTimeLabel

            anchors.left: parent.left
            text: "󱎫 Screen time"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }

        Text {
            anchors.right: parent.right
            text: NexusSuiteModel.screenTimeLine(nexus.screenTimeSummary)
            color: Qt.darker(Color.menu.text, 1.25)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }

    }

    MouseArea {
        anchors.fill: parent
        onClicked: nexus.summonSibling("community.screen-time")
    }

}
