import QtQuick
import qs.Commons
import qs.Ui

// Command palette: a query echo plus the ranked results. The key handling
// lives in the panel's key catcher; this renders state and takes clicks.
Column {
    id: palette

    required property var nexus

    visible: nexus.paletteOpen
    width: parent.width
    spacing: Style.space(4)

    Item {
        width: parent.width
        height: queryRow.implicitHeight + Style.space(8)

        Row {
            id: queryRow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - paletteHint.implicitWidth - Style.space(8)
            spacing: 0

            Text {
                text: "󰍉 " + (nexus.paletteQuery === "" ? "Type to search actions…" : nexus.paletteQuery)
                color: nexus.paletteQuery === "" ? Qt.darker(Color.menu.text, 1.4) : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: nexus.paletteQuery !== ""
                elide: Text.ElideLeft
            }

            Text {
                // Ghost completion of the top result; Tab accepts it.
                visible: nexus.paletteGhost !== ""
                text: nexus.paletteGhost
                color: Qt.darker(Color.menu.text, 1.8)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }

        }

        Text {
            id: paletteHint

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: nexus.paletteGhost !== "" ? "Tab completes · Esc closes" : "Esc closes"
            color: Qt.darker(Color.menu.text, 1.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }

    }

    Text {
        visible: nexus.paletteResults.length === 0
        width: parent.width
        text: "No matching actions."
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    Repeater {
        model: nexus.paletteResults

        CursorSurface {
            id: paletteRow

            required property var modelData
            required property int index

            width: parent.width
            implicitHeight: rowText.implicitHeight + Style.space(8)
            outline: true
            foreground: Color.menu.text
            hasCursor: nexus.paletteCursor === index

            HoverHandler {
                onHoveredChanged: {
                    if (hovered)
                        nexus.paletteCursor = paletteRow.index;

                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: nexus.runPaletteEntry(paletteRow.modelData)
            }

            Text {
                id: rowText

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                width: parent.width - rowSubtitle.implicitWidth - Style.space(28)
                text: (paletteRow.modelData.icon !== "" ? paletteRow.modelData.icon + "  " : "") + paletteRow.modelData.title
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
            }

            Text {
                id: rowSubtitle

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(10)
                text: paletteRow.modelData.subtitle
                color: Qt.darker(Color.menu.text, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }

        }

    }

}
