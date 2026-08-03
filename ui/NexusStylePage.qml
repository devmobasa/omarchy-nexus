import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: stylePage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_STYLE
    width: parent.width
    spacing: Style.spacing.md

    Text {
        width: parent.width
        text: "Style actions close Nexus and open the Omarchy selector."
        color: Qt.darker(Color.menu.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
    }

    Row {
        spacing: Style.spacing.controlGap

        Button {
            iconText: "󰸌"
            text: "Theme"
            hasCursor: nexus.controlCursor === NexusModel.STYLE_ROWS.THEME && nexus.page === NexusModel.PAGE_STYLE
            onHovered: function(h) {
                if (h)
                    nexus.controlCursor = NexusModel.STYLE_ROWS.THEME;

            }
            onClicked: nexus.openMenuRoute(NexusModel.MENU_ROUTES.theme)
        }

        Button {
            iconText: ""
            text: "Background"
            hasCursor: nexus.controlCursor === NexusModel.STYLE_ROWS.BACKGROUND && nexus.page === NexusModel.PAGE_STYLE
            onHovered: function(h) {
                if (h)
                    nexus.controlCursor = NexusModel.STYLE_ROWS.BACKGROUND;

            }
            onClicked: nexus.openMenuRoute(NexusModel.MENU_ROUTES.background)
        }

        Button {
            visible: nexus.wallpaperHubAvailable
            iconText: "󰸉"
            text: "Wallpaper Hub"
            hasCursor: nexus.controlCursor === NexusModel.STYLE_ROWS.WALLPAPERS && nexus.page === NexusModel.PAGE_STYLE
            onHovered: function(h) {
                if (h)
                    nexus.controlCursor = NexusModel.STYLE_ROWS.WALLPAPERS;

            }
            onClicked: nexus.summonSibling("community.wallpaper-hub")
        }

    }

}
