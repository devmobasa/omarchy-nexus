import "../model/NexusMediaModel.js" as NexusMediaModel
import QtQuick
import Quickshell.Services.Mpris

Item {
    id: state

    required property var nexus
    readonly property bool opened: nexus.opened
    readonly property var settings: nexus.settings
    // ---- media adapter -------------------------------------------------------
    // One direct MPRIS adapter; selection is the deterministic two-phase model
    // in NexusMediaModel. All reactivity is gated on `opened` (the watcher
    // Repeater below has an empty model while closed), so closed-state media
    // activity is zero. Serial history is session-scoped.
    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
    property var mediaSerials: ({
    })
    property int mediaLastSerial: 0
    property var mediaSelected: null
    // Manual player choice from the switcher chip; wins while that player
    // exists, cleared on close. Count drives the chip's visibility.
    property string mediaOverrideKey: ""
    property int mediaPlayerCount: 0
    property var mediaAllPlayers: []
    // Seek preview while dragging, so the bar tracks the pointer instead of
    // the (as yet unmoved) player position.
    property bool seekDragging: false
    property real seekPreviewFraction: 0
    // The player's usable track length: only a supported, positive length may
    // drive the seek bar (an unsupported length mirrors position and would pin
    // the bar to 100%).
    readonly property real mediaUsableLength: mediaSelected && mediaSelected.lengthSupported && mediaSelected.length > 0 ? mediaSelected.length : 0

    function playbackStateOf(player) {
        if (player.playbackState === MprisPlaybackState.Playing)
            return "playing";

        if (player.playbackState === MprisPlaybackState.Paused)
            return "paused";

        if (player.playbackState === MprisPlaybackState.Stopped)
            return "stopped";

        return "unknown";
    }

    function mediaRecordOf(player) {
        return NexusMediaModel.buildRecord({
            "busName": player.dbusName || "",
            "identity": player.identity || "",
            "desktopEntry": player.desktopEntry || "",
            "state": playbackStateOf(player),
            "trackKey": [player.trackTitle || "", player.trackArtist || ""].join("\u0000"),
            "canPlay": !!player.canPlay,
            "canPause": !!player.canPause,
            "canGoNext": !!player.canGoNext,
            "canGoPrevious": !!player.canGoPrevious
        });
    }

    function refreshMedia() {
        if (!opened)
            return ;

        var players = mprisPlayers;
        var recordsList = [];
        for (var i = 0; i < players.length; i++) {
            if (players[i])
                recordsList.push(mediaRecordOf(players[i]));

        }
        var activity = NexusMediaModel.reconcileActivity(mediaSerials, recordsList, mediaLastSerial);
        mediaSerials = activity.serials;
        mediaLastSerial = activity.lastSerial;
        mediaPlayerCount = NexusMediaModel.countPlayers(recordsList);
        // The full ordered representative list backs the Media page.
        var representatives = NexusMediaModel.orderedRepresentatives(recordsList, NexusMediaModel.normalizeIdentity(settings.preferredMediaIdentity), mediaSerials);
        var ordered = [];
        for (var r = 0; r < representatives.length; r++) {
            for (var p = 0; p < players.length; p++) {
                if (players[p] && String(players[p].dbusName || "") === representatives[r].busName) {
                    ordered.push(players[p]);
                    break;
                }
            }
        }
        mediaAllPlayers = ordered;
        var chosen = NexusMediaModel.selectPlayer(recordsList, settings.preferredMediaIdentity, mediaSerials, mediaOverrideKey);
        var next = null;
        if (chosen) {
            for (var j = 0; j < players.length; j++) {
                if (players[j] && String(players[j].dbusName || "") === chosen.busName) {
                    next = players[j];
                    break;
                }
            }
        }
        mediaSelected = next;
    }

    function selectPlayerByObject(player) {
        if (!player)
            return ;

        mediaOverrideKey = mediaRecordOf(player).sourceKey;
        refreshMedia();
    }

    // Chip action: step to the next player in the deterministic order and pin
    // it as the manual override.
    function cycleMediaPlayer() {
        var players = mprisPlayers;
        var recordsList = [];
        for (var i = 0; i < players.length; i++) {
            if (players[i])
                recordsList.push(mediaRecordOf(players[i]));

        }
        var currentKey = mediaSelected ? mediaRecordOf(mediaSelected).sourceKey : "";
        var nextKey = NexusMediaModel.cyclePlayer(recordsList, currentKey, settings.preferredMediaIdentity, mediaSerials);
        if (nextKey === "")
            return ;

        mediaOverrideKey = nextKey;
        refreshMedia();
    }

    // Seek paths per the verified Quickshell contract: an absolute position
    // write needs canSeek AND positionSupported; the relative seek() needs only
    // canSeek. clampSeek returns null rather than letting a blind seek through.
    function applySeekFraction(fraction) {
        var player = mediaSelected;
        if (!player)
            return ;

        var target = NexusMediaModel.clampSeek(fraction, mediaUsableLength, player.canSeek && player.positionSupported);
        if (target === null)
            return ;

        player.position = target;
    }

    function seekBy(offsetSeconds) {
        var player = mediaSelected;
        if (!player || !player.canSeek)
            return false;

        player.seek(offsetSeconds);
        return true;
    }

    // Actions route only to the selected representative and only when it
    // reports the capability; a successful action bumps its activity serial.
    // Returns whether the action was consumed, so the key handler can fall
    // back to page cycling instead of swallowing the keystroke.
    function mediaAction(kind) {
        var player = mediaSelected;
        if (!player)
            return false;

        if (kind === "playpause") {
            if (player.isPlaying && player.canPause)
                player.pause();
            else if (!player.isPlaying && player.canPlay)
                player.play();
            else
                return false;
        } else if (kind === "next") {
            if (!player.canGoNext)
                return false;

            player.next();
        } else if (kind === "previous") {
            if (!player.canGoPrevious)
                return false;

            player.previous();
        } else {
            return false;
        }
        var bumped = NexusMediaModel.bumpUserAction(mediaSerials, String(player.dbusName || ""), mediaLastSerial);
        mediaSerials = bumped.serials;
        mediaLastSerial = bumped.lastSerial;
        refreshMedia();
        return true;
    }

    function resetSession() {
        mediaSelected = null;
        mediaOverrideKey = "";
        mediaPlayerCount = 0;
        mediaAllPlayers = [];
        seekDragging = false;
    }

    // MPRIS position does not tick on its own; emitting positionChanged() once
    // a second re-reads the locally extrapolated value (no D-Bus traffic).
    // Runs only while the panel is open, a player is selected, and playing.
    Timer {
        running: state.opened && state.mediaSelected !== null && state.mediaSelected.isPlaying
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (state.mediaSelected) {
                state.mediaSelected.positionChanged();
            }
        }
    }

    // Player lifecycle and state watcher; empty model while closed.
    Repeater {
        model: state.opened ? state.mprisPlayers : []
        onItemAdded: state.refreshMedia()
        onItemRemoved: state.refreshMedia()

        Item {
            required property var modelData

            Connections {
                function onPlaybackStateChanged() {
                    state.refreshMedia();
                }

                function onTrackTitleChanged() {
                    state.refreshMedia();
                }

                function onTrackArtistChanged() {
                    state.refreshMedia();
                }

                target: modelData
            }

        }

    }

}
