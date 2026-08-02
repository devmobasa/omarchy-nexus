import "../model/NexusMetricsModel.js" as NexusMetricsModel
import "../model/NexusModel.js" as NexusModel
import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

Grid {
    id: metricGrid

    required property var nexus

    visible: nexus.page === NexusModel.PAGE_OVERVIEW && nexus.settings.showMetrics
    width: parent.width
    columns: width < Style.space(300) ? 1 : 2
    columnSpacing: Style.spacing.md
    rowSpacing: Style.spacing.md

    NexusArcMeter {
        nexus: metricGrid.nexus
        visible: nexus.settings.showCpu
        width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
        label: "CPU"
        percent: !nexus.statStale && nexus.cpuValue !== null ? nexus.cpuValue : null
        stale: nexus.statStaleShown
        detail: nexus.statStaleShown ? "Stale" : "Usage"
    }

    NexusArcMeter {
        nexus: metricGrid.nexus
        visible: nexus.settings.showMemory
        width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
        label: "Memory"
        percent: !nexus.statStale && nexus.memValue !== null ? nexus.memValue : null
        stale: nexus.statStaleShown
        detail: nexus.statStaleShown ? "Stale" : "In use"
    }

    NexusArcMeter {
        nexus: metricGrid.nexus
        visible: nexus.settings.showStorage
        width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
        label: "Storage"
        percent: !nexus.diskStale && nexus.diskValue ? nexus.diskValue.percent : null
        stale: nexus.diskStaleShown
        detail: !nexus.diskStale && nexus.diskValue ? NexusMetricsModel.formatGib(nexus.diskValue.availableKb) + " free on " + nexus.diskValue.mount : (nexus.diskStaleShown ? "Stale" : "Used on /")
    }

    NexusArcMeter {
        nexus: metricGrid.nexus
        visible: nexus.settings.showBattery
        width: (parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns
        label: "Battery"
        percent: nexus.batteryPresent ? nexus.batteryPercent : null
        stale: false
        detail: NexusMetricsModel.batteryDetail(nexus.batteryPresent, nexus.batteryDevice ? nexus.batteryDevice.state : 0, UPower.onBattery, nexus.batteryPercent, nexus.batteryDevice ? nexus.batteryDevice.timeToEmpty : 0, nexus.batteryDevice ? nexus.batteryDevice.timeToFull : 0)
    }

}
