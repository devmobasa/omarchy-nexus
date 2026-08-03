import QtQuick
import Quickshell
import "model/NexusModel.js" as NexusModel
import "model/NexusAlertsModel.js" as NexusAlertsModel
import "model/NexusAudioModel.js" as NexusAudioModel
import "model/NexusBarModel.js" as NexusBarModel
import "model/NexusBrightnessModel.js" as NexusBrightnessModel
import "model/NexusCavaModel.js" as NexusCavaModel
import "model/NexusContrastModel.js" as NexusContrastModel
import "model/NexusDiagnosticsModel.js" as NexusDiagnosticsModel
import "model/NexusLatencyModel.js" as NexusLatencyModel
import "model/NexusMinimizerModel.js" as NexusMinimizerModel
import "model/NexusPaletteModel.js" as NexusPaletteModel
import "model/NexusSuiteModel.js" as NexusSuiteModel

// Loads every model in the REAL QML JS engine — node's V8 accepts syntax
// (lookbehind, newer ES) that Qt's engine may not, and only this catches
// the difference before a deploy does.
ShellRoot {
    Component.onCompleted: {
        let failures = 0;
        function check(name, ok) {
            if (!ok) {
                console.error("smoke FAIL:", name);
                failures++;
            }
        }
        check("pages", NexusModel.PAGES.length === 10);
        check("alerts", NexusAlertsModel.unitCommand("restart", "user", "x.service").length === 5);
        check("audio", NexusAudioModel.peakToMeter(1) === 1);
        check("bar", NexusBarModel.nextSection("right") === "left");
        check("brightness", NexusBrightnessModel.clampBrightness(150) === 100);
        check("cava", NexusCavaModel.retryDelay(2) === 1000);
        check("contrast", NexusContrastModel.readableIndex({ "r": 0, "g": 0, "b": 0 }, [{ "r": 1, "g": 1, "b": 1 }]) === 0);
        check("diagnostics", NexusDiagnosticsModel.scanLog("WARN: TypeError: x").length === 1);
        check("latency", NexusLatencyModel.parsePing("time=1.5 ms") === 1.5);
        check("minimizer", NexusMinimizerModel.closeDispatch("0xabc").indexOf("close") !== -1);
        check("palette", NexusPaletteModel.filterEntries([{ "title": "Night", "subtitle": "" }], "ni", 5).length === 1);
        check("suite", NexusSuiteModel.pendingCount("{\"pending\":[1]}") === 1);
        console.info(failures === 0 ? "ok - qml engine smoke" : "FAILED - qml engine smoke");
        Qt.exit(failures === 0 ? 0 : 1);
    }
}
