import "../model/NexusMetricsModel.js" as NexusMetricsModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

BorderSurface {
    id: netCard

    required property var nexus
    readonly property bool netStale: NexusMetricsModel.isStale(nexus.statSampledAt, nexus.now.getTime(), NexusMetricsModel.CPU_MEM_INTERVAL_MS)
    readonly property real netSharedMax: Math.max(NexusMetricsModel.historyMax(nexus.netRxHistory, nexus.netTxHistory), NexusMetricsModel.NET_SCALE_FLOOR)

    function polylineFor(history, w, h) {
        var normalized = NexusMetricsModel.sparklinePoints(history, w, h, netSharedMax);
        var points = [];
        for (var i = 0; i < normalized.length; i++) points.push(Qt.point(normalized[i].x, normalized[i].y))
        return points;
    }

    visible: nexus.page === NexusModel.PAGE_OVERVIEW && nexus.settings.showMetrics && nexus.settings.showNetwork
    width: parent.width
    implicitHeight: netColumn.implicitHeight + Style.spacing.rowPaddingX * 2
    radius: Style.cornerRadius
    color: nexus.softText(0.04)
    borderSpec: Border.flat(nexus.softText(0.1), 1)

    Column {
        id: netColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(6)

        Item {
            width: parent.width
            height: netTitle.implicitHeight

            Text {
                id: netTitle

                anchors.left: parent.left
                text: "Network"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
            }

            Row {
                anchors.right: parent.right
                spacing: Style.space(10)

                Text {
                    text: "󰇚 " + (netCard.netStale ? "—" : NexusMetricsModel.formatRate(nexus.netRxRate))
                    color: netCard.netStale ? Qt.darker(Color.menu.text, 1.6) : Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }

                Text {
                    text: "󰕒 " + (netCard.netStale ? "—" : NexusMetricsModel.formatRate(nexus.netTxRate))
                    color: Qt.darker(Color.menu.text, netCard.netStale ? 1.6 : 1.2)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }

            }

        }

        Item {
            id: netSparkline

            width: parent.width
            height: Style.space(48)

            Text {
                anchors.centerIn: parent
                visible: nexus.netRxHistory.length < 2
                text: "Sampling…"
                color: Qt.darker(Color.menu.text, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }

            Shape {
                anchors.fill: parent
                visible: nexus.netRxHistory.length >= 2

                ShapePath {
                    strokeWidth: 2
                    strokeColor: Qt.darker(Color.menu.text, 1.35)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathPolyline {
                        path: netCard.polylineFor(nexus.netTxHistory, netSparkline.width, netSparkline.height)
                    }

                }

                ShapePath {
                    strokeWidth: 2
                    strokeColor: Color.accent
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathPolyline {
                        path: netCard.polylineFor(nexus.netRxHistory, netSparkline.width, netSparkline.height)
                    }

                }

            }

        }

    }

}
