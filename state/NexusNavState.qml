import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Navigation policy: which screen the panel opens on, how far the keyboard
// cursor reaches per page, and what activating a cursor row does. The
// facade keeps thin delegates so its IPC surface is unchanged.
Item {
    id: state

    required property var nexus
    readonly property int lastCursorIndex: {
        if (nexus.page === NexusModel.PAGE_CONTROLS)
            return NexusModel.CONTROLS_LAST_ROW;

        if (nexus.page === NexusModel.PAGE_OVERVIEW) {
            if (!nexus.settings.showMedia || nexus.mediaSelected === null)
                return -1;

            return nexus.mediaPlayerCount > 1 ? 2 : 1;
        }
        if (nexus.page === NexusModel.PAGE_STYLE)
            return nexus.wallpaperHubAvailable ? NexusModel.STYLE_ROWS.WALLPAPERS : NexusModel.STYLE_ROWS.BACKGROUND;

        if (nexus.page === NexusModel.PAGE_SETTINGS)
            return nexus.settingsRows.length - 1;

        if (nexus.page === NexusModel.PAGE_MEDIA)
            return nexus.mediaAllPlayers.length - 1;

        if (nexus.page === NexusModel.PAGE_CLIPBOARD)
            return nexus.clipboardAllRows.length - 1;

        if (nexus.page === NexusModel.PAGE_MINIMIZER)
            return nexus.minimizerRows.length - 1;

        return -1;
    }

    function targetScreenForOpen() {
        const screens = Quickshell.screens || [];
        const wanted = nexus.settings.monitor;
        if (wanted && wanted !== "focused") {
            for (let i = 0; i < screens.length; i++) {
                if (String(screens[i].name || "") === wanted)
                    return screens[i];

            }
        }
        const focused = Hyprland.focusedMonitor;
        for (let i = 0; i < screens.length; i++) {
            const monitor = Hyprland.monitorFor(screens[i]);
            if (focused && monitor === focused)
                return screens[i];

            if (focused && monitor && monitor.id === focused.id)
                return screens[i];

            if (focused && String(screens[i].name || "") === String(focused.name || ""))
                return screens[i];

        }
        const active = ToplevelManager.activeToplevel;
        if (active && active.screens && active.screens.length > 0)
            return active.screens[0];

        return screens.length > 0 ? screens[0] : null;
    }

    function activateControl(index) {
        if (nexus.page === NexusModel.PAGE_OVERVIEW) {
            if (index === NexusModel.OVERVIEW_ROWS.TRANSPORT)
                nexus.mediaAction("playpause");
            else if (index === NexusModel.OVERVIEW_ROWS.PLAYER_CHIP)
                nexus.cycleMediaPlayer();
        } else if (nexus.page === NexusModel.PAGE_CONTROLS) {
            if (index === NexusModel.CONTROLS_ROWS.VOLUME)
                nexus.dispatchControl("mute-output", nexus.toggleOutputMute);
            else if (index === NexusModel.CONTROLS_ROWS.MUTE)
                nexus.dispatchControl("mute-output", nexus.toggleOutputMute);
            else if (index === NexusModel.CONTROLS_ROWS.MICROPHONE)
                nexus.dispatchControl("mute-microphone", nexus.toggleInputMute);
            else if (index === NexusModel.CONTROLS_ROWS.DND)
                nexus.dispatchControl("dnd", nexus.toggleDnd);
            else if (index === NexusModel.CONTROLS_ROWS.NIGHT_LIGHT)
                nexus.dispatchControl("night-light", nexus.toggleNightlight);
            else if (index === NexusModel.CONTROLS_ROWS.STAY_AWAKE)
                nexus.dispatchControl("stay-awake", nexus.toggleStayAwake);
            else if (index === NexusModel.CONTROLS_ROWS.BLUETOOTH)
                nexus.dispatchControl("bluetooth", nexus.toggleBluetooth);
            else if (index === NexusModel.CONTROLS_ROWS.GAME_MODE)
                nexus.toggleGameMode();
            else if (index === NexusModel.CONTROLS_ROWS.POMODORO)
                nexus.togglePomodoro();
            else if (index === NexusModel.CONTROLS_ROWS.CAPTURE)
                nexus.openMenuRoute(NexusModel.MENU_ROUTES.capture);
            else if (index === NexusModel.CONTROLS_ROWS.POWER)
                nexus.openMenuRoute(NexusModel.MENU_ROUTES.power);
        } else if (nexus.page === NexusModel.PAGE_STYLE) {
            if (index === NexusModel.STYLE_ROWS.THEME)
                nexus.openMenuRoute(NexusModel.MENU_ROUTES.theme);
            else if (index === NexusModel.STYLE_ROWS.BACKGROUND)
                nexus.openMenuRoute(NexusModel.MENU_ROUTES.background);
            else if (index === NexusModel.STYLE_ROWS.WALLPAPERS && nexus.wallpaperHubAvailable)
                nexus.summonSibling("community.wallpaper-hub");
        } else if (nexus.page === NexusModel.PAGE_SETTINGS) {
            const row = nexus.settingsRows[index];
            if (row)
                nexus.updateSetting(row.key, nexus.settings[row.key] !== true);

        } else if (nexus.page === NexusModel.PAGE_MEDIA) {
            const player = nexus.mediaAllPlayers[index];
            if (player) {
                nexus.selectPlayerByObject(player);
                if (player.isPlaying && player.canPause)
                    player.pause();
                else if (!player.isPlaying && player.canPlay)
                    player.play();
            }
        } else if (nexus.page === NexusModel.PAGE_CLIPBOARD) {
            nexus.copyClipboardRow(nexus.clipboardAllRows[index]);
        } else if (nexus.page === NexusModel.PAGE_MINIMIZER) {
            nexus.restoreMinimized(nexus.minimizerRows[index]);
        }
    }

}
