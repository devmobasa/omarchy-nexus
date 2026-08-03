import "../model/NexusMetricsModel.js" as NexusMetricsModel
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

Item {
    id: state

    required property var nexus
    readonly property bool opened: nexus.opened
    readonly property date now: nexus.now
    // ---- metrics sampler -----------------------------------------------------
    // One bounded sampler: cpu/mem via one cat of /proc/stat + /proc/meminfo
    // every 2 s, storage via df every 30 s, both only while open (the timers
    // below stop with `opened`). Units: integer percent; storage in GiB.
    // Readings older than 3x their cadence render as stale ("—").
    property var cpuPrevSample: null
    property var cpuValue: null
    property var memValue: null
    property var diskValue: null
    property var cpuHistory: []
    property var memHistory: []
    property double statSampledAt: 0
    property double diskSampledAt: 0
    // Network throughput shares the same single sampler process; rates derive
    // from cumulative counter deltas, histories feed the sparkline.
    property var netPrevSample: null
    property var netRxRate: null
    property var netTxRate: null
    property var netRxHistory: []
    property var netTxHistory: []
    property var uptimeSeconds: null
    // Static system facts for the fetch row: one-shot async reads while open,
    // following the shell's FileView house pattern (never blocking).
    property string hostName: ""
    property string kernelVersion: ""
    // ---- battery (reactive UPower state; no polling) -------------------------
    readonly property var batteryDevice: UPower.displayDevice
    readonly property bool batteryPresent: batteryDevice ? batteryDevice.isPresent === true : false
    readonly property int batteryPercent: batteryPresent ? NexusMetricsModel.clampPercent(batteryDevice.percentage) : 0
    // ---- metric staleness ----------------------------------------------------
    // Plain bool bindings: they re-evaluate with the clock but only notify on
    // an actual flip, so the meters are not rebuilt every second.
    readonly property bool statStale: NexusMetricsModel.isStale(statSampledAt, now.getTime(), NexusMetricsModel.CPU_MEM_INTERVAL_MS)
    readonly property bool diskStale: NexusMetricsModel.isStale(diskSampledAt, now.getTime(), NexusMetricsModel.DISK_INTERVAL_MS)
    readonly property bool statStaleShown: statStale && statSampledAt > 0
    readonly property bool diskStaleShown: diskStale && diskSampledAt > 0

    function resetSession() {
        netPrevSample = null;
        netRxRate = null;
        netTxRate = null;
        netRxHistory = [];
        netTxHistory = [];
        cpuHistory = [];
        memHistory = [];
    }

    FileView {
        path: state.opened ? "/proc/sys/kernel/hostname" : ""
        printErrors: false
        onLoaded: state.hostName = text().trim()
    }

    FileView {
        path: state.opened ? "/proc/sys/kernel/osrelease" : ""
        printErrors: false
        onLoaded: state.kernelVersion = text().trim()
    }

    Process {
        id: statProcess

        command: ["cat", "/proc/stat", "/proc/meminfo", "/proc/net/dev", "/proc/uptime"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var parsed = NexusMetricsModel.parseSample(text);
                var nowMs = Date.now();
                if (parsed.cpu) {
                    state.cpuValue = NexusMetricsModel.cpuPercent(state.cpuPrevSample, parsed.cpu);
                    state.cpuPrevSample = parsed.cpu;
                    if (state.cpuValue !== null)
                        state.cpuHistory = NexusMetricsModel.pushHistory(state.cpuHistory, state.cpuValue, NexusMetricsModel.STAT_HISTORY_CAP);

                }
                if (parsed.mem) {
                    state.memValue = parsed.mem.percent;
                    state.memHistory = NexusMetricsModel.pushHistory(state.memHistory, state.memValue, NexusMetricsModel.STAT_HISTORY_CAP);
                }

                if (parsed.uptimeSeconds !== null)
                    state.uptimeSeconds = parsed.uptimeSeconds;

                if (parsed.net) {
                    var prev = state.netPrevSample;
                    state.netRxRate = NexusMetricsModel.rateBetween(prev ? prev.rxBytes : null, prev ? prev.atMs : 0, parsed.net.rxBytes, nowMs);
                    state.netTxRate = NexusMetricsModel.rateBetween(prev ? prev.txBytes : null, prev ? prev.atMs : 0, parsed.net.txBytes, nowMs);
                    state.netPrevSample = {
                        "rxBytes": parsed.net.rxBytes,
                        "txBytes": parsed.net.txBytes,
                        "atMs": nowMs
                    };
                    if (state.netRxRate !== null || state.netTxRate !== null) {
                        state.netRxHistory = NexusMetricsModel.pushHistory(state.netRxHistory, state.netRxRate, NexusMetricsModel.NET_HISTORY_CAP);
                        state.netTxHistory = NexusMetricsModel.pushHistory(state.netTxHistory, state.netTxRate, NexusMetricsModel.NET_HISTORY_CAP);
                    }
                }
                if (parsed.cpu || parsed.mem)
                    state.statSampledAt = nowMs;

            }
        }

    }

    Process {
        id: diskProcess

        command: ["df", "-P", "-k", "/"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var parsed = NexusMetricsModel.parseDiskFree(text);
                if (parsed) {
                    state.diskValue = parsed;
                    state.diskSampledAt = Date.now();
                }
            }
        }

    }

    Timer {
        running: state.opened
        interval: NexusMetricsModel.CPU_MEM_INTERVAL_MS
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statProcess.running) {
                statProcess.running = true;
            }
        }
    }

    Timer {
        running: state.opened
        interval: NexusMetricsModel.DISK_INTERVAL_MS
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!diskProcess.running) {
                diskProcess.running = true;
            }
        }
    }

}
