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
    readonly property var mediaSelected: nexus.mediaSelected
    // ---- cava visualizer (behind the media card) -----------------------------
    // Raw ascii frames from cava, config fed over stdin — nothing touches
    // disk. The worker is an explicit state machine, never a declarative
    // `running` binding: a binding cannot re-fire when cava crashes on its
    // own (no dependency changed), which would leave the strip dead with
    // every gate still true. Crashes retry with bounded backoff; an owner
    // stop or a start failure never does.
    property bool cavaAvailable: true
    property string cavaState: NexusCavaModel.STATES.INACTIVE
    property bool intentionalStop: false
    property int failureCount: 0
    property int workerStartCount: 0
    property int lastExitCode: 0
    property string lastError: ""
    property var cavaBars: NexusCavaModel.silentFrame()
    readonly property bool running: cavaState === NexusCavaModel.STATES.RUNNING
    readonly property bool cavaWanted: opened && page === NexusModel.PAGE_OVERVIEW && cavaAvailable && settings.showMedia && settings.showVisualizer && mediaSelected !== null && mediaSelected.isPlaying

    function sync() {
        if (!cavaWanted) {
            stopWorker();
            return ;
        }
        if (intentionalStop || cavaProcess.running || retryTimer.running)
            return ;

        startWorker();
    }

    function startWorker() {
        cavaState = NexusCavaModel.STATES.STARTING;
        lastError = "";
        cavaProcess.startSeen = false;
        // Quickshell closes stdin permanently once stdinEnabled goes
        // false; it must be re-asserted before EVERY start or the next
        // run's `-p /dev/stdin` blocks forever on an already-closed pipe.
        cavaProcess.stdinEnabled = true;
        workerStartCount++;
        cavaProcess.running = true;
    }

    function stopWorker() {
        retryTimer.stop();
        if (cavaProcess.running) {
            intentionalStop = true;
            cavaProcess.running = false;
        } else if (cavaState !== NexusCavaModel.STATES.FAILED && cavaState !== NexusCavaModel.STATES.UNAVAILABLE) {
            cavaState = NexusCavaModel.STATES.INACTIVE;
        }
        cavaBars = NexusCavaModel.silentFrame();
    }

    function resetSession() {
        // Fresh session, fresh retry budget — but a missing binary stays
        // missing; re-probing every open is pointless process churn.
        retryTimer.stop();
        stopWorker();
        failureCount = 0;
        lastError = "";
        lastExitCode = 0;
        if (cavaState === NexusCavaModel.STATES.FAILED)
            cavaState = NexusCavaModel.STATES.INACTIVE;

    }

    onCavaWantedChanged: sync()

    Timer {
        id: retryTimer

        repeat: false
        onTriggered: state.sync()
    }

    Process {
        id: cavaProcess

        property bool startSeen: false

        command: NexusCavaModel.cavaCommand()
        stdinEnabled: true
        onStarted: {
            startSeen = true;
            state.cavaState = NexusCavaModel.STATES.RUNNING;
            // EOF (closing the write channel) is what tells cava the
            // stdin config is complete; only then does it start streaming.
            write(NexusCavaModel.buildConfig());
            stdinEnabled = false;
        }
        onRunningChanged: {
            if (!running && !startSeen) {
                // FailedToStart emits no `exited` — only runningChanged.
                state.cavaAvailable = false;
                state.cavaState = NexusCavaModel.STATES.UNAVAILABLE;
            }
            if (!running)
                state.cavaBars = NexusCavaModel.silentFrame();

        }
        onExited: function(exitCode) {
            state.lastExitCode = exitCode;
            const stoppedByOwner = state.intentionalStop;
            state.intentionalStop = false;
            if (stoppedByOwner || !state.cavaWanted) {
                state.cavaState = NexusCavaModel.STATES.INACTIVE;
                if (state.cavaWanted)
                    Qt.callLater(function() { state.sync(); });

                return ;
            }
            state.failureCount++;
            const delay = NexusCavaModel.retryDelay(state.failureCount);
            if (delay < 0) {
                state.cavaState = NexusCavaModel.STATES.FAILED;
                return ;
            }
            state.cavaState = NexusCavaModel.STATES.STARTING;
            retryTimer.interval = delay;
            retryTimer.restart();
        }

        stdout: SplitParser {
            onRead: function(line) {
                if (!state.cavaWanted || !cavaProcess.running)
                    return ;

                var frame = NexusCavaModel.parseFrame(line);
                if (frame !== null)
                    state.cavaBars = frame;

            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var trimmed = text.trim();
                if (trimmed.length > 0)
                    state.lastError = trimmed.slice(0, 512);

            }
        }

    }

}
