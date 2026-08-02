import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: clipboardPage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_CLIPBOARD
    width: parent.width
    spacing: Style.space(4)

    Item {
        width: parent.width
        height: clipboardTitle.implicitHeight

        Text {
            id: clipboardTitle

            anchors.left: parent.left
            text: nexus.copiedPreview !== "" ? "Copied: " + nexus.copiedPreview : nexus.clipboardRows.length + " recent clips — click to copy"
            color: nexus.copiedPreview !== "" ? Color.accent : Color.menu.text
            width: parent.width - clipboardManagerButton.width - Style.space(8)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
        }

        Button {
            id: clipboardManagerButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Full manager"
            fontSize: Style.font.caption
            onClicked: nexus.summonSibling("omarchy.clipboard")
        }

    }

    Text {
        visible: nexus.clipboardRows.length === 0
        width: parent.width
        text: "Clipboard history is empty."
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    Repeater {
        model: nexus.clipboardRows

        CursorSurface {
            id: clipRow

            required property var modelData
            required property int index

            width: parent.width
            implicitHeight: clipText.implicitHeight + Style.space(8)
            outline: true
            foreground: Color.menu.text
            hasCursor: nexus.controlCursor === index && nexus.page === NexusModel.PAGE_CLIPBOARD

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        nexus.controlCursor = clipRow.index;
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: nexus.copyClipboardRow(clipRow.modelData)
            }

            Text {
                id: clipText

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                text: clipRow.modelData.preview
                color: clipRow.modelData.kind === "image" ? Qt.darker(Color.menu.text, 1.4) : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
            }

        }

    }

}
