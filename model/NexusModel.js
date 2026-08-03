// Pure page and payload model for Omarchy Nexus. Loaded by both the QML
// entry point and the Node test harness, so it must stay dependency-free.

// Page identifiers. The QML layer references these constants, never the
// raw strings; the string values are the payload/schema contract.
var PAGE_OVERVIEW = "overview"
var PAGE_MEDIA = "media"
var PAGE_CONTROLS = "controls"
var PAGE_STYLE = "style"
var PAGE_KEYS = "keys"
var PAGE_NOTES = "notes"
var PAGE_ALERTS = "alerts"
var PAGE_CLIPBOARD = "clipboard"
var PAGE_MINIMIZER = "minimizer"
var PAGE_SETTINGS = "settings"

// "settings" is a full page (payloads and Tab cycling reach it) but renders
// in the tab row as the trailing cog rather than a labelled tab. Pages with
// an icon render icon-only in the tab row to keep it inside the card width.
// PAGE_KEYS is parked: its page stays mounted but unlisted, so no tab,
// cycling stop, or payload can reach it until it is re-added here.
var PAGES = [PAGE_OVERVIEW, PAGE_MEDIA, PAGE_CONTROLS, PAGE_STYLE,
  PAGE_NOTES, PAGE_CLIPBOARD, PAGE_MINIMIZER, PAGE_ALERTS,
  PAGE_SETTINGS]
var DEFAULT_PAGE = PAGE_OVERVIEW

// Keyboard cursor rows, one map per page that has fixed rows (the settings
// and media pages derive their row count from data).
var CONTROLS_ROWS = {
  VOLUME: 0, MUTE: 1, MICROPHONE: 2, DND: 3, NIGHT_LIGHT: 4,
  STAY_AWAKE: 5, BLUETOOTH: 6, GAME_MODE: 7, POMODORO: 8,
  CAPTURE: 9, POWER: 10
}
var CONTROLS_LAST_ROW = CONTROLS_ROWS.POWER

var OVERVIEW_ROWS = { TRANSPORT: 0, SEEK: 1, PLAYER_CHIP: 2 }
// WALLPAPERS is conditional: the row exists only while community.wallpaper-hub
// is installed and enabled (the facade's lastCursorIndex reflects that).
var STYLE_ROWS = { THEME: 0, BACKGROUND: 1, WALLPAPERS: 2 }

// Fixed Omarchy menu routes for delegated actions.
var MENU_ROUTES = {
  theme: "style.theme",
  background: "style.background",
  capture: "trigger.capture",
  power: "system"
}

var PAGE_TITLES = {}
PAGE_TITLES[PAGE_OVERVIEW] = "Overview"
PAGE_TITLES[PAGE_MEDIA] = "Media"
PAGE_TITLES[PAGE_CONTROLS] = "Controls"
PAGE_TITLES[PAGE_STYLE] = "Style"
PAGE_TITLES[PAGE_KEYS] = "Keys"
PAGE_TITLES[PAGE_NOTES] = "Notes"
PAGE_TITLES[PAGE_ALERTS] = "Alerts"
PAGE_TITLES[PAGE_CLIPBOARD] = "Clipboard"
PAGE_TITLES[PAGE_MINIMIZER] = "Minimizer"
PAGE_TITLES[PAGE_SETTINGS] = "Settings"

// Every page has an icon: the tab row renders icon-only (uniform, fits the
// card at any page count) with the title as tooltip.
var PAGE_ICONS = {}
PAGE_ICONS[PAGE_OVERVIEW] = "󰋜"
PAGE_ICONS[PAGE_MEDIA] = "󰎈"
PAGE_ICONS[PAGE_CONTROLS] = "󰘮"
PAGE_ICONS[PAGE_STYLE] = "󰸌"
PAGE_ICONS[PAGE_KEYS] = "󰌌"
PAGE_ICONS[PAGE_NOTES] = "󰎞"
PAGE_ICONS[PAGE_ALERTS] = "󰂚"
PAGE_ICONS[PAGE_CLIPBOARD] = "󰅍"
PAGE_ICONS[PAGE_MINIMIZER] = "󰖰"
PAGE_ICONS[PAGE_SETTINGS] = "󰒓"

// Pages with real content use the empty string: the panel hides the
// placeholder row entirely for them. All pages now have content; future
// expansion pages can reuse this mechanism.
var PAGE_PLACEHOLDERS = {}
for (var placeholderIndex = 0; placeholderIndex < PAGES.length; placeholderIndex++) {
  PAGE_PLACEHOLDERS[PAGES[placeholderIndex]] = ""
}

// The labelled tabs; the settings page is reached via the cog, Tab cycling,
// or a payload.
function tabPages() {
  var tabs = []
  for (var i = 0; i < PAGES.length; i++) {
    if (PAGES[i] !== PAGE_SETTINGS) tabs.push(PAGES[i])
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
    PAGE_OVERVIEW: PAGE_OVERVIEW,
    PAGE_MEDIA: PAGE_MEDIA,
    PAGE_CONTROLS: PAGE_CONTROLS,
    PAGE_STYLE: PAGE_STYLE,
    PAGE_KEYS: PAGE_KEYS,
    PAGE_NOTES: PAGE_NOTES,
    PAGE_ALERTS: PAGE_ALERTS,
    PAGE_CLIPBOARD: PAGE_CLIPBOARD,
    PAGE_MINIMIZER: PAGE_MINIMIZER,
    PAGE_SETTINGS: PAGE_SETTINGS,
    CONTROLS_ROWS: CONTROLS_ROWS,
    CONTROLS_LAST_ROW: CONTROLS_LAST_ROW,
    OVERVIEW_ROWS: OVERVIEW_ROWS,
    STYLE_ROWS: STYLE_ROWS,
    MENU_ROUTES: MENU_ROUTES,
    tabPages: tabPages,
    normalizePayload: normalizePayload,
    adjacentPage: adjacentPage,
    pageTitle: pageTitle,
    pageIcon: pageIcon,
    pagePlaceholder: pagePlaceholder
  }
}
