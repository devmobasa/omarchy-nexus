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
    // Clipboard history (omarchy.clipboard state file): text rows copy back
    // via wl-copy; image rows defer to the full first-party manager.
    readonly property string clipboardFile: NexusSuiteModel.clipboardPath(Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"))
    property string clipboardText: ""
    readonly property var clipboardRows: NexusSuiteModel.parseClipboard(clipboardText, 15)
    property string copiedPreview: ""
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
        if (dndService && typeof dndService.clearPast === "function")
            dndService.clearPast();

    }

    function copyClipboardRow(row) {
        if (!row)
            return ;

        if (row.kind !== "text") {
            nexus.summonSibling("omarchy.clipboard");
            return ;
        }
        copyProcess.command = NexusSuiteModel.copyCommand(row.text);
        copyProcess.running = true;
        copiedPreview = row.preview;
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
