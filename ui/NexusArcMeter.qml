import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
    id: meter

    required property var nexus
    property string label: ""
    property var percent: null
    property bool stale: false
    property string detail: ""
    readonly property color trackColor: nexus.softText(0.12)
    readonly property color valueColor: stale || percent === null ? Qt.darker(Color.menu.text, 1.6) : Color.accent

    id: meter

    implicitHeight: meterColumn.implicitHeight

    Column {
        id: meterColumn

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(4)

        Item {
            width: Style.space(64)
            height: Style.space(64)
            anchors.horizontalCenter: parent.horizontalCenter

            Shape {
                id: arcShape

                anchors.fill: parent

                ShapePath {
                    strokeWidth: Style.space(5)
                    strokeColor: meter.trackColor
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: arcShape.width / 2
                        centerY: arcShape.height / 2
                        radiusX: arcShape.width / 2 - Style.space(4)
                        radiusY: arcShape.height / 2 - Style.space(4)
                        startAngle: 135
                        sweepAngle: 270
                    }

                }

                ShapePath {
                    strokeWidth: Style.space(5)
                    strokeColor: meter.valueColor
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: arcShape.width / 2
                        centerY: arcShape.height / 2
                        radiusX: arcShape.width / 2 - Style.space(4)
                        radiusY: arcShape.height / 2 - Style.space(4)
                        startAngle: 135
                        sweepAngle: meter.percent === null ? 0 : 270 * Math.min(100, Math.max(0, meter.percent)) / 100
                    }

                }

            }

            Text {
                anchors.centerIn: parent
                text: meter.percent === null ? "—" : meter.percent + "%"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
            }

        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: meter.label
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: meter.detail
            color: Qt.darker(Color.menu.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
        }

    }

}
