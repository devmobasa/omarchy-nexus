import QtQuick
import Quickshell
import Quickshell.Hyprland
import "model/NexusModel.js" as NexusModel
import "model/NexusSettingsRows.js" as NexusSettingsRows
import qs.Commons
import "state"
import "ui"

Item {
    id: root

    // The shell injects these properties through the panel plugin contract.
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var shell: null
    property var manifest: null
    property var pluginRegistry: null
    property bool opened: false
    property string page: NexusModel.DEFAULT_PAGE
    property var targetScreen: null
    property bool closingFromHost: false
    property int controlCursor: -1
    property real pageShift: 0
    property date now: new Date()
    property string pendingActionName: ""
    property alias armedCloseAddress: minimizer.armedCloseAddress
    // Command palette: typing anywhere (or "/") opens it; entries assemble
    // from every actionable thing the panel knows about.
    property alias paletteOpen: palette.open
    property alias paletteQuery: palette.query
    property alias paletteCursor: palette.cursor
    readonly property var paletteResults: palette.results
    readonly property string pluginId: manifest && manifest.id ? manifest.id : "community.omarchy-nexus"
    readonly property real volumeStep: 0.05
    readonly property int seekStepSeconds: 5
    readonly property bool metricsActive: opened
    readonly property string focusRole: controlCursor >= 0 ? "control" : "tab"
    readonly property var pendingAction: pendingActionName === "" ? null : pendingActionName
    readonly property var
    sliderBar: QtObject {
        readonly property color foreground: Color.menu.text
        readonly property color background: Color.menu.background
        readonly property color urgent: Color.urgent
        readonly property string fontFamily: Style.font.family
        readonly property string position: "top"
        readonly property bool vertical: false
        readonly property int barSize: 26
    }

    // Public facade consumed by the panel components.
    readonly property var settings: persistence.settings
    readonly property string settingsDir: persistence.settingsDir
    readonly property string settingsError: persistence.settingsError
    readonly property bool gameModeOn: persistence.gameModeOn
    readonly property bool gameModePending: persistence.gameModePending
    readonly property string gameModeError: persistence.gameModeError
    readonly property var gameModeFlagContent: persistence.gameModeFlagContent
    readonly property var dndService: controls.dndService
    readonly property var nightlightService: controls.nightlightService
    readonly property var idleService: controls.idleService
    readonly property var audioSink: controls.audioSink
    readonly property var audioSource: controls.audioSource
    readonly property real outputVolume: controls.outputVolume
    readonly property bool outputMuted: controls.outputMuted
    readonly property bool inputMuted: controls.inputMuted
    readonly property var btAdapter: controls.btAdapter
    readonly property var keybindRows: controls.keybindRows
    readonly property var filteredKeybinds: controls.filteredKeybinds
    property alias keysQuery: controls.keysQuery
    readonly property var sensorReadings: sensors.sensorReadings
    readonly property var cavaController: cava
    readonly property bool cavaAvailable: cava.cavaAvailable
    readonly property bool cavaConfWritten: cava.cavaConfWritten
    readonly property var cavaBars: cava.cavaBars
    readonly property bool cavaRunning: cava.running
    readonly property var screenTimeSummary: suite.screenTimeSummary
    readonly property var nextEvent: suite.nextEvent
    readonly property var pomodoroSession: suite.pomodoroSession
    readonly property var notificationRows: suite.notificationRows
    readonly property int pendingNotificationCount: suite.pendingNotificationCount
    readonly property var failedUnits: alerts.failedUnits
    readonly property string unitBusy: alerts.unitBusy
    readonly property string unitError: alerts.unitError
    readonly property var clipboardRows: suite.clipboardRows
    readonly property var pinnedClipboardRows: suite.pinnedRows
    // Keyboard cursor and activation walk pins-then-history as one list.
    readonly property var clipboardAllRows: suite.pinnedRows.concat(suite.clipboardRows)
    readonly property var minimizerRows: minimizer.minimizerRows
    readonly property string copiedPreview: suite.copiedPreview
    readonly property string notesFile: suite.notesFile
    readonly property bool notesLoaded: suite.notesLoaded
    readonly property bool notesDirty: suite.notesDirty
    readonly property string notesText: suite.notesText
    readonly property var mediaSelected: media.mediaSelected
    readonly property int mediaPlayerCount: media.mediaPlayerCount
    readonly property var mediaAllPlayers: media.mediaAllPlayers
    readonly property real mediaUsableLength: media.mediaUsableLength
    property alias seekDragging: media.seekDragging
    property alias seekPreviewFraction: media.seekPreviewFraction
    readonly property var cpuValue: metrics.cpuValue
    readonly property var memValue: metrics.memValue
    readonly property var diskValue: metrics.diskValue
    readonly property double statSampledAt: metrics.statSampledAt
    readonly property var netRxRate: metrics.netRxRate
    readonly property var netTxRate: metrics.netTxRate
    readonly property var netRxHistory: metrics.netRxHistory
    readonly property var netTxHistory: metrics.netTxHistory
    readonly property var cpuHistory: metrics.cpuHistory
    readonly property var memHistory: metrics.memHistory
    readonly property var uptimeSeconds: metrics.uptimeSeconds
    readonly property string hostName: metrics.hostName
    readonly property string kernelVersion: metrics.kernelVersion
    readonly property var batteryDevice: metrics.batteryDevice
    readonly property bool batteryPresent: metrics.batteryPresent
    readonly property int batteryPercent: metrics.batteryPercent
    readonly property bool statStale: metrics.statStale
    readonly property bool diskStale: metrics.diskStale
    readonly property bool statStaleShown: metrics.statStaleShown
    readonly property bool diskStaleShown: metrics.diskStaleShown
    readonly property string workspaceLabel: {
        const parts = [];
        const workspace = Hyprland.focusedWorkspace;
        if (workspace && workspace.id !== undefined)
            parts.push("Workspace " + workspace.id);

        const monitor = Hyprland.focusedMonitor;
        if (monitor && monitor.name)
            parts.push(String(monitor.name));

        return parts.join(" · ");
    }
    readonly property var settingsRows: NexusSettingsRows.rows()
    // isEnabled() is a plain function QML cannot track, so the binding also
    // reads registryRevision — the host's own idiom for registry reactivity.
    readonly property bool wallpaperHubAvailable: {
        if (!pluginRegistry)
            return false;

        const revision = pluginRegistry.registryRevision;
        return !!pluginRegistry.installedPlugins["community.wallpaper-hub"] && pluginRegistry.isEnabled("community.wallpaper-hub") === true;
    }
    readonly property int lastCursorIndex: nav.lastCursorIndex

    function softText(alpha) {
        return Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, alpha);
    }

    function softAccent(alpha) {
        return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, alpha);
    }

    function open(payloadJson) {
        const normalized = NexusModel.normalizePayload(payloadJson, root.settings.defaultPage);
        root.page = normalized.page;
        root.targetScreen = targetScreenForOpen();
        root.now = new Date();
        root.opened = true;
        controls.refreshServices();
        media.refreshMedia();
        if (root.settings.showSensors)
            sensors.discover();

        persistence.prepareCava();
        if (root.page === NexusModel.PAGE_KEYS)
            controls.refreshBinds();

        Qt.callLater(function() {
            if (root.opened)
                panel.focusCurrentPage();

        });
    }

    function close() {
        closingFromHost = true;
        suite.saveNotes();
        opened = false;
        targetScreen = null;
        controlCursor = -1;
        pendingActionName = "";
        closePalette();
        media.resetSession();
        metrics.resetSession();
        sensors.resetSession();
        cava.resetSession();
        suite.resetTransient();
        minimizer.resetSession();
        alerts.resetSession();
        persistence.resetTransient();
        closingFromHost = false;
    }

    function requestClose() {
        if (closingFromHost)
            return ;

        if (shell && typeof shell.hide === "function")
            shell.hide(root.pluginId);
        else
            root.opened = false;
    }

    function status() {
        return JSON.stringify({
            "opened": root.opened,
            "page": root.page,
            "screen": root.targetScreen ? String(root.targetScreen.name || "") : "",
            "metricsActive": root.metricsActive,
            "pendingAction": root.pendingAction,
            "focusRole": root.focusRole
        });
    }

    function targetScreenForOpen() { return nav.targetScreenForOpen() }
    function activateControl(index) { nav.activateControl(index) }

    function dispatchControl(name, action) {
        if (!opened || pendingActionName !== "")
            return ;

        pendingActionName = name;
        action();
        pendingClearTimer.restart();
    }

    function setPage(next) {
        if (next === page || NexusModel.PAGES.indexOf(next) === -1)
            return ;

        const forward = NexusModel.adjacentPage(page, 1) === next;
        pageSlideAnimation.stop();
        pageShift = forward ? 1 : -1;
        page = next;
        pageSlideAnimation.restart();
    }

    function openMenuRoute(route) {
        const host = shell;
        requestClose();
        if (host && typeof host.summon === "function")
            host.summon("omarchy.menu", JSON.stringify({
            "menu": String(route)
        }));

    }

    function summonSibling(pluginId) {
        const host = shell;
        requestClose();
        if (host && typeof host.summon === "function")
            host.summon(String(pluginId), "{}");

    }

    function setOutputVolume(value) { controls.setOutputVolume(value) }
    function toggleOutputMute() { controls.toggleOutputMute() }
    function toggleInputMute() { controls.toggleInputMute() }
    function toggleDnd() { controls.toggleDnd() }
    function toggleNightlight() { controls.toggleNightlight() }
    function toggleStayAwake() { controls.toggleStayAwake() }
    function toggleBluetooth() { controls.toggleBluetooth() }
    function updateSetting(key, value) { persistence.updateSetting(key, value) }
    function toggleGameMode() { persistence.toggleGameMode() }
    function togglePomodoro() { suite.togglePomodoro() }
    function clearNotificationHistory() { suite.clearNotificationHistory() }
    function markAllNotificationsSeen() { alerts.markAllSeen() }
    function dismissNotificationRow(row) { alerts.dismissRow(row) }
    function notificationLiveAction(row) { return alerts.liveAction(row) }
    function invokeNotificationAction(row) { alerts.invokeAction(row) }
    function restartUnit(row) { alerts.runUnitAction("restart", row) }
    function resetFailedUnit(row) { alerts.runUnitAction("reset-failed", row) }
    function copyClipboardRow(row) { suite.copyClipboardRow(row) }
    function togglePinClipboard(row) { suite.togglePinRow(row) }
    function copyText(text, preview) { suite.copyText(text, preview) }
    function restoreMinimized(row) { minimizer.restoreRow(row) }
    function closeMinimized(row) { minimizer.closeMinimized(row) }
    function openPalette(seed) { palette.openPalette(seed) }
    function closePalette() { palette.closePalette() }
    function runPaletteEntry(entry) { palette.runEntry(entry) }
    function refreshBinds() { controls.refreshBinds() }
    function updateNotes(text) { suite.updateNotes(text) }
    function refreshMedia() { media.refreshMedia() }
    function selectPlayerByObject(player) { media.selectPlayerByObject(player) }
    function cycleMediaPlayer() { media.cycleMediaPlayer() }
    function applySeekFraction(fraction) { media.applySeekFraction(fraction) }
    function seekBy(seconds) { return media.seekBy(seconds) }
    function mediaAction(kind) { return media.mediaAction(kind) }

    onPageChanged: {
        controlCursor = -1;
        keysQuery = "";
        minimizer.disarmClose();
        suite.resetTransient();
        if (page === NexusModel.PAGE_KEYS && opened)
            controls.refreshBinds();

        if (opened)
            Qt.callLater(function() {
            if (root.opened)
                panel.focusCurrentPage();

        });

    }
    onLastCursorIndexChanged: {
        if (controlCursor > lastCursorIndex) {
            controlCursor = lastCursorIndex;
        }
    }

    Timer {
        id: pendingClearTimer

        interval: 400
        onTriggered: root.pendingActionName = ""
    }

    Timer {
        running: root.opened
        interval: 1000
        repeat: true
        onTriggered: {
            root.now = new Date();
            suite.resolvePomodoroExpiry();
        }
    }

    NumberAnimation {
        id: pageSlideAnimation

        target: root
        property: "pageShift"
        to: 0
        duration: 160
        easing.type: Easing.OutCubic
    }

    Connections {
        function onScreensChanged() {
            if (!root.opened)
                return ;

            const screens = Quickshell.screens || [];
            if (!root.targetScreen || screens.indexOf(root.targetScreen) === -1) {
                root.targetScreen = root.targetScreenForOpen();
                if (!root.targetScreen)
                    root.requestClose();

            }
        }

        target: Quickshell
    }

    NexusPersistenceState {
        id: persistence

        nexus: root
    }

    NexusControlsState {
        id: controls

        nexus: root
    }

    NexusSensorsState {
        id: sensors

        nexus: root
    }

    NexusCavaState {
        id: cava

        nexus: root
    }

    NexusSuiteState {
        id: suite

        nexus: root
    }

    NexusMinimizerState {
        id: minimizer

        nexus: root
    }

    NexusAlertsState {
        id: alerts

        nexus: root
    }

    NexusPaletteState {
        id: palette

        nexus: root
    }

    NexusNavState {
        id: nav

        nexus: root
    }

    NexusMediaState {
        id: media

        nexus: root
    }

    NexusMetricsState {
        id: metrics

        nexus: root
    }

    NexusPanel {
        id: panel

        nexus: root
    }

}
