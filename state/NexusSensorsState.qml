import "../model/NexusSensorsModel.js" as NexusSensorsModel
import QtQuick
import Quickshell.Io

Item {
    id: state

    required property var nexus
    readonly property bool opened: nexus.opened
    readonly property var settings: nexus.settings
    // ---- hardware sensors ----------------------------------------------------
    // Discovery once per open (hwmon indices are probe-order); sampling greps
    // exactly the selected paths (self-labeling, shift-immune). An NVIDIA
    // display GPU has no sysfs telemetry, so nvidia-smi joins the cadence;
    // its absence just drops the GPU row.
    property var sensorsCatalog: null
    property var sensorsSpec: null
    property var sensorSampleMap: ({
    })
    property var nvidiaInfo: null
    property bool nvidiaAvailable: true
    readonly property var sensorReadings: sensorsSpec ? NexusSensorsModel.readings(sensorsSpec, sensorSampleMap, nvidiaInfo, sensorsCatalog) : []

    function runSensorSample() {
        if (!sensorsSpec || !sensorsCatalog)
            return ;

        var paths = NexusSensorsModel.samplePaths(sensorsSpec, sensorsCatalog);
        if (paths.length > 0) {
            sensorSampleProcess.command = NexusSensorsModel.sampleCommand(paths);
            if (!sensorSampleProcess.running)
                sensorSampleProcess.running = true;

        }
        if (sensorsSpec.gpu && sensorsSpec.gpu.kind === "nvidia" && nvidiaAvailable && !nvidiaProcess.running) {
            nvidiaProcess.exitSeen = false;
            nvidiaProcess.running = true;
        }
    }

    function discover() {
        if (!sensorDiscoveryProcess.running)
            sensorDiscoveryProcess.running = true;

    }

    function resetSession() {
        sensorsCatalog = null;
        sensorsSpec = null;
        sensorSampleMap = ({
        });
        nvidiaInfo = null;
        nvidiaAvailable = true;
    }

    Process {
        id: sensorDiscoveryProcess

        command: NexusSensorsModel.discoveryCommand()

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                state.sensorsCatalog = NexusSensorsModel.parseDiscovery(text);
                state.sensorsSpec = NexusSensorsModel.selectSensors(state.sensorsCatalog);
                state.runSensorSample();
            }
        }

        // find -L reports harmless sysfs symlink loops; keep them out of the log.
        stderr: StdioCollector {
            waitForEnd: true
        }

    }

    Process {
        id: sensorSampleProcess

        command: ["grep", "-H", ".", "/dev/null"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: state.sensorSampleMap = NexusSensorsModel.parseLines(text)
        }

    }

    Process {
        id: nvidiaProcess

        property bool exitSeen: false

        command: NexusSensorsModel.nvidiaCommand()
        onRunningChanged: {
            if (!running && !exitSeen) {
                state.nvidiaAvailable = false;
            }
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                nvidiaProcess.exitSeen = true;
                state.nvidiaInfo = NexusSensorsModel.parseNvidiaSmi(text);
            }
        }

    }

    Timer {
        running: state.opened && state.sensorsSpec !== null && state.settings.showSensors
        interval: NexusSensorsModel.SENSOR_INTERVAL_MS
        repeat: true
        onTriggered: state.runSensorSample()
    }

}
