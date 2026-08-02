import "../model/NexusMinimizerModel.js" as NexusMinimizerModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Column {
    id: minimizerPage

    required property var nexus
    // The hovered/keyboard row drives the preview pane below the list.
    readonly property var previewRow: nexus.page === NexusModel.PAGE_MINIMIZER && nexus.controlCursor >= 0 && nexus.controlCursor < nexus.minimizerRows.length ? nexus.minimizerRows[nexus.controlCursor] : null

    visible: nexus.page === NexusModel.PAGE_MINIMIZER
    width: parent.width
    spacing: Style.space(4)

    Item {
        width: parent.width
        height: minimizerTitle.implicitHeight

        Text {
            id: minimizerTitle

            anchors.left: parent.left
            width: parent.width - (restoreLastButton.visible ? restoreLastButton.width + Style.space(8) : 0)
            text: nexus.minimizerRows.length === 0 ? "Minimized windows" : nexus.minimizerRows.length + " minimized — click to restore here"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
        }

        Button {
            id: restoreLastButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: nexus.minimizerRows.length > 0
            text: "Restore last"
            fontSize: Style.font.caption
            onClicked: nexus.restoreMinimized(nexus.minimizerRows[0])
        }

    }

    Text {
        visible: nexus.minimizerRows.length === 0
        width: parent.width
        text: "Nothing stashed. Super+M minimizes the focused window."
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }

    Repeater {
        model: nexus.minimizerRows

        CursorSurface {
            id: minimizedRow

            required property var modelData
            required property int index

            width: parent.width
            implicitHeight: rowTitle.implicitHeight + Style.space(8)
            outline: true
            foreground: Color.menu.text
            hasCursor: nexus.controlCursor === index && nexus.page === NexusModel.PAGE_MINIMIZER

            HoverHandler {
                onHoveredChanged: {
                    if (hovered)
                        nexus.controlCursor = minimizedRow.index;

                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: nexus.restoreMinimized(minimizedRow.modelData)
            }

            Text {
                id: rowTitle

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                width: parent.width - rowOrigin.implicitWidth - Style.space(28)
                text: minimizedRow.modelData.title
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
            }

            Text {
                id: rowOrigin

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(10)
                text: minimizedRow.modelData.origin
                color: Qt.darker(Color.menu.text, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }

        }

    }

    Rectangle {
        id: previewPane

        readonly property bool showThumb: minimizerPage.previewRow !== null && minimizerPage.previewRow.thumb !== "" && thumbImage.status !== Image.Error
        readonly property var liveSource: minimizerPage.previewRow !== null && !showThumb && minimizerPage.previewRow.toplevel ? minimizerPage.previewRow.toplevel.wayland : null

        visible: minimizerPage.previewRow !== null
        width: parent.width
        height: visible ? Math.round(width * 9 / 16) : 0
        radius: Style.cornerRadius
        color: Qt.darker(Color.menu.background, 1.15)
        border.color: nexus.softText(0.15)
        border.width: 1
        clip: true

        Image {
            id: thumbImage

            anchors.fill: parent
            anchors.margins: 1
            visible: previewPane.showThumb
            source: minimizerPage.previewRow !== null ? NexusMinimizerModel.thumbUrl(minimizerPage.previewRow.thumb) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
        }

        ScreencopyView {
            // Fallback for windows the scripts never saw: the toplevel
            // export protocol re-renders hidden windows on demand.
            id: livePreview

            anchors.fill: parent
            anchors.margins: 1
            visible: previewPane.liveSource !== null
            captureSource: previewPane.liveSource
            live: false
        }

        Text {
            anchors.centerIn: parent
            visible: !previewPane.showThumb && (previewPane.liveSource === null || !livePreview.hasContent)
            text: "No preview available"
            color: Qt.darker(Color.menu.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }

    }

}
