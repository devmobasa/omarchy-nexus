import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Row {
    id: quickActions

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_CONTROLS
    spacing: Style.spacing.controlGap

    Button {
        iconText: ""
        text: "Capture"
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.CAPTURE && nexus.page === NexusModel.PAGE_CONTROLS
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.CAPTURE;

        }
        onClicked: nexus.openMenuRoute(NexusModel.MENU_ROUTES.capture)
    }

    Button {
        iconText: "󰐥"
        text: "Power"
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.POWER && nexus.page === NexusModel.PAGE_CONTROLS
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.POWER;

        }
        onClicked: nexus.openMenuRoute(NexusModel.MENU_ROUTES.power)
    }

}
