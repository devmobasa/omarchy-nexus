import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: settingsPage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_SETTINGS
    width: parent.width
    spacing: Style.space(4)

    Text {
        width: parent.width
        text: "Overview cards"
        color: Qt.darker(Color.menu.text, 1.3)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
    }

    Repeater {
        model: nexus.settingsRows.filter(function(row) {
            return row.section !== "game";
        })

        Toggle {
            required property var modelData
            required property int index

            width: parent.width
            label: modelData.label
            description: modelData.desc
            checked: nexus.settings[modelData.key] === true
            foreground: Color.menu.text
            accent: Color.accent
            fontFamily: Style.font.family
            hasCursor: nexus.controlCursor === index && nexus.page === NexusModel.PAGE_SETTINGS
            onHovered: function(h) {
                if (h)
                    nexus.controlCursor = index;

            }
            onClicked: {
                nexus.controlCursor = index;
                nexus.updateSetting(modelData.key, nexus.settings[modelData.key] !== true);
            }
        }

    }

    Text {
        width: parent.width
        topPadding: Style.space(8)
        text: "Game mode strips"
        color: Qt.darker(Color.menu.text, 1.3)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
    }

    // Presets batch-set the six toggles below; "custom" is whatever
    // the individual switches say.
    Row {
        spacing: Style.spacing.controlGap

        Repeater {
            model: NexusSuiteModel.GAME_MODE_PRESETS

            Button {
                required property var modelData

                text: modelData.label
                active: NexusSuiteModel.activePreset(nexus.settings) === modelData.key
                fontSize: Style.font.caption
                onClicked: {
                    for (var key in modelData.settings) nexus.updateSetting(key, modelData.settings[key])
                }
            }

        }

    }

    Repeater {
        id: gameRowsRepeater

        readonly property int indexOffset: nexus.settingsRows.length - count

        model: nexus.settingsRows.filter(function(row) {
            return row.section === "game";
        })

        Toggle {
            required property var modelData
            required property int index
            readonly property int cursorIndex: gameRowsRepeater.indexOffset + index

            width: parent.width
            label: modelData.label
            description: modelData.desc
            checked: nexus.settings[modelData.key] === true
            foreground: Color.menu.text
            accent: Color.accent
            fontFamily: Style.font.family
            hasCursor: nexus.controlCursor === cursorIndex && nexus.page === NexusModel.PAGE_SETTINGS
            onHovered: function(h) {
                if (h)
                    nexus.controlCursor = cursorIndex;

            }
            onClicked: {
                nexus.controlCursor = cursorIndex;
                nexus.updateSetting(modelData.key, nexus.settings[modelData.key] !== true);
            }
        }

    }

    Text {
        width: parent.width
        visible: nexus.settingsError !== ""
        text: nexus.settingsError
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
    }

    Text {
        width: parent.width
        text: "Changes save to the Nexus state file immediately; the shell.json entry still works for scripted overrides."
        color: Qt.darker(Color.menu.text, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
    }

}
