import "../model/NexusAgendaModel.js" as NexusAgendaModel
import "../model/NexusPomodoroModel.js" as NexusPomodoroModel
import "../model/NexusSuiteModel.js" as NexusSuiteModel
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    // ---- suite integrations --------------------------------------------------
    // Read-only views over the state files sibling plugins maintain. Every
    // reader is opened-gated and watch-driven; absent files just hide their
    // card. No subprocesses anywhere in this section.

    id: state

    required property var nexus
    readonly property bool opened: nexus.opened
    readonly property var settings: nexus.settings
    readonly property date now: nexus.now
    readonly property var dndService: nexus.dndService
    // Screen time (community.screen-time day files).
    readonly property string screenTimeFile: NexusSuiteModel.screenTimeDayPath(NexusSuiteModel.screenTimeDir(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME")), NexusSuiteModel.dayKey(now.getTime()))
    property string screenTimeText: ""
    readonly property var screenTimeSummary: NexusSuiteModel.screenTimeSummary(screenTimeText, NexusSuiteModel.dayKey(now.getTime()))
    // Calendar (community.calendar-agenda ICS caches).
    readonly property string calendarCacheDir: NexusAgendaModel.stateDir(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    property var calendarTexts: []
    readonly property var nextEvent: NexusAgendaModel.upcoming(NexusAgendaModel.mergeAgendas(calendarTexts, 7, now.getTime()), now.getTime())
    // Pomodoro (shared state file with community.pomodoro). Nexus reads and
    // starts/pauses sessions; expiry is resolved here too while open, which
    // is benign alongside the bar widget (identical resolved content).
    readonly property string pomodoroFile: NexusPomodoroModel.statePath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    readonly property var pomodoroConfig: NexusPomodoroModel.readConfig({
    })
    property var pomodoroSession: NexusPomodoroModel.idleState()
    // Notification history (the omarchy.notifications state file; clearing
    // goes through the already-resolved service).
    readonly property string notificationsFile: NexusSuiteModel.notificationsPath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    property string notificationsText: ""
    readonly property var notificationRows: NexusSuiteModel.parseNotifications(notificationsText, 40)
    readonly property int pendingNotificationCount: NexusSuiteModel.pendingCount(notificationsText)
    // Clipboard history (omarchy.clipboard state file): text rows copy back
    // via wl-copy; image rows defer to the full first-party manager.
    readonly property string clipboardFile: NexusSuiteModel.clipboardPath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    property string clipboardText: ""
    readonly property var clipboardRows: NexusSuiteModel.parseClipboard(clipboardText, 15)
    // Pinned snippets (Nexus's own state file), shown above the history.
    readonly property string pinsFile: NexusSuiteModel.pinsPath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    property string pinsText: ""
    readonly property var pinnedRows: NexusSuiteModel.parsePins(pinsText)
    property string copiedPreview: ""
    property string armedClipKey: ""
    // Quick notes: one markdown file, debounce-autosaved.
    readonly property string notesFile: NexusSuiteModel.notesPath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    property bool notesLoaded: false
    property bool notesDirty: false
    property string notesText: ""

    function storeCalendarText(index, text) {
        var next = calendarTexts.slice();
        while (next.length <= index)next.push("")
        next[index] = text;
        calendarTexts = next;
    }

    function persistPomodoro(next) {
        pomodoroSession = next;
        pomodoroWriter.setText(NexusPomodoroModel.serializeState(next));
    }

    function togglePomodoro() {
        var nowMs = Date.now();
        if (pomodoroSession.phase === "idle")
            persistPomodoro(NexusPomodoroModel.startPhase(pomodoroSession, "work", nowMs, pomodoroConfig));
        else if (NexusPomodoroModel.isPaused(pomodoroSession))
            persistPomodoro(NexusPomodoroModel.resume(pomodoroSession, nowMs));
        else
            persistPomodoro(NexusPomodoroModel.pause(pomodoroSession, nowMs));
    }

    function resolvePomodoroExpiry() {
        if (pomodoroSession.phase === "idle" || NexusPomodoroModel.isPaused(pomodoroSession))
            return ;

        if (NexusPomodoroModel.remainingMs(pomodoroSession, Date.now()) > 0)
            return ;

        persistPomodoro(NexusPomodoroModel.resolveState(pomodoroSession, Date.now(), pomodoroConfig));
    }

    function clearNotificationHistory() {
        // The Alerts page shows pending + past merged, so clearing clears
        // both lists, not just the 15-minute "past" window.
        if (dndService && typeof dndService.clearPast === "function")
            dndService.clearPast();

        if (dndService && typeof dndService.clearPending === "function")
            dndService.clearPending();

    }

    function copyClipboardRow(row) {
        if (!row)
            return ;

        if (row.kind !== "text") {
            nexus.summonSibling("omarchy.clipboard");
            return ;
        }
        copyText(row.text, row.preview);
    }

    function copyText(text, preview) {
        copyProcess.command = NexusSuiteModel.copyCommand(text);
        copyProcess.running = true;
        copiedPreview = String(preview == null ? "" : preview);
    }

    function togglePinRow(row) {
        if (!row || row.kind !== "text")
            return ;

        var texts = [];
        for (var i = 0; i < pinnedRows.length; i++) texts.push(pinnedRows[i].text)
        var serialized = NexusSuiteModel.serializePins(NexusSuiteModel.togglePin(texts, row.text));
        pinsText = serialized;
        pinsWriter.setText(serialized);
    }

    // History deletes arm on the first click and run on the second (the
    // suite's confirm idiom). The write preserves the first-party
    // manager's exact serialization; its file watcher adopts the change.
    function deleteClipRow(row) {
        if (!row || typeof row.key !== "string" || row.key === "")
            return ;

        if (armedClipKey !== row.key) {
            armedClipKey = row.key;
            clipArmTimer.restart();
            return ;
        }
        armedClipKey = "";
        clipArmTimer.stop();
        var serialized = NexusSuiteModel.removeClipEntry(clipboardText, row.key);
        if (serialized === null)
            return ;

        clipboardText = serialized;
        clipWriter.setText(serialized);
    }

    function saveNotes() {
        if (!notesDirty)
            return ;

        notesWriter.setText(state.notesText);
    }

    function updateNotes(text) {
        if (!notesLoaded || text === notesText)
            return ;

        notesText = text;
        notesDirty = true;
    }

    function resetTransient() {
        copiedPreview = "";
        armedClipKey = "";
        clipArmTimer.stop();
    }

    FileView {
        path: state.opened && state.settings.showScreenTime ? state.screenTimeFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.screenTimeText = text()
        onLoadFailed: state.screenTimeText = ""
        onFileChanged: reload()
    }

    Repeater {
        model: 8

        Item {
            id: calendarDelegate

            required property int index

            FileView {
                path: state.opened && state.settings.showNextEvent ? NexusAgendaModel.cachePath(state.calendarCacheDir, calendarDelegate.index) : ""
                printErrors: false
                watchChanges: true
                onLoaded: state.storeCalendarText(calendarDelegate.index, text())
                onFileChanged: reload()
            }

        }

    }

    FileView {
        path: state.opened ? state.pomodoroFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.pomodoroSession = NexusPomodoroModel.parseState(text())
        onLoadFailed: state.pomodoroSession = NexusPomodoroModel.idleState()
        onFileChanged: reload()
    }

    FileView {
        id: pomodoroWriter

        path: state.pomodoroFile
        printErrors: false
        atomicWrites: true
        onSaved: reload()
    }

    FileView {
        path: state.opened ? state.notificationsFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.notificationsText = text()
        onLoadFailed: state.notificationsText = ""
        onFileChanged: reload()
    }

    FileView {
        path: state.opened ? state.clipboardFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.clipboardText = text()
        onLoadFailed: state.clipboardText = ""
        onFileChanged: reload()
    }

    FileView {
        path: state.opened ? state.pinsFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: state.pinsText = text()
        onLoadFailed: state.pinsText = ""
        onFileChanged: reload()
    }

    FileView {
        id: pinsWriter

        path: state.pinsFile
        printErrors: false
        atomicWrites: true
        onSaved: reload()
    }

    FileView {
        id: clipWriter

        path: state.clipboardFile
        printErrors: false
        atomicWrites: true
        onSaved: reload()
    }

    Timer {
        id: clipArmTimer

        interval: 3000
        onTriggered: state.armedClipKey = ""
    }

    Process {
        id: copyProcess

        command: ["wl-copy", "--", ""]
    }

    FileView {
        id: notesReader

        path: state.opened ? state.notesFile : ""
        printErrors: false
        watchChanges: true
        onLoaded: {
            if (!state.notesDirty)
                state.notesText = text();

            state.notesLoaded = true;
        }
        onLoadFailed: state.notesLoaded = true
        onFileChanged: reload()
    }

    FileView {
        id: notesWriter

        path: state.notesFile
        printErrors: false
        atomicWrites: true
        onSaved: {
            state.notesDirty = false;
            reload();
        }
    }

    Timer {
        id: notesSaveTimer

        running: state.notesDirty
        interval: 1500
        onTriggered: state.saveNotes()
    }

}
