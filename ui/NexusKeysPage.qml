import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: keysPage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_KEYS
    width: parent.width
    spacing: Style.space(4)

    Text {
        width: parent.width
        text: nexus.keysQuery === "" ? "Type to filter " + nexus.keybindRows.length + " keybinds · Esc clears" : "Filter: " + nexus.keysQuery + "▏ (" + nexus.filteredKeybinds.length + " matches)"
        color: nexus.keysQuery === "" ? Qt.darker(Color.menu.text, 1.4) : Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideLeft
    }

    Repeater {
        model: nexus.filteredKeybinds.slice(0, 60)

        Item {
            required property var modelData

            width: parent.width
            height: Math.max(comboChip.implicitHeight, bindDesc.implicitHeight) + Style.space(4)

            Rectangle {
                id: comboChip

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: comboText.implicitWidth + Style.space(12)
                implicitHeight: comboText.implicitHeight + Style.space(4)
                height: implicitHeight
                radius: Style.cornerRadius / 2
                color: nexus.softAccent(0.14)

                Text {
                    id: comboText

                    anchors.centerIn: parent
                    text: modelData.combo
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }

            }

            Text {
                id: bindDesc

                anchors.left: comboChip.right
                anchors.right: parent.right
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.description !== "" ? modelData.description : "(no description)"
                color: modelData.description !== "" ? Color.menu.text : Qt.darker(Color.menu.text, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
            }

        }

    }

    Text {
        width: parent.width
        visible: nexus.filteredKeybinds.length > 60
        text: "+" + (nexus.filteredKeybinds.length - 60) + " more — refine the filter"
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }

}
