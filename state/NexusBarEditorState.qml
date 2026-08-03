import "../model/NexusBarModel.js" as NexusBarModel
import QtQuick

// Bar editor state: reactive views over the host's bar layout, mutations
// through the host's pluginRegistry — the registry preserves inline
// settings on moves, validates placement, and owns the clone/disabled
// bookkeeping. Relative before/after placement is used everywhere, so the
// post-removal index semantics of numeric targets never apply.
Item {
    id: state

    required property var nexus
    property string editError: ""
    readonly property var registry: nexus.pluginRegistry
    readonly property var barLayout: {
        if (registry) {
            const revision = registry.registryRevision;
        }
        const config = nexus.shell && nexus.shell.shellConfig ? nexus.shell.shellConfig.bar : null;
        return NexusBarModel.layoutFrom(config);
    }
    readonly property var barRows: NexusBarModel.displayRows(barLayout, registry ? registry.installedPlugins : {})
    readonly property var availableWidgets: NexusBarModel.availableWidgets(registry ? registry.installedPlugins : {}, barLayout)
    readonly property bool editable: registry !== null && typeof (registry ? registry.moveBarWidget : undefined) === "function"

    function applyResult(error) {
        editError = typeof error === "string" ? error : "";
    }

    function moveRowUp(row) {
        if (!editable || !row || row.first || row.locked)
            return ;

        applyResult(registry.moveBarWidget(row.id, {
            "fromSection": row.section,
            "fromIndex": row.index,
            "section": row.section,
            "before": row.prevId
        }));
    }

    function moveRowDown(row) {
        if (!editable || !row || row.last || row.locked)
            return ;

        applyResult(registry.moveBarWidget(row.id, {
            "fromSection": row.section,
            "fromIndex": row.index,
            "section": row.section,
            "after": row.nextId
        }));
    }

    function moveRowSection(row) {
        if (!editable || !row || row.locked)
            return ;

        applyResult(registry.moveBarWidget(row.id, {
            "fromSection": row.section,
            "fromIndex": row.index,
            "section": NexusBarModel.nextSection(row.section)
        }));
    }

    function removeRow(row) {
        if (!editable || !row || row.locked)
            return ;

        const error = registry.setEnabled(row.id, false);
        applyResult(typeof error === "string" ? error : "");
    }

    function addWidget(id) {
        if (!editable || typeof id !== "string" || id.length === 0)
            return ;

        const error = registry.setEnabled(id, true);
        applyResult(typeof error === "string" ? error : "");
    }

    function resetSession() {
        editError = "";
    }

}
