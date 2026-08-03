import "../model/NexusAudioModel.js" as NexusAudioModel
import "../model/NexusBrightnessModel.js" as NexusBrightnessModel
import "../model/NexusKeybindsModel.js" as NexusKeybindsModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
    id: state

    required property var nexus
    readonly property bool opened: nexus.opened
    readonly property var shell: nexus.shell
    // ---- first-party reactive services ---------------------------------------
    // Resolved at each open. These are keepLoaded services; when one is absent
    // its control shows the unavailable reason instead of an action.
    property var dndService: null
    property var nightlightService: null
    property var idleService: null
    // ---- audio (reactive PipeWire state; one action path) --------------------
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource
    readonly property real outputVolume: audioSink && audioSink.audio ? audioSink.audio.volume : 0
    readonly property bool outputMuted: audioSink && audioSink.audio ? audioSink.audio.muted === true : false
    readonly property bool inputMuted: audioSource && audioSource.audio ? audioSource.audio.muted === true : false
    // ---- bluetooth (native reactive adapter state) ---------------------------
    readonly property var btAdapter: Bluetooth.defaultAdapter
    // ---- microphone peak (native PipeWire monitor, no process) ---------------
    // The monitor opens a real capture stream, so it is gated hard: only
    // while the Controls page is visible and the mic is unmuted. Updates
    // arrive per graph quantum (~21 ms at the default 1024/48000).
    readonly property real micLevel: micPeakMonitor.enabled ? NexusAudioModel.peakToMeter(micPeakMonitor.peak) : 0
    // ---- keybind cheatsheet (plain-text hyprctl binds) -----------------------
    // The JSON form blanks the key for every code:NN bind, so the text output
    // is the source of truth. Fetched on each entry to the keys page; typing
    // filters (the key catcher feeds keysQuery), Backspace edits, Escape
    // clears the query before it closes the panel.
    property var keybindRows: []
    property string keysQuery: ""
    readonly property var filteredKeybinds: NexusKeybindsModel.filterBinds(keybindRows, keysQuery)
    // ---- brightness (focused monitor, via omarchy's own CLI) -----------------
    // Optimistic local value; NEVER re-read right after a set (it races the
    // hardware and can bounce to zero) — external changes arrive via the
    // page-gated 5 s poll. A single-slot queue coalesces slider drags so at
    // most one set process is ever in flight.
    property bool brightnessAvailable: false
    property int brightnessPercent: 0
    property string brightnessMonitor: ""
    property int pendingBrightness: -1
    readonly property bool brightnessActive: opened && nexus.page === NexusModel.PAGE_CONTROLS

    function refreshBrightness() {
        if (!brightnessStateProcess.running)
            brightnessStateProcess.running = true;

    }

    function setBrightness(value) {
        if (!brightnessAvailable || brightnessMonitor === "")
            return ;

        const percent = NexusBrightnessModel.clampBrightness(value);
        brightnessPercent = percent;
        if (brightnessSetProcess.running) {
            pendingBrightness = percent;
            return ;
        }
        const command = NexusBrightnessModel.setCommand(brightnessMonitor, percent);
        if (command.length === 0)
            return ;

        brightnessSetProcess.command = command;
        brightnessSetProcess.running = true;
    }

    function previewBrightness(value) {
        brightnessPercent = NexusBrightnessModel.clampBrightness(value);
        brightnessDebounce.restart();
    }

    function stepBrightness(delta) {
        setBrightness(brightnessPercent + delta);
    }

    onBrightnessActiveChanged: {
        if (brightnessActive)
            refreshBrightness();

    }

    function refreshServices() {
        var host = shell && typeof shell.serviceFor === "function" ? shell : null;
        dndService = host ? host.serviceFor("omarchy.notifications") : null;
        nightlightService = host ? host.serviceFor("omarchy.nightlight") : null;
        idleService = host ? host.serviceFor("omarchy.idle") : null;
    }

    function setOutputVolume(value) {
        if (audioSink && audioSink.audio)
            audioSink.audio.volume = Math.max(0, Math.min(1, Number(value) || 0));

    }

    function toggleOutputMute() {
        if (audioSink && audioSink.audio)
            audioSink.audio.muted = !audioSink.audio.muted;

    }

    function toggleInputMute() {
        if (audioSource && audioSource.audio)
            audioSource.audio.muted = !audioSource.audio.muted;

    }

    function toggleDnd() {
        if (dndService && typeof dndService.setDoNotDisturb === "function")
            dndService.setDoNotDisturb(!(dndService.doNotDisturb === true));

    }

    function toggleNightlight() {
        if (nightlightService && typeof nightlightService.toggle === "function")
            nightlightService.toggle();

    }

    function toggleStayAwake() {
        if (idleService && typeof idleService.setIdleEnabled === "function")
            idleService.setIdleEnabled(!(idleService.idleEnabled === true));

    }

    function toggleBluetooth() {
        if (btAdapter)
            btAdapter.enabled = !(btAdapter.enabled === true);

    }

    function refreshBinds() {
        if (!bindsProcess.running)
            bindsProcess.running = true;

    }

    // PipeWire node properties stay bound only while the panel is open.
    PwObjectTracker {
        objects: state.opened ? [state.audioSink, state.audioSource].filter(Boolean) : []
    }

    PwNodePeakMonitor {
        id: micPeakMonitor

        node: state.audioSource
        enabled: state.opened && state.nexus.page === NexusModel.PAGE_CONTROLS && state.audioSource !== null && !state.inputMuted
    }

    Process {
        id: bindsProcess

        command: ["hyprctl", "binds"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.keybindRows = NexusKeybindsModel.parseBindsText(text)
        }

    }

    Timer {
        running: state.brightnessActive
        interval: NexusBrightnessModel.POLL_INTERVAL_MS
        repeat: true
        onTriggered: state.refreshBrightness()
    }

    Timer {
        id: brightnessDebounce

        interval: NexusBrightnessModel.DRAG_DEBOUNCE_MS
        onTriggered: state.setBrightness(state.brightnessPercent)
    }

    Process {
        id: brightnessStateProcess

        property bool exitSeen: false

        command: NexusBrightnessModel.stateCommand()
        onStarted: exitSeen = false
        onRunningChanged: {
            if (!running && !exitSeen)
                state.brightnessAvailable = false;

        }
        onExited: exitSeen = true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const parsed = NexusBrightnessModel.parseMonitorState(text);
                state.brightnessAvailable = parsed.available;
                state.brightnessMonitor = parsed.monitor;
                if (parsed.available && !brightnessSetProcess.running && !brightnessDebounce.running)
                    state.brightnessPercent = parsed.percent;

            }
        }

    }

    Process {
        id: brightnessSetProcess

        property bool exitSeen: false

        command: ["omarchy-brightness-display", "--help"]
        onStarted: exitSeen = false
        onExited: {
            exitSeen = true;
            if (state.pendingBrightness >= 0) {
                const queued = state.pendingBrightness;
                state.pendingBrightness = -1;
                const command = NexusBrightnessModel.setCommand(state.brightnessMonitor, queued);
                if (command.length > 0) {
                    brightnessSetProcess.command = command;
                    brightnessSetProcess.running = true;
                }
            }
        }
    }

}
