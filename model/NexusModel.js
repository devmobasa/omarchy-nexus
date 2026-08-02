// Pure page and payload model for Omarchy Nexus. Loaded by both the QML
// entry point and the Node test harness, so it must stay dependency-free.

// "settings" is a full page (payloads and Tab cycling reach it) but renders
// in the tab row as the trailing cog rather than a labelled tab. Pages with
// an icon render icon-only in the tab row to keep it inside the card width.
var PAGES = ["overview", "media", "controls", "style", "keys", "notes", "alerts", "settings"]
var DEFAULT_PAGE = "overview"

var PAGE_TITLES = {
  overview: "Overview",
  media: "Media",
  controls: "Controls",
  style: "Style",
  keys: "Keys",
  notes: "Notes",
  alerts: "Alerts",
  settings: "Settings"
}

var PAGE_ICONS = {
  media: "󰎈",
  keys: "󰌌",
  notes: "󰎞",
  alerts: "󰂚"
}

// Pages with real content use the empty string: the panel hides the
// placeholder row entirely for them. All pages now have content; future
// expansion pages can reuse this mechanism.
var PAGE_PLACEHOLDERS = {
  overview: "",
  media: "",
  controls: "",
  style: "",
  keys: "",
  notes: "",
  alerts: "",
  settings: ""
}

// The labelled tabs; the settings page is reached via the cog, Tab cycling,
// or a payload.
function tabPages() {
  var tabs = []
  for (var i = 0; i < PAGES.length; i++) {
    if (PAGES[i] !== "settings") tabs.push(PAGES[i])
  }
  return tabs
}

// The host delivers the summon payload verbatim (any string, possibly not
// JSON) and ignores open()'s return value, so normalization can never refuse:
// every input maps to a valid page. Only the whitelisted page field is read;
// arrays, primitives, malformed JSON, and unknown fields normalize away.
// fallbackPage (the validated defaultPage setting) applies only when the
// payload names no valid page; an explicit payload page always wins.
function normalizePayload(payloadJson, fallbackPage) {
  var parsed = null
  if (typeof payloadJson === "string" && payloadJson.length > 0) {
    try {
      parsed = JSON.parse(payloadJson)
    } catch (error) {
      parsed = null
    }
  } else if (payloadJson && typeof payloadJson === "object") {
    parsed = payloadJson
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) parsed = {}

  var page = typeof fallbackPage === "string" && PAGES.indexOf(fallbackPage) !== -1
    ? fallbackPage : DEFAULT_PAGE
  if (typeof parsed.page === "string" && PAGES.indexOf(parsed.page) !== -1) page = parsed.page
  return { page: page }
}

function adjacentPage(page, delta) {
  var index = PAGES.indexOf(page)
  if (index === -1) return DEFAULT_PAGE
  return PAGES[(index + delta + PAGES.length) % PAGES.length]
}

function pageTitle(page) {
  return PAGE_TITLES[page] || PAGE_TITLES[DEFAULT_PAGE]
}

// Icon for icon-only tabs; empty string means a labelled tab.
function pageIcon(page) {
  return PAGE_ICONS[page] || ""
}

function pagePlaceholder(page) {
  return PAGE_PLACEHOLDERS[page] || PAGE_PLACEHOLDERS[DEFAULT_PAGE]
}

if (typeof module !== "undefined") {
  module.exports = {
    PAGES: PAGES,
    DEFAULT_PAGE: DEFAULT_PAGE,
    tabPages: tabPages,
    normalizePayload: normalizePayload,
    adjacentPage: adjacentPage,
    pageTitle: pageTitle,
    pageIcon: pageIcon,
    pagePlaceholder: pagePlaceholder
  }
}
