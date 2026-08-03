// WCAG relative-luminance contrast picking. Label colors on themed fills
// are computed, never hardcoded: whichever candidate reads better wins,
// so no theme can produce an unreadable badge. Dependency-free; loaded by
// both QML and the Node test harness. Channels are 0..1 floats (QML
// color.r/g/b).

function linearChannel(c) {
  var v = Number(c)
  if (!isFinite(v)) v = 0
  if (v < 0) v = 0
  if (v > 1) v = 1
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

function relativeLuminance(r, g, b) {
  return 0.2126 * linearChannel(r) + 0.7152 * linearChannel(g) + 0.0722 * linearChannel(b)
}

function contrastRatio(lumA, lumB) {
  var lighter = Math.max(lumA, lumB)
  var darker = Math.min(lumA, lumB)
  return (lighter + 0.05) / (darker + 0.05)
}

// Index of the candidate with the highest contrast against the fill.
// Candidates and fill are {r, g, b} objects (a QML color qualifies).
function readableIndex(fill, candidates) {
  var list = candidates && typeof candidates.length === "number" ? candidates : []
  if (list.length === 0) return -1
  var fillLum = relativeLuminance(fill ? fill.r : 0, fill ? fill.g : 0, fill ? fill.b : 0)
  var best = 0
  var bestRatio = -1
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c) continue
    var ratio = contrastRatio(fillLum, relativeLuminance(c.r, c.g, c.b))
    if (ratio > bestRatio) { bestRatio = ratio; best = i }
  }
  return best
}

if (typeof module !== "undefined") {
  module.exports = {
    linearChannel: linearChannel,
    relativeLuminance: relativeLuminance,
    contrastRatio: contrastRatio,
    readableIndex: readableIndex
  }
}
