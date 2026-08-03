import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

// Bar editor: reorder, re-home, remove, and add bar widgets — the same
// shell.json the host owns, mutated only through its plugin registry, so
// inline widget settings survive every move.
Column {
    id: barPage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_BAR
    width: parent.width
    spacing: Style.space(4)

    Text {
        width: parent.width
        text: nexus.barEditable ? "Bar layout — changes apply instantly." : "The plugin registry is unavailable; the bar cannot be edited."
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: nexus.barRows

        CursorSurface {
            id: barRow

            required property var modelData

            width: parent.width
            implicitHeight: rowTitle.implicitHeight + Style.space(8)
            outline: true
            foreground: Color.menu.text
            hasCursor: false

            Text {
                id: rowTitle

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                width: parent.width - rowActions.width - Style.space(24)
                text: barRow.modelData.title + " · " + barRow.modelData.section + (barRow.modelData.locked ? " · pinned" : "")
                color: barRow.modelData.locked ? Qt.darker(Color.menu.text, 1.5) : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
            }

            Row {
                id: rowActions

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)
                visible: !barRow.modelData.locked

                Text {
                    text: "󰅃"
                    color: barRow.modelData.first ? nexus.softText(0.2) : Qt.darker(Color.menu.text, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(3)
                        enabled: !barRow.modelData.first
                        onClicked: nexus.moveBarRowUp(barRow.modelData)
                    }

                }

                Text {
                    text: "󰅀"
                    color: barRow.modelData.last ? nexus.softText(0.2) : Qt.darker(Color.menu.text, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(3)
                        enabled: !barRow.modelData.last
                        onClicked: nexus.moveBarRowDown(barRow.modelData)
                    }

                }

                Text {
                    text: "󰓡"
                    color: Qt.darker(Color.menu.text, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(3)
                        onClicked: nexus.moveBarRowSection(barRow.modelData)
                    }

                }

                Text {
                    text: "󰅖"
                    color: Qt.darker(Color.menu.text, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(3)
                        onClicked: nexus.removeBarRow(barRow.modelData)
                    }

                }

            }

        }

    }

    Text {
        visible: nexus.availableBarWidgets.length > 0
        width: parent.width
        topPadding: Style.space(6)
        text: "Available widgets — click to add"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
    }

    Repeater {
        model: nexus.availableBarWidgets

        CursorSurface {
            id: availableRow

            required property var modelData

            width: parent.width
            implicitHeight: availableTitle.implicitHeight + Style.space(8)
            outline: true
            foreground: Color.menu.text
            hasCursor: false

            MouseArea {
                anchors.fill: parent
                onClicked: nexus.addBarWidget(availableRow.modelData.id)
            }

            Text {
                id: availableTitle

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                width: parent.width - Style.space(20)
                text: "+ " + availableRow.modelData.title
                color: Qt.darker(Color.menu.text, 1.25)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
            }

        }

    }

    Text {
        visible: nexus.barEditError !== ""
        width: parent.width
        text: nexus.barEditError
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
    }

}
