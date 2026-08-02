import "../model/NexusModel.js" as NexusModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: notesPage

    required property var nexus

    function focusEditor() {
        notesEditor.forceActiveFocus();
    }

    function syncText() {
        if (notesEditor.text !== nexus.notesText)
            notesEditor.text = nexus.notesText;

    }

    Component.onCompleted: syncText()
    visible: nexus.page === NexusModel.PAGE_NOTES
    width: parent.width
    spacing: Style.space(4)

    Connections {
        function onNotesTextChanged() {
            notesPage.syncText();
        }

        target: nexus
    }

    BorderSurface {
        width: parent.width
        implicitHeight: Math.max(Style.space(220), notesEditor.implicitHeight + Style.space(20))
        radius: Style.cornerRadius
        color: nexus.softText(0.04)
        borderSpec: Border.flat(nexus.softText(0.1), 1)

        TextEdit {
            id: notesEditor

            anchors.fill: parent
            anchors.margins: Style.space(10)
            wrapMode: TextEdit.Wrap
            color: Color.menu.text
            selectionColor: Color.accent
            selectedTextColor: Color.menu.background
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            onTextChanged: nexus.updateNotes(text)
            Keys.onEscapePressed: nexus.requestClose()
        }

    }

    Text {
        width: parent.width
        text: (nexus.notesDirty ? "Saving…" : "Saved") + " · " + notesEditor.text.length + " characters · markdown at " + nexus.notesFile.replace(/^.*omarchy\//, "…/omarchy/")
        color: Qt.darker(Color.menu.text, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
    }

}
