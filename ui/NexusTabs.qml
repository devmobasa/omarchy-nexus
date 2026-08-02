import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: tabs

    required property var nexus

    width: parent.width
    height: tabRow.implicitHeight

    Row {
        id: tabRow

        spacing: Style.spacing.controlGap

        WheelHandler {
            // Touchpads deliver a stream of small deltas (and horizontal
            // scrolls report y === 0); without the guard and the notch
            // threshold one flick would spin through several pages.
            property real wheelAccum: 0

            onActiveChanged: {
                if (!active) {
                    wheelAccum = 0;
                }
            }
            onWheel: function(event) {
                if (event.angleDelta.y === 0)
                    return ;

                wheelAccum += event.angleDelta.y;
                if (Math.abs(wheelAccum) < 120)
                    return ;

                var step = wheelAccum < 0 ? 1 : -1;
                wheelAccum = 0;
                nexus.setPage(NexusModel.adjacentPage(nexus.page, step));
            }
        }

        Repeater {
            model: NexusModel.tabPages()

            Button {
                required property string modelData

                // Icon-only tabs stay uniform at any page count; the
                // title lives in the tooltip.
                iconText: NexusModel.pageIcon(modelData)
                tooltipText: NexusModel.pageTitle(modelData)
                active: nexus.page === modelData
                onClicked: nexus.setPage(modelData)
            }

        }

    }

    Button {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰒓"
        active: nexus.page === NexusModel.PAGE_SETTINGS
        tooltipText: "Nexus settings"
        onClicked: nexus.setPage(NexusModel.PAGE_SETTINGS)
    }

}
