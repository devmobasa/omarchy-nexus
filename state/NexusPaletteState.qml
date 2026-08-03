import "../model/NexusModel.js" as NexusModel
import "../model/NexusPaletteModel.js" as NexusPaletteModel
import QtQuick

// Command palette state: the entry catalogue assembled from live facade
// state, the query/cursor, and the per-kind activation switch. The panel's
// key catcher and the palette UI drive this through the facade aliases.
Item {
    id: state

    required property var nexus
    property bool open: false
    property string query: ""
    property int cursor: 0
    // The catalogue, reassembled reactively. Static actions lead so an
    // empty query shows something useful; the keybind bulk sits last and
    // only surfaces through search.
    readonly property var source: {
        const entries = [];
        const pages = NexusModel.PAGES;
        for (let i = 0; i < pages.length; i++) {
            if (pages[i] === nexus.page)
                continue;

            entries.push({
                "kind": NexusPaletteModel.KINDS.PAGE,
                "arg": pages[i],
                "title": "Go to " + NexusModel.pageTitle(pages[i]),
                "subtitle": "page",
                "icon": NexusModel.pageIcon(pages[i])
            });
        }
        const controlEntries = NexusPaletteModel.CONTROL_ENTRIES;
        for (let c = 0; c < controlEntries.length; c++) {
            entries.push({
                "kind": controlEntries[c].kind,
                "arg": controlEntries[c].arg,
                "title": controlEntries[c].title,
                "subtitle": controlSubtitle(controlEntries[c].arg),
                "icon": controlEntries[c].icon
            });
        }
        for (let p = 0; p < nexus.mediaAllPlayers.length; p++) {
            const player = nexus.mediaAllPlayers[p];
            entries.push({
                "kind": NexusPaletteModel.KINDS.PLAYER,
                "arg": p,
                "title": "Play / pause " + (player.identity || player.dbusName || "player"),
                "subtitle": player.isPlaying ? "playing" : "paused",
                "icon": "󰎈"
            });
        }
        for (let m = 0; m < nexus.minimizerRows.length; m++) {
            entries.push({
                "kind": NexusPaletteModel.KINDS.MINIMIZED,
                "arg": nexus.minimizerRows[m].address,
                "title": "Restore " + nexus.minimizerRows[m].title,
                "subtitle": nexus.minimizerRows[m].origin,
                "icon": "󰖰"
            });
        }
        for (let n = 0; n < nexus.pinnedClipboardRows.length; n++) {
            entries.push({
                "kind": NexusPaletteModel.KINDS.PIN,
                "arg": nexus.pinnedClipboardRows[n].text,
                "title": nexus.pinnedClipboardRows[n].preview,
                "subtitle": "copy pinned snippet",
                "icon": "󰐃"
            });
        }
        for (let s = 0; s < nexus.settingsRows.length; s++) {
            entries.push({
                "kind": NexusPaletteModel.KINDS.SETTING,
                "arg": nexus.settingsRows[s].key,
                "title": "Setting: " + nexus.settingsRows[s].label,
                "subtitle": nexus.settings[nexus.settingsRows[s].key] === true ? "on" : "off",
                "icon": "󰒓"
            });
        }
        entries.push({
            "kind": NexusPaletteModel.KINDS.SIBLING,
            "arg": "omarchy.clipboard",
            "title": "Open full clipboard manager",
            "subtitle": "plugin",
            "icon": "󰅍"
        });
        if (nexus.wallpaperHubAvailable)
            entries.push({
            "kind": NexusPaletteModel.KINDS.SIBLING,
            "arg": "community.wallpaper-hub",
            "title": "Open Wallpaper Hub",
            "subtitle": "plugin",
            "icon": "󰸉"
        });

        for (let k = 0; k < nexus.keybindRows.length; k++) {
            entries.push({
                "kind": NexusPaletteModel.KINDS.KEYBIND,
                "arg": nexus.keybindRows[k].combo + " — " + nexus.keybindRows[k].description,
                "title": nexus.keybindRows[k].combo,
                "subtitle": nexus.keybindRows[k].description,
                "icon": "󰌌"
            });
        }
        return entries;
    }
    readonly property var results: NexusPaletteModel.filterEntries(source, query, NexusPaletteModel.MAX_RESULTS)

    function controlSubtitle(name) {
        if (name === "dnd")
            return nexus.dndService && nexus.dndService.doNotDisturb === true ? "on" : "off";

        if (name === "night-light")
            return nexus.nightlightService && nexus.nightlightService.enabled === true ? "on" : "off";

        if (name === "stay-awake")
            return nexus.idleService && nexus.idleService.idleEnabled === false ? "on" : "off";

        if (name === "bluetooth")
            return nexus.btAdapter && nexus.btAdapter.enabled === true ? "on" : "off";

        if (name === "mute-output")
            return nexus.outputMuted ? "muted" : "live";

        if (name === "mute-microphone")
            return nexus.inputMuted ? "muted" : "live";

        if (name === "game-mode")
            return nexus.gameModeOn ? "on" : "off";

        if (name === "pomodoro")
            return nexus.pomodoroSession.phase;

        return "";
    }

    function openPalette(seed) {
        query = typeof seed === "string" ? seed : "";
        cursor = 0;
        open = true;
        nexus.refreshBinds();
    }

    function closePalette() {
        open = false;
        query = "";
        cursor = 0;
    }

    function runControlAction(name) {
        if (name === "dnd")
            nexus.dispatchControl("dnd", nexus.toggleDnd);
        else if (name === "night-light")
            nexus.dispatchControl("night-light", nexus.toggleNightlight);
        else if (name === "stay-awake")
            nexus.dispatchControl("stay-awake", nexus.toggleStayAwake);
        else if (name === "bluetooth")
            nexus.dispatchControl("bluetooth", nexus.toggleBluetooth);
        else if (name === "mute-output")
            nexus.dispatchControl("mute-output", nexus.toggleOutputMute);
        else if (name === "mute-microphone")
            nexus.dispatchControl("mute-microphone", nexus.toggleInputMute);
        else if (name === "game-mode")
            nexus.toggleGameMode();
        else if (name === "pomodoro")
            nexus.togglePomodoro();
        else if (name === "clear-alerts")
            nexus.clearNotificationHistory();
        else if (NexusModel.MENU_ROUTES[name] !== undefined)
            nexus.openMenuRoute(NexusModel.MENU_ROUTES[name]);
    }

    function runEntry(entry) {
        if (!entry)
            return ;

        closePalette();
        if (entry.kind === NexusPaletteModel.KINDS.PAGE) {
            nexus.setPage(entry.arg);
        } else if (entry.kind === NexusPaletteModel.KINDS.CONTROL) {
            runControlAction(entry.arg);
        } else if (entry.kind === NexusPaletteModel.KINDS.PLAYER) {
            const player = nexus.mediaAllPlayers[entry.arg];
            if (player) {
                nexus.selectPlayerByObject(player);
                if (player.isPlaying && player.canPause)
                    player.pause();
                else if (!player.isPlaying && player.canPlay)
                    player.play();
            }
        } else if (entry.kind === NexusPaletteModel.KINDS.MINIMIZED) {
            for (let i = 0; i < nexus.minimizerRows.length; i++) {
                if (nexus.minimizerRows[i].address === entry.arg) {
                    nexus.restoreMinimized(nexus.minimizerRows[i]);
                    break;
                }
            }
        } else if (entry.kind === NexusPaletteModel.KINDS.SETTING) {
            nexus.updateSetting(entry.arg, nexus.settings[entry.arg] !== true);
        } else if (entry.kind === NexusPaletteModel.KINDS.PIN || entry.kind === NexusPaletteModel.KINDS.KEYBIND) {
            nexus.copyText(entry.arg, entry.title);
        } else if (entry.kind === NexusPaletteModel.KINDS.SIBLING) {
            nexus.summonSibling(entry.arg);
        }
    }

    onResultsChanged: {
        if (cursor >= results.length)
            cursor = Math.max(0, results.length - 1);

    }
}
