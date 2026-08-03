import "../model/NexusModel.js" as NexusModel
import "../model/NexusPomodoroModel.js" as NexusPomodoroModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: controlsPage

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_CONTROLS
    width: parent.width
    spacing: Style.space(4)

    Toggle {
        width: parent.width
        label: "Mute output"
        description: nexus.audioSink ? "Silence the default output device." : "No output device available."
        enabled: nexus.audioSink !== null && nexus.pendingActionName === ""
        checked: nexus.outputMuted
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.MUTE
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.MUTE;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.MUTE;
            nexus.dispatchControl("mute-output", nexus.toggleOutputMute);
        }
    }

    Toggle {
        width: parent.width
        label: "Mute microphone"
        description: nexus.audioSource ? "Silence the default input device." : "No input device available."
        enabled: nexus.audioSource !== null && nexus.pendingActionName === ""
        checked: nexus.inputMuted
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.MICROPHONE
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.MICROPHONE;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.MICROPHONE;
            nexus.dispatchControl("mute-microphone", nexus.toggleInputMute);
        }
    }

    // Live input peak: what the mic actually hears, -55 dBFS floor to
    // full scale. Zero (and flat) while muted.
    Item {
        width: parent.width
        height: Style.space(4)
        visible: nexus.audioSource !== null

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(3)
            radius: height / 2
            color: nexus.softText(0.1)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * nexus.micLevel
                radius: parent.radius
                color: nexus.inputMuted ? nexus.softAccent(0.25) : nexus.softAccent(0.7)

                Behavior on width {
                    NumberAnimation {
                        duration: 70
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

    }

    Toggle {
        width: parent.width
        label: "Do not disturb"
        description: nexus.dndService ? "Silence notification popups." : "Notifications service unavailable."
        enabled: nexus.dndService !== null && nexus.pendingActionName === ""
        checked: nexus.dndService !== null && nexus.dndService.doNotDisturb === true
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.DND
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.DND;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.DND;
            nexus.dispatchControl("dnd", nexus.toggleDnd);
        }
    }

    Toggle {
        width: parent.width
        label: "Night light"
        description: nexus.nightlightService ? "Warm the display color temperature." : "Night light service unavailable."
        enabled: nexus.nightlightService !== null && nexus.pendingActionName === ""
        checked: nexus.nightlightService !== null && nexus.nightlightService.enabled === true
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.NIGHT_LIGHT
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.NIGHT_LIGHT;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.NIGHT_LIGHT;
            nexus.dispatchControl("night-light", nexus.toggleNightlight);
        }
    }

    Toggle {
        width: parent.width
        label: "Stay awake"
        description: nexus.idleService ? "Prevent idle lock and screen off." : "Idle service unavailable."
        enabled: nexus.idleService !== null && nexus.pendingActionName === ""
        checked: nexus.idleService !== null && nexus.idleService.idleEnabled === false
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.STAY_AWAKE
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.STAY_AWAKE;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.STAY_AWAKE;
            nexus.dispatchControl("stay-awake", nexus.toggleStayAwake);
        }
    }

    Toggle {
        width: parent.width
        label: "Bluetooth"
        description: nexus.btAdapter ? "Power the default Bluetooth adapter." : "No Bluetooth adapter."
        enabled: nexus.btAdapter !== null && nexus.pendingActionName === ""
        checked: nexus.btAdapter !== null && nexus.btAdapter.enabled === true
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.BLUETOOTH
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.BLUETOOTH;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.BLUETOOTH;
            nexus.dispatchControl("bluetooth", nexus.toggleBluetooth);
        }
    }

    Toggle {
        width: parent.width
        label: "Game mode"
        description: nexus.gameModeError !== "" ? nexus.gameModeError : (nexus.gameModePending ? "Applying…" : (!nexus.gameModeOn && nexus.gameModeFlagContent === null ? "Nothing selected to strip — pick effects in Settings." : "Strip compositor effects; configure the set in Settings."))
        enabled: !nexus.gameModePending && (nexus.gameModeOn || nexus.gameModeFlagContent !== null)
        checked: nexus.gameModeOn
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.GAME_MODE && nexus.page === NexusModel.PAGE_CONTROLS
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.GAME_MODE;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.GAME_MODE;
            nexus.toggleGameMode();
        }
    }

    Toggle {
        width: parent.width
        label: "Pomodoro"
        description: nexus.pomodoroSession.phase === "idle" ? "Start a focus session (" + nexus.pomodoroSession.todayCount + " done today)." : NexusPomodoroModel.labelFor(nexus.pomodoroSession.phase) + (NexusPomodoroModel.isPaused(nexus.pomodoroSession) ? " (paused)" : "") + " — " + NexusPomodoroModel.formatRemaining(NexusPomodoroModel.remainingMs(nexus.pomodoroSession, nexus.now.getTime())) + " left. Click to " + (NexusPomodoroModel.isPaused(nexus.pomodoroSession) ? "resume" : "pause") + "."
        checked: nexus.pomodoroSession.phase !== "idle" && !NexusPomodoroModel.isPaused(nexus.pomodoroSession)
        foreground: Color.menu.text
        accent: Color.accent
        fontFamily: Style.font.family
        hasCursor: nexus.controlCursor === NexusModel.CONTROLS_ROWS.POMODORO && nexus.page === NexusModel.PAGE_CONTROLS
        onHovered: function(h) {
            if (h)
                nexus.controlCursor = NexusModel.CONTROLS_ROWS.POMODORO;

        }
        onClicked: {
            nexus.controlCursor = NexusModel.CONTROLS_ROWS.POMODORO;
            nexus.togglePomodoro();
        }
    }

}
