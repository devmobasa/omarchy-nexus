// Game-mode flag model for Omarchy Nexus. Loaded by both the QML entry
// point and the Node test harness, so it must stay dependency-free.
//
// Nexus shares one flag file with the community.game-mode bar widget: the
// same basename in the same sourced Hyprland toggles directory (the
// mechanism behind omarchy-hyprland-toggle). File present = stripped
// effects; file absent = the user's own configuration, exactly. Either
// controller may write or remove it; both watch it, so they never disagree.

var FLAG_BASENAME = "community-game-mode.lua"

function stateDir(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/toggles/hypr"
}

function flagPath(xdgStateHome, home) {
  return stateDir(xdgStateHome, home) + "/" + FLAG_BASENAME
}

// Build the Lua flag from the configured strip set (the gm* settings).
// Returns null when nothing is selected, so the caller disables the toggle
// instead of writing a flag that strips nothing.
function buildFlagContent(options) {
  var o = options || {}
  var body = []

  if (o.gmAnimations) {
    body = body.concat(["  animations = {", "    enabled = false,", "  },", ""])
  }

  var general = []
  if (o.gmGaps) general = general.concat(["    gaps_in = 0,", "    gaps_out = 0,"])
  if (o.gmTearing) general.push("    allow_tearing = true,")
  if (general.length > 0) {
    body = body.concat(["  general = {"], general, ["  },", ""])
  }

  var decoration = []
  if (o.gmRounding) decoration.push("    rounding = 0,")
  if (o.gmBlur) decoration = decoration.concat(["    blur = {", "      enabled = false,", "    },"])
  if (o.gmShadows) decoration = decoration.concat(["    shadow = {", "      enabled = false,", "    },"])
  if (decoration.length > 0) {
    body = body.concat(["  decoration = {"], decoration, ["  },", ""])
  }

  if (body.length === 0) return null
  // Drop the trailing blank spacer line before closing the table.
  if (body[body.length - 1] === "") body = body.slice(0, body.length - 1)

  return [
    "-- Omarchy game mode (written by Omarchy Nexus; shared with the",
    "-- community.game-mode bar widget). Deleting this file (or toggling",
    "-- game mode off) restores your own configuration exactly.",
    "hl.config({"
  ].concat(body, ["})", ""]).join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    FLAG_BASENAME: FLAG_BASENAME,
    stateDir: stateDir,
    flagPath: flagPath,
    buildFlagContent: buildFlagContent
  }
}
