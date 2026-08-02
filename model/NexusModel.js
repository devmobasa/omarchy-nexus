// Pure page and payload model for Omarchy Nexus. Loaded by both the QML
// entry point and the Node test harness, so it must stay dependency-free.

var PAGES = ["overview", "controls", "style"]
var DEFAULT_PAGE = "overview"

var PAGE_TITLES = {
  overview: "Overview",
  controls: "Controls",
  style: "Style"
}

// Pages with real content use the empty string: the panel hides the
// placeholder row entirely for them.
var PAGE_PLACEHOLDERS = {
  overview: "",
  controls: "Audio, microphone, DND, night light, and stay awake land here in Milestone 3.",
  style: "Wallpaper and theme selectors land here in Milestone 3."
}

// The host delivers the summon payload verbatim (any string, possibly not
// JSON) and ignores open()'s return value, so normalization can never refuse:
// every input maps to a valid page. Only the whitelisted page field is read;
// arrays, primitives, malformed JSON, and unknown fields normalize away.
function normalizePayload(payloadJson) {
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

  var page = DEFAULT_PAGE
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

function pagePlaceholder(page) {
  return PAGE_PLACEHOLDERS[page] || PAGE_PLACEHOLDERS[DEFAULT_PAGE]
}

if (typeof module !== "undefined") {
  module.exports = {
    PAGES: PAGES,
    DEFAULT_PAGE: DEFAULT_PAGE,
    normalizePayload: normalizePayload,
    adjacentPage: adjacentPage,
    pageTitle: pageTitle,
    pagePlaceholder: pagePlaceholder
  }
}
