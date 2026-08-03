import "../model/NexusAlertsModel.js" as NexusAlertsModel
import "../model/NexusDiagnosticsModel.js" as NexusDiagnosticsModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell
import Quickshell.Io

// Failed systemd units for the Alerts page: both scopes listed on entry,
// restart / reset-failed on demand. System-scope actions go through plain
// systemctl and the shell's polkit agent raises the auth prompt; nothing
// here touches sudo.
Item {
    id: state

    required property var nexus
    readonly property bool active: nexus.opened && nexus.page === NexusModel.PAGE_ALERTS
    property var systemFailed: []
    property var userFailed: []
    readonly property var failedUnits: systemFailed.concat(userFailed)
    // Single-flight: one unit action at a time, keyed for the row spinner.
    property string unitBusy: ""
    property string unitError: ""
    // Shell-log self-diagnostics: QML errors since the last config load,
    // read from this instance's own mirrored log file.
    property var logIssues: []
    readonly property string ownLogPath: NexusDiagnosticsModel.logPath(Quickshell.env("XDG_RUNTIME_DIR"), Quickshell.instanceId)

    function refreshFailed() {
        if (!systemProcess.running)
            systemProcess.running = true;

        if (!userProcess.running)
            userProcess.running = true;

        const command = NexusDiagnosticsModel.tailCommand(ownLogPath);
        if (command.length > 0 && !logProcess.running) {
            logProcess.command = command;
            logProcess.running = true;
        }
    }

    function runUnitAction(verb, row) {
        if (unitBusy !== "" || !row)
            return ;

        const command = NexusAlertsModel.unitCommand(verb, row.scope, row.unit);
        if (command.length === 0)
            return ;

        unitBusy = row.scope + ":" + row.unit;
        unitError = "";
        actionProcess.command = command;
        actionProcess.running = true;
    }

    function resetSession() {
        systemFailed = [];
        userFailed = [];
        unitBusy = "";
        unitError = "";
        logIssues = [];
    }

    // ---- notification row actions (through the live service) -----------------
    function markAllSeen() {
        const svc = nexus.dndService;
        if (svc && typeof svc.markAllSeen === "function")
            svc.markAllSeen();

    }

    function dismissRow(row) {
        const svc = nexus.dndService;
        if (!row || !svc || typeof svc.removeByOriginalId !== "function")
            return ;

        svc.removeByOriginalId(row.pending ? svc.pendingModel : svc.pastModel, row.originalId);
        if (typeof svc.scheduleHistorySave === "function")
            svc.scheduleHistorySave();

    }

    // liveRefs is mutated in place and never signals, so it is read at
    // click time, never bound. The "default" action is the row-click
    // convention on every notification daemon; fall back to the first.
    function liveAction(row) {
        const svc = nexus.dndService;
        if (!row || !svc || !svc.liveRefs)
            return null;

        const live = svc.liveRefs[row.originalId];
        if (!live || !live.actions || live.actions.length === 0)
            return null;

        for (let i = 0; i < live.actions.length; i++) {
            if (live.actions[i].identifier === "default")
                return live.actions[i];

        }
        return live.actions[0];
    }

    function invokeAction(row) {
        const action = liveAction(row);
        if (!action)
            return ;

        action.invoke();
        nexus.requestClose();
    }

    onActiveChanged: {
        if (active)
            refreshFailed();

    }

    Process {
        id: systemProcess

        property bool exitSeen: false

        command: NexusAlertsModel.failedCommand(NexusAlertsModel.SCOPE_SYSTEM)
        onStarted: exitSeen = false
        onExited: exitSeen = true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.systemFailed = NexusAlertsModel.parseFailedUnits(text, NexusAlertsModel.SCOPE_SYSTEM)
        }

    }

    Process {
        id: userProcess

        property bool exitSeen: false

        command: NexusAlertsModel.failedCommand(NexusAlertsModel.SCOPE_USER)
        onStarted: exitSeen = false
        onExited: exitSeen = true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.userFailed = NexusAlertsModel.parseFailedUnits(text, NexusAlertsModel.SCOPE_USER)
        }

    }

    Process {
        id: logProcess

        property bool exitSeen: false

        command: ["tail", "--version"]
        onStarted: exitSeen = false
        onExited: exitSeen = true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.logIssues = NexusDiagnosticsModel.scanLog(text)
        }

    }

    Process {
        id: actionProcess

        property bool exitSeen: false

        command: ["systemctl", "--version"]
        onStarted: exitSeen = false
        onExited: function(exitCode) {
            exitSeen = true;
            state.unitBusy = "";
            if (exitCode !== 0 && state.unitError === "")
                state.unitError = "systemctl exited " + exitCode;

            state.refreshFailed();
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text.trim().length > 0)
                    state.unitError = text.trim();

            }
        }

    }

}
