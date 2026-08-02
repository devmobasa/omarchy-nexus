import "../model/NexusKeybindsModel.js" as NexusKeybindsModel
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
    // ---- keybind cheatsheet (plain-text hyprctl binds) -----------------------
    // The JSON form blanks the key for every code:NN bind, so the text output
    // is the source of truth. Fetched on each entry to the keys page; typing
    // filters (the key catcher feeds keysQuery), Backspace edits, Escape
    // clears the query before it closes the panel.
    property var keybindRows: []
    property string keysQuery: ""
    readonly property var filteredKeybinds: NexusKeybindsModel.filterBinds(keybindRows, keysQuery)

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

    Process {
        id: bindsProcess

        command: ["hyprctl", "binds"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.keybindRows = NexusKeybindsModel.parseBindsText(text)
        }

    }

}
