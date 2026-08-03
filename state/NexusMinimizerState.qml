import "../model/NexusMinimizerModel.js" as NexusMinimizerModel
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
    // ---- minimizer integration ----------------------------------------------
    // Reads the hyprland-minimizer scripts' sidecar (state.json origins,
    // history.txt recency, pre-captured thumbs) and restores with the
    // scripts' own dispatch semantics. The sidecar is never written from
    // here: the scripts prune stale entries themselves on their next run.

    id: state

    required property var nexus
    property string armedCloseAddress: ""
    readonly property bool opened: nexus.opened
    readonly property string minimizerDir: NexusMinimizerModel.runtimeDir(Quickshell.env("XDG_RUNTIME_DIR"))
    property string sidecarText: ""
    property string historyText: ""
    property var minimizedWindows: []
    readonly property var minimizerRows: NexusMinimizerModel.rows(minimizedWindows, NexusMinimizerModel.parseSidecar(sidecarText), NexusMinimizerModel.parseHistory(historyText))

    function refreshWindows() {
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        const out = [];
        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i];
            if (!toplevel || !toplevel.workspace || toplevel.workspace.name !== NexusMinimizerModel.MINIMIZED_WORKSPACE)
                continue;

            const wayland = toplevel.wayland;
            const ipc = toplevel.lastIpcObject;
            out.push({
                "address": String(toplevel.address || ""),
                "title": wayland && wayland.title ? String(wayland.title) : (ipc && ipc.title ? String(ipc.title) : ""),
                "toplevel": toplevel
            });
        }
        minimizedWindows = out;
    }

    function restoreRow(row) {
        if (!row)
            return ;

        const focused = Hyprland.focusedWorkspace;
        const target = focused && focused.id > 0 ? focused.id : 1;
        const move = NexusMinimizerModel.restoreDispatch(row.address, target);
        if (move === "")
            return ;

        Hyprland.dispatch(move);
        Hyprland.dispatch(NexusMinimizerModel.focusDispatch(row.address));
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
    }

    function closeRow(row) {
        if (!row)
            return ;

        const close = NexusMinimizerModel.closeDispatch(row.address);
        if (close === "")
            return ;

        Hyprland.dispatch(close);
        Hyprland.refreshToplevels();
    }

    // Destructive row actions arm on the first activation and run on the
    // second (the Omarchy menu's confirm idiom); the arm decays on its own.
    function closeMinimized(row) {
        if (!row)
            return ;

        if (armedCloseAddress !== row.address) {
            armedCloseAddress = row.address;
            armedCloseTimer.restart();
            return ;
        }
        disarmClose();
        closeRow(row);
    }

    function disarmClose() {
        armedCloseAddress = "";
        armedCloseTimer.stop();
    }

    function resetSession() {
        minimizedWindows = [];
        sidecarText = "";
        historyText = "";
        disarmClose();
    }

    onOpenedChanged: {
        if (opened) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            refreshWindows();
        }
    }

    Connections {
        // The async refreshToplevels round trip and live window churn both
        // land here; the values snapshot recomputes on either.
        target: Hyprland.toplevels
        enabled: state.opened

        function onValuesChanged() {
            state.refreshWindows();
        }

    }

    Connections {
        // Workspace moves do not change the toplevel set, only membership.
        target: Hyprland
        enabled: state.opened

        function onRawEvent(event) {
            switch (event.name) {
            case "movewindow":
            case "movewindowv2":
            case "windowtitle":
            case "windowtitlev2":
                state.refreshWindows();
                break;
            }
        }

    }

    FileView {
        path: state.opened ? NexusMinimizerModel.sidecarPath(state.minimizerDir) : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.sidecarText = text()
        onLoadFailed: state.sidecarText = ""
        onFileChanged: reload()
    }

    FileView {
        path: state.opened ? NexusMinimizerModel.historyPath(state.minimizerDir) : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.historyText = text()
        onLoadFailed: state.historyText = ""
        onFileChanged: reload()
    }

    Timer {
        id: armedCloseTimer

        interval: 3000
        onTriggered: state.armedCloseAddress = ""
    }

}
