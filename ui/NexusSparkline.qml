import "../model/NexusMetricsModel.js" as NexusMetricsModel
import QtQuick
import QtQuick.Shapes

// Minimal trend line over a rolling history. The scale is fixed by
// `scaleMax` (percent metrics pass 100) so the same load always draws at
// the same height; fewer than two samples draw nothing.
Item {
    id: spark

    property var history: []
    property real scaleMax: NexusMetricsModel.PERCENT_SCALE_MAX
    property color lineColor: "white"
    property real lineWidth: 1.5

    function polyline() {
        var normalized = NexusMetricsModel.sparklinePoints(history, spark.width, spark.height, spark.scaleMax);
        var points = [];
        for (var i = 0; i < normalized.length; i++) points.push(Qt.point(normalized[i].x, normalized[i].y))
        return points;
    }

    visible: history.length >= 2

    Shape {
        anchors.fill: parent

        ShapePath {
            strokeWidth: spark.lineWidth
            strokeColor: spark.lineColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: spark.polyline()
            }

        }

    }

}
