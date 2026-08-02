import "../model/NexusGameModeModel.js" as NexusGameModeModel
import "../model/NexusModel.js" as NexusModel
import "../model/NexusSettingsModel.js" as NexusSettingsModel
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: state

    required property var nexus
    readonly property bool opened: nexus.opened
    readonly property var shell: nexus.shell
    readonly property string pluginId: nexus.pluginId
    // ---- validated settings ---------------------------------------------------
    // Two layers: the read-only shell.json entry, overridden by the Settings
    // page's state file. Nexus never writes shell.json.
    property var stateOverrides: ({
    })
    readonly property var settings: NexusSettingsModel.applyState(NexusSettingsModel.readSettings(shell && shell.shellConfig ? shell.shellConfig.plugins : null, state.pluginId, NexusModel.PAGES), stateOverrides)
    readonly property string settingsDir: NexusSettingsModel.stateDir(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    readonly property string settingsFile: NexusSettingsModel.statePath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    property string settingsError: ""
    // ---- game mode (flag file shared with community.game-mode) ---------------
    // Presence of the flag in Omarchy's sourced toggles directory is the whole
    // state; removing it restores the user's exact config. The strip set comes
    // from the gm* settings, so the Settings page decides what game mode does.
    readonly property string gameModeDir: NexusGameModeModel.stateDir(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    readonly property string gameModeFile: NexusGameModeModel.flagPath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    readonly property var gameModeFlagContent: NexusGameModeModel.buildFlagContent(settings)
    property bool gameModeOn: false
    property bool gameModePending: false
    property string gameModeError: ""

    function updateSetting(key, value) {
        var next = {
        };
        for (var existing in stateOverrides) next[existing] = stateOverrides[existing]
        next[key] = value === true;
        stateOverrides = next;
        ensureDirsProcess.writeStateAfter = true;
        runProcess(ensureDirsProcess);
    }

    function syncGameMode() {
        gameModeProbe.reload();
        // The writer's write-compare cache must track disk (setText de-dupes).
        flagWriter.reload();
    }

    // Quickshell emits no `exited` when a binary cannot be started, only
    // runningChanged — an exit that was never seen is a start failure.
    function runProcess(proc) {
        proc.exitSeen = false;
        proc.running = true;
    }

    function toggleGameMode() {
        if (gameModePending || !opened)
            return ;

        gameModeError = "";
        if (gameModeOn) {
            gameModePending = true;
            runProcess(removeFlagProcess);
        } else {
            if (gameModeFlagContent === null) {
                gameModeError = "Nothing selected to strip — pick effects in Settings.";
                return ;
            }
            gameModePending = true;
            ensureDirsProcess.writeFlagAfter = true;
            runProcess(ensureDirsProcess);
        }
    }

    function finishGameMode(ok, message) {
        gameModePending = false;
        gameModeError = ok ? "" : message;
        syncGameMode();
    }

    function prepareCava() {
        if (nexus.cavaConfWritten || !nexus.cavaAvailable || !settings.showVisualizer)
            return ;

        ensureDirsProcess.writeCavaAfter = true;
        runProcess(ensureDirsProcess);
    }

    function resetTransient() {
        gameModePending = false;
        gameModeError = "";
        settingsError = "";
    }

    FileView {
        path: state.opened ? state.settingsFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.stateOverrides = NexusSettingsModel.parseState(text())
        onFileChanged: reload()
    }

    FileView {
        id: stateWriter

        path: state.settingsFile
        printErrors: false
        atomicWrites: true
        // Re-read after every save so the write-compare cache tracks disk
        // (setText silently no-ops on identical cached content).
        onSaved: {
            state.settingsError = "";
            reload();
        }
        onSaveFailed: state.settingsError = "Could not write the settings file"
    }

    FileView {
        id: gameModeProbe

        path: state.opened ? state.gameModeFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.gameModeOn = true
        onLoadFailed: state.gameModeOn = false
        onFileChanged: state.syncGameMode()
    }

    // One idempotent dir-ensure serves both writers (game-mode flag and the
    // settings state file); fixed argument array, fired only on user action.
    Process {
        id: ensureDirsProcess

        property bool exitSeen: false
        property bool writeFlagAfter: false
        property bool writeStateAfter: false
        property bool writeCavaAfter: false

        command: ["mkdir", "-p", state.gameModeDir, state.settingsDir]
        onRunningChanged: {
            if (!running && !exitSeen) {
                if (writeFlagAfter)
                    state.finishGameMode(false, "mkdir could not be started");

                if (writeStateAfter)
                    state.settingsError = "mkdir could not be started";

                writeFlagAfter = false;
                writeStateAfter = false;
                writeCavaAfter = false;
            }
        }
        onExited: function(exitCode) {
            exitSeen = true;
            var flagWanted = writeFlagAfter;
            var stateWanted = writeStateAfter;
            var cavaWanted = writeCavaAfter;
            writeFlagAfter = false;
            writeStateAfter = false;
            writeCavaAfter = false;
            if (exitCode !== 0) {
                if (flagWanted)
                    state.finishGameMode(false, "could not create the state directories");

                if (stateWanted)
                    state.settingsError = "Could not create the state directories";

                return ;
            }
            if (flagWanted)
                flagWriter.setText(state.gameModeFlagContent);

            if (stateWanted)
                stateWriter.setText(NexusSettingsModel.buildStateJson(state.stateOverrides));

            if (cavaWanted)
                nexus.cavaController.writeConfig();

        }
    }

    FileView {
        id: flagWriter

        path: state.gameModeFile
        printErrors: false
        atomicWrites: true
        onSaved: state.runProcess(hyprReloadProcess)
        onSaveFailed: state.finishGameMode(false, "could not write the flag file")
    }

    Process {
        id: removeFlagProcess

        property bool exitSeen: false

        command: ["rm", "-f", state.gameModeFile]
        onRunningChanged: {
            if (!running && !exitSeen) {
                state.finishGameMode(false, "rm could not be started");
            }
        }
        onExited: function(exitCode) {
            exitSeen = true;
            if (exitCode === 0)
                state.runProcess(hyprReloadProcess);
            else
                state.finishGameMode(false, "could not remove the flag file");
        }
    }

    Process {
        id: hyprReloadProcess

        property bool exitSeen: false

        command: ["hyprctl", "reload"]
        onRunningChanged: {
            if (!running && !exitSeen) {
                state.finishGameMode(false, "hyprctl could not be started");
            }
        }
        onExited: function(exitCode) {
            exitSeen = true;
            state.finishGameMode(exitCode === 0, "hyprctl reload failed");
        }
    }

}
