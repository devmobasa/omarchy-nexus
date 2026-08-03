import "../model/NexusLatencyModel.js" as NexusLatencyModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell.Io

// Split-path latency sampling: the router leg and the internet leg are
// launched in the same tick so they overlap (~1 s worst case inside the
// 3 s cadence). Runs only while the Network card is actually visible.
Item {
    id: state

    required property var nexus
    readonly property bool active: nexus.opened && nexus.page === NexusModel.PAGE_OVERVIEW && nexus.settings.showMetrics && nexus.settings.showNetwork
    property string routerHost: ""
    property var routerRing: []
    property var internetRing: []
    readonly property string routerLatency: NexusLatencyModel.formatLatency(routerRing)
    readonly property string internetLatency: NexusLatencyModel.formatLatency(internetRing)

    function samplePings() {
        if (!routeProcess.running)
            routeProcess.running = true;

        if (!internetPing.running)
            internetPing.running = true;

        const command = NexusLatencyModel.pingCommand(routerHost);
        if (command.length > 0 && !routerPing.running) {
            routerPing.command = command;
            routerPing.running = true;
        }
    }

    function resetSession() {
        routerHost = "";
        routerRing = [];
        internetRing = [];
    }

    onActiveChanged: {
        if (active)
            samplePings();

    }

    Timer {
        running: state.active
        interval: NexusLatencyModel.PING_INTERVAL_MS
        repeat: true
        onTriggered: state.samplePings()
    }

    Process {
        id: routeProcess

        property bool exitSeen: false

        command: NexusLatencyModel.routeCommand()
        onStarted: exitSeen = false
        onExited: exitSeen = true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const gateway = NexusLatencyModel.parseDefaultRoute(text);
                if (gateway !== state.routerHost) {
                    // A different gateway is a different network: the old
                    // samples say nothing about it.
                    state.routerHost = gateway;
                    state.routerRing = [];
                }
            }
        }

    }

    Process {
        id: routerPing

        property bool exitSeen: false

        command: ["ping", "-V"]
        environment: ({
            "LC_ALL": "C"
        })
        onStarted: exitSeen = false
        onExited: exitSeen = true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.routerRing = NexusLatencyModel.pushSample(state.routerRing, NexusLatencyModel.parsePing(text))
        }

    }

    Process {
        id: internetPing

        property bool exitSeen: false

        command: NexusLatencyModel.pingCommand(NexusLatencyModel.INTERNET_PROBE)
        environment: ({
            "LC_ALL": "C"
        })
        onStarted: exitSeen = false
        onExited: exitSeen = true

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.internetRing = NexusLatencyModel.pushSample(state.internetRing, NexusLatencyModel.parsePing(text))
        }

    }

}
