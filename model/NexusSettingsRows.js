// Declarative Settings-page row metadata. Kept outside the plugin facade so
// navigation policy can consume one stable, ordered list.
function rows() {
  return [
    { key: "showMedia", label: "Media card", desc: "Artwork, transport, and seek bar on Overview." },
    { key: "showMetrics", label: "Metric meters", desc: "Master switch for the arc meters and network card." },
    { key: "showCpu", label: "CPU meter", desc: "" },
    { key: "showMemory", label: "Memory meter", desc: "" },
    { key: "showStorage", label: "Storage meter", desc: "" },
    { key: "showBattery", label: "Battery meter", desc: "Hide on desktops without a battery." },
    { key: "showNetwork", label: "Network card", desc: "Live down/up throughput sparkline." },
    { key: "showSensors", label: "Sensors card", desc: "CPU/GPU/NVMe temperatures and fans." },
    { key: "showVisualizer", label: "Audio visualizer", desc: "Spectrum bars while media plays (needs cava installed)." },
    { key: "showScreenTime", label: "Screen time card", desc: "Today's focused time (needs community.screen-time)." },
    { key: "showNextEvent", label: "Next event line", desc: "Calendar countdown in the hero (needs community.calendar-agenda)." },
    { key: "showFetch", label: "System info line", desc: "hostname · kernel · uptime under the clock." },
    { key: "gmAnimations", label: "Animations", desc: "", section: "game" },
    { key: "gmBlur", label: "Blur", desc: "", section: "game" },
    { key: "gmShadows", label: "Shadows", desc: "", section: "game" },
    { key: "gmGaps", label: "Gaps", desc: "", section: "game" },
    { key: "gmRounding", label: "Rounding", desc: "", section: "game" },
    { key: "gmTearing", label: "Allow tearing", desc: "Master tearing switch; windowed games may also need an immediate window rule.", section: "game" }
  ]
}

if (typeof module !== "undefined") module.exports = { rows: rows }
