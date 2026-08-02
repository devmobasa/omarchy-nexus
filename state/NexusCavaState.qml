import "../model/NexusCavaModel.js" as NexusCavaModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell.Io

Item {
    id: state

    required property var nexus
    readonly property bool opened: nexus.opened
    readonly property string page: nexus.page
    readonly property var settings: nexus.settings
    readonly property string settingsDir: nexus.settingsDir
    readonly property var mediaSelected: nexus.mediaSelected
    readonly property bool running: cavaProcess.running
    // ---- cava visualizer (behind the media card) -----------------------------
    // Raw ascii frames from cava, one line per frame, parsed through the
    // model. Runs only while the panel is open on Overview with media playing;
    // a start failure (cava not installed) hides the strip for the session.
    property bool cavaAvailable: true
    property bool cavaConfWritten: false
    property var cavaBars: NexusCavaModel.silentFrame()
    readonly property string cavaConfFile: NexusCavaModel.confPath(settingsDir)

    function writeConfig() {
        cavaConfWriter.setText(NexusCavaModel.buildConfig());
    }

    function resetSession() {
        cavaBars = NexusCavaModel.silentFrame();
    }

    FileView {
        id: cavaConfWriter

        path: state.cavaConfFile
        printErrors: false
        atomicWrites: true
        onSaved: {
            state.cavaConfWritten = true;
            reload();
        }
    }

    Process {
        id: cavaProcess

        property bool exitSeen: false

        running: state.opened && state.page === NexusModel.PAGE_OVERVIEW && state.cavaConfWritten && state.cavaAvailable && state.settings.showMedia && state.settings.showVisualizer && state.mediaSelected !== null && state.mediaSelected.isPlaying
        command: NexusCavaModel.cavaCommand(state.cavaConfFile)
        onStarted: exitSeen = true
        onRunningChanged: {
            if (!running && !exitSeen)
                state.cavaAvailable = false;

            if (!running)
                state.cavaBars = NexusCavaModel.silentFrame();

            if (running)
                exitSeen = false;

        }

        stdout: SplitParser {
            onRead: function(line) {
                var frame = NexusCavaModel.parseFrame(line);
                if (frame !== null)
                    state.cavaBars = frame;

            }
        }

    }

}
