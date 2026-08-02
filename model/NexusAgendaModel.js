// ICS agenda model (shared engine with community.calendar-agenda; kept in sync by copy). Loaded by both the QML
// entry points and the Node test harness, so it must stay dependency-free
// (ES5 only — the QML V4 engine).
//
// Scope, deliberately: UID/SUMMARY/LOCATION/DTSTART/DTEND, RRULE
// (DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL, BYDAY incl. nth-weekday,
// BYMONTHDAY, BYMONTH, UNTIL, COUNT), EXDATE/RDATE, RECURRENCE-ID
// overrides, CANCELLED skipping, folded lines, quoted params, escaped text.
// TZID values are treated as local wall-clock time — correct for events the
// user created in their own timezone; documented limitation otherwise
// (there is no Intl in the QML engine, and toLocaleString silently returns
// wrong times rather than throwing).

function unfold(raw) {
  // RFC 5545 3.1: CRLF + single WSP is a fold. Strip exactly one WSP.
  return String(raw).replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "");
}

function splitLine(line) {
  // NAME;PARAM=v;PARAM="a:b":VALUE  -- colon inside dquotes is not the separator
  var inQuote = false;
  for (var i = 0; i < line.length; i++) {
    var c = line.charAt(i);
    if (c === '"') inQuote = !inQuote;
    else if (c === ":" && !inQuote) {
      var head = line.slice(0, i);
      var value = line.slice(i + 1);
      var parts = [], cur = "", q = false;
      for (var j = 0; j < head.length; j++) {
        var h = head.charAt(j);
        if (h === '"') { q = !q; cur += h; }
        else if (h === ";" && !q) { parts.push(cur); cur = ""; }
        else cur += h;
      }
      parts.push(cur);
      var params = {};
      for (var k = 1; k < parts.length; k++) {
        var eq = parts[k].indexOf("=");
        if (eq < 0) continue;
        params[parts[k].slice(0, eq).toUpperCase()] =
          parts[k].slice(eq + 1).replace(/^"|"$/g, "");
      }
      return { name: parts[0].toUpperCase(), params: params, value: value };
    }
  }
  return null;
}

function unescapeText(v) {
  return String(v)
    .replace(/\\n/gi, "\n")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\\\/g, "\\");
}

// ---- date handling -------------------------------------------------------
// Returns { allDay, utcMs | wall:{y,m,d,H,M,S}, tzid }
function parseIcsDate(value, params) {
  var v = String(value).trim();
  if ((params && params.VALUE === "DATE") || /^\d{8}$/.test(v)) {
    return {
      allDay: true,
      y: +v.slice(0, 4), mo: +v.slice(4, 6) - 1, d: +v.slice(6, 8),
      H: 0, M: 0, S: 0, tzid: null, utc: false
    };
  }
  var m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$/.exec(v);
  if (!m) return null;
  return {
    allDay: false,
    y: +m[1], mo: +m[2] - 1, d: +m[3], H: +m[4], M: +m[5], S: +m[6],
    utc: m[7] === "Z",
    tzid: (params && params.TZID) || null
  };
}

// Resolve to epoch ms. offsets: { "America/Los_Angeles": fn } not available in
// QML -> caller supplies a resolver. Here: UTC exact, floating/all-day = local,
// TZID = local unless resolver given.
function toEpochMs(p, tzResolver) {
  if (!p) return NaN;
  if (p.utc) return Date.UTC(p.y, p.mo, p.d, p.H, p.M, p.S);
  if (p.tzid && tzResolver) {
    var r = tzResolver(p);
    if (typeof r === "number" && !isNaN(r)) return r;
  }
  return new Date(p.y, p.mo, p.d, p.H, p.M, p.S).getTime();
}

// ---- component walk ------------------------------------------------------
function parseEvents(raw) {
  var lines = unfold(raw).split("\n");
  var events = [], cur = null, stack = [];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!line) continue;
    var p = splitLine(line);
    if (!p) continue;

    if (p.name === "BEGIN") {
      stack.push(p.value.toUpperCase());
      if (p.value.toUpperCase() === "VEVENT" && stack.length === 2) {
        cur = { summary: "", rdate: [], exdate: [], raw: {} };
      }
      continue;
    }
    if (p.name === "END") {
      var ended = stack.pop();
      if (ended === "VEVENT" && cur && stack.length === 1) { events.push(cur); cur = null; }
      continue;
    }
    // Anything nested deeper than VCALENDAR/VEVENT (VALARM, VTIMEZONE) is dropped.
    if (!cur || stack.length !== 2 || stack[1] !== "VEVENT") continue;

    switch (p.name) {
      case "UID": cur.uid = p.value; break;
      case "SUMMARY": cur.summary = unescapeText(p.value); break;
      case "LOCATION": cur.location = unescapeText(p.value); break;
      case "DESCRIPTION": cur.description = unescapeText(p.value); break;
      case "STATUS": cur.status = p.value.toUpperCase(); break;
      case "TRANSP": cur.transp = p.value.toUpperCase(); break;
      case "DTSTART": cur.dtstart = parseIcsDate(p.value, p.params); break;
      case "DTEND": cur.dtend = parseIcsDate(p.value, p.params); break;
      case "DURATION": cur.duration = p.value; break;
      case "RRULE": cur.rrule = parseRRule(p.value); break;
      case "RECURRENCE-ID": cur.recurrenceId = parseIcsDate(p.value, p.params); break;
      case "RDATE":
        p.value.split(",").forEach(function (v) {
          cur.rdate.push(parseIcsDate(v.split("/")[0], p.params));
        });
        break;
      case "EXDATE":
        p.value.split(",").forEach(function (v) {
          cur.exdate.push(parseIcsDate(v, p.params));
        });
        break;
    }
  }
  return events;
}

function parseRRule(v) {
  var out = {};
  String(v).split(";").forEach(function (kv) {
    var i = kv.indexOf("=");
    if (i < 0) return;
    out[kv.slice(0, i).toUpperCase()] = kv.slice(i + 1);
  });
  var r = {
    freq: (out.FREQ || "").toUpperCase(),
    interval: parseInt(out.INTERVAL || "1", 10) || 1,
    count: out.COUNT ? parseInt(out.COUNT, 10) : null,
    until: out.UNTIL ? parseIcsDate(out.UNTIL, {}) : null,
    byday: out.BYDAY ? out.BYDAY.split(",") : null,
    bymonthday: out.BYMONTHDAY ? out.BYMONTHDAY.split(",").map(Number) : null,
    bymonth: out.BYMONTH ? out.BYMONTH.split(",").map(Number) : null,
    wkst: out.WKST || "MO"
  };
  return r;
}

// ---- recurrence expansion ------------------------------------------------
var DAYS = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

function dayKey(d) {
  return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate();
}

// Expand occurrences of `ev` overlapping [winStart, winEnd) (epoch ms, local).
// Strategy: candidate generation by day-stepping the window, guarded by an
// iteration cap. This is O(window days) not O(occurrences since DTSTART).
function expand(ev, winStart, winEnd, tzResolver) {
  var startMs = toEpochMs(ev.dtstart, tzResolver);
  if (isNaN(startMs)) return [];

  var durMs = 0;
  if (ev.dtend) durMs = toEpochMs(ev.dtend, tzResolver) - startMs;
  if (durMs < 0) durMs = 0;

  var occ = [];
  var exSet = {};
  ev.exdate.forEach(function (x) { var t = toEpochMs(x, tzResolver); if (!isNaN(t)) exSet[t] = true; });

  function push(ms) {
    if (exSet[ms]) return;
    if (ms + Math.max(durMs, 1) <= winStart) return;
    if (ms >= winEnd) return;
    occ.push({ start: ms, end: ms + durMs, summary: ev.summary, allDay: !!ev.dtstart.allDay, uid: ev.uid });
  }

  if (!ev.rrule || !ev.rrule.freq) {
    push(startMs);
  } else {
    var r = ev.rrule;
    var untilMs = r.until ? toEpochMs(r.until, tzResolver) : null;
    // COUNT cannot be evaluated inside a window walk (the walk has no idea
    // what ordinal an occurrence is), so pre-walk from DTSTART to find the
    // COUNT-th occurrence and treat it as an UNTIL.
    if (r.count !== null && r.count > 0) {
      var countUntil = countLimitMs(ev, r, tzResolver)
      if (countUntil !== null && (untilMs === null || countUntil < untilMs)) untilMs = countUntil
    }
    var s = new Date(startMs);
    var bydaySet = null;
    if (r.byday) {
      bydaySet = {};
      r.byday.forEach(function (b) { bydaySet[b.replace(/^[-+]?\d+/, "")] = b; });
    }

    // Walk day-by-day across the window, testing the rule. Correct for
    // DAILY / WEEKLY / MONTHLY when INTERVAL counting is anchored at DTSTART.
    var cursor = new Date(winStart);
    cursor.setHours(s.getHours(), s.getMinutes(), s.getSeconds(), 0);
    // Back up one day so an occurrence starting before the window but still
    // running inside it is not missed.
    cursor.setDate(cursor.getDate() - 1);

    var guard = 0;
    var seen = 0;
    while (cursor.getTime() < winEnd && guard++ < 400) {
      var t = cursor.getTime();
      if (t >= startMs && (untilMs === null || t <= untilMs)) {
        var ok = false;
        if (r.freq === "DAILY") {
          var dayDelta = Math.round((dateOnly(cursor) - dateOnly(s)) / 86400000);
          ok = dayDelta >= 0 && dayDelta % r.interval === 0;
          if (ok && bydaySet) ok = !!bydaySet[DAYS[cursor.getDay()]];
        } else if (r.freq === "WEEKLY") {
          var wkDelta = Math.floor((weekStart(cursor, r.wkst) - weekStart(s, r.wkst)) / (7 * 86400000));
          ok = wkDelta >= 0 && wkDelta % r.interval === 0;
          if (ok) {
            ok = bydaySet ? !!bydaySet[DAYS[cursor.getDay()]]
                          : cursor.getDay() === s.getDay();
          }
        } else if (r.freq === "MONTHLY") {
          var moDelta = (cursor.getFullYear() - s.getFullYear()) * 12 + (cursor.getMonth() - s.getMonth());
          ok = moDelta >= 0 && moDelta % r.interval === 0;
          if (ok) {
            if (bydaySet) ok = matchesByDay(cursor, r.byday);
            else if (r.bymonthday) ok = r.bymonthday.indexOf(cursor.getDate()) >= 0;
            else ok = cursor.getDate() === s.getDate();
          }
        } else if (r.freq === "YEARLY") {
          ok = (cursor.getMonth() === s.getMonth() && cursor.getDate() === s.getDate() &&
                (cursor.getFullYear() - s.getFullYear()) % r.interval === 0);
        }
        if (ok && r.bymonth) ok = r.bymonth.indexOf(cursor.getMonth() + 1) >= 0;
        if (ok) push(t);
      }
      cursor.setDate(cursor.getDate() + 1);
    }
  }

  ev.rdate.forEach(function (x) { var t = toEpochMs(x, tzResolver); if (!isNaN(t)) push(t); });
  occ.sort(function (a, b) { return a.start - b.start; });
  return occ;
}

// Pre-walk from DTSTART matching the same rule tests as expand(), stopping
// at the COUNT-th occurrence; returns its epoch ms (an effective UNTIL).
function countLimitMs(ev, r, tzResolver) {
  var startMs = toEpochMs(ev.dtstart, tzResolver)
  if (isNaN(startMs)) return null
  var s = new Date(startMs)
  var bydaySet = null
  if (r.byday) {
    bydaySet = {}
    r.byday.forEach(function (b) { bydaySet[b.replace(/^[-+]?\d+/, "")] = b })
  }
  var cursor = new Date(startMs)
  var seen = 0
  var guard = 0
  while (guard++ < 40000) {
    var ok = false
    if (r.freq === "DAILY") {
      var dayDelta = Math.round((dateOnly(cursor) - dateOnly(s)) / 86400000)
      ok = dayDelta >= 0 && dayDelta % r.interval === 0
      if (ok && bydaySet) ok = !!bydaySet[DAYS[cursor.getDay()]]
    } else if (r.freq === "WEEKLY") {
      var wkDelta = Math.floor((weekStart(cursor, r.wkst) - weekStart(s, r.wkst)) / (7 * 86400000))
      ok = wkDelta >= 0 && wkDelta % r.interval === 0
      if (ok) ok = bydaySet ? !!bydaySet[DAYS[cursor.getDay()]] : cursor.getDay() === s.getDay()
    } else if (r.freq === "MONTHLY") {
      var moDelta = (cursor.getFullYear() - s.getFullYear()) * 12 + (cursor.getMonth() - s.getMonth())
      ok = moDelta >= 0 && moDelta % r.interval === 0
      if (ok) {
        if (bydaySet) ok = matchesByDay(cursor, r.byday)
        else if (r.bymonthday) ok = r.bymonthday.indexOf(cursor.getDate()) >= 0
        else ok = cursor.getDate() === s.getDate()
      }
    } else if (r.freq === "YEARLY") {
      ok = (cursor.getMonth() === s.getMonth() && cursor.getDate() === s.getDate()
        && (cursor.getFullYear() - s.getFullYear()) % r.interval === 0)
    } else {
      return null
    }
    if (ok && r.bymonth) ok = r.bymonth.indexOf(cursor.getMonth() + 1) >= 0
    if (ok) {
      seen += 1
      if (seen >= r.count) return cursor.getTime()
    }
    cursor.setDate(cursor.getDate() + 1)
  }
  return null
}

function dateOnly(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }
function weekStart(d, wkst) {
  var w = DAYS.indexOf(String(wkst).toUpperCase());
  if (w < 0) w = 1;
  var x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  x.setDate(x.getDate() - ((x.getDay() - w + 7) % 7));
  return x.getTime();
}
function matchesByDay(cursor, byday) {
  for (var i = 0; i < byday.length; i++) {
    var m = /^([-+]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$/.exec(byday[i]);
    if (!m) continue;
    if (DAYS[cursor.getDay()] !== m[2]) continue;
    if (!m[1]) return true;
    var n = parseInt(m[1], 10);
    if (n > 0) {
      if (Math.floor((cursor.getDate() - 1) / 7) + 1 === n) return true;
    } else {
      var last = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0).getDate();
      if (Math.floor((last - cursor.getDate()) / 7) + 1 === -n) return true;
    }
  }
  return false;
}

function agenda(raw, days, now) {
  var events = parseEvents(raw);
  var winStart = new Date(now); winStart.setHours(0, 0, 0, 0);
  var winEnd = new Date(winStart); winEnd.setDate(winEnd.getDate() + days);

  // RECURRENCE-ID overrides: index by uid+recurrence start.
  var overrides = {};
  events.forEach(function (e) {
    if (e.recurrenceId) overrides[e.uid + "|" + toEpochMs(e.recurrenceId)] = e;
  });

  var out = [];
  events.forEach(function (e) {
    if (e.recurrenceId) return; // handled as override
    if (e.status === "CANCELLED") return;
    expand(e, winStart.getTime(), winEnd.getTime()).forEach(function (o) {
      var ov = overrides[e.uid + "|" + o.start];
      if (ov) {
        var s = toEpochMs(ov.dtstart);
        out.push({ start: s, end: ov.dtend ? toEpochMs(ov.dtend) : s, summary: ov.summary, allDay: !!ov.dtstart.allDay, uid: ov.uid, overridden: true });
      } else out.push(o);
    });
  });
  // Overrides whose base occurrence fell outside the window but which moved in
  events.forEach(function (e) {
    if (!e.recurrenceId) return;
    var s = toEpochMs(e.dtstart);
    if (s >= winStart.getTime() && s < winEnd.getTime() &&
        !out.some(function (o) { return o.uid === e.uid && o.start === s; })) {
      out.push({ start: s, end: e.dtend ? toEpochMs(e.dtend) : s, summary: e.summary, allDay: !!e.dtstart.allDay, uid: e.uid, overridden: true });
    }
  });
  out.sort(function (a, b) { return a.start - b.start || (a.allDay ? -1 : 1); });
  return out;
}

// ---- plugin-facing helpers -------------------------------------------------

var DEFAULT_REFRESH_MINUTES = 30
var AGENDA_DAYS = 14

function normalizeUrls(value) {
  var list = value
  if (typeof list === "string") {
    var trimmed = list.trim()
    if (trimmed.indexOf("[") === 0) {
      try { list = JSON.parse(trimmed) } catch (error) { list = [] }
    } else {
      list = [trimmed]
    }
  }
  if (!list || typeof list.length !== "number") return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var url = String(list[i] == null ? "" : list[i]).trim()
    if (/^https?:\/\/.+/.test(url) || /^webcal:\/\/.+/.test(url)) {
      out.push(url.replace(/^webcal:\/\//, "https://"))
    }
  }
  return out
}

function fetchCommand(url) {
  return ["curl", "-fsSL", "--max-time", "15", url]
}

function stateDir(xdgStateHome, home) {
  var base = typeof xdgStateHome === "string" && xdgStateHome.trim().length > 0
    ? xdgStateHome.trim()
    : String(home == null ? "" : home) + "/.local/state"
  return base + "/omarchy/calendar"
}

function cachePath(dir, index) {
  return dir + "/calendar-" + index + ".ics"
}

// Merge occurrences from several calendars into one sorted agenda.
function mergeAgendas(rawTexts, days, nowMs) {
  var out = []
  for (var i = 0; i < (rawTexts ? rawTexts.length : 0); i++) {
    var text = rawTexts[i]
    if (typeof text !== "string" || text.indexOf("BEGIN:VCALENDAR") === -1) continue
    out = out.concat(agenda(text, days, nowMs))
  }
  out.sort(function (a, b) { return a.start - b.start || (a.allDay === b.allDay ? 0 : (a.allDay ? -1 : 1)) })
  return out
}

function upcoming(occurrences, nowMs) {
  var list = occurrences || []
  for (var i = 0; i < list.length; i++) {
    if (!list[i].allDay && list[i].end > nowMs) return list[i]
    if (!list[i].allDay && list[i].start > nowMs) return list[i]
  }
  return null
}

function countdownLabel(occurrence, nowMs) {
  if (!occurrence) return ""
  var deltaMinutes = Math.round((occurrence.start - Number(nowMs)) / 60000)
  var name = occurrence.summary || "(untitled)"
  if (deltaMinutes <= 0) return name + " · now"
  if (deltaMinutes < 60) return name + " · in " + deltaMinutes + " m"
  if (deltaMinutes < 24 * 60) {
    var hours = Math.floor(deltaMinutes / 60)
    var minutes = deltaMinutes % 60
    return name + " · in " + hours + " h" + (minutes > 0 ? " " + minutes + " m" : "")
  }
  return name + " · in " + Math.round(deltaMinutes / 1440) + " d"
}

// Group occurrences by calendar day for the panel.
function groupByDay(occurrences, nowMs) {
  var groups = []
  var byKey = {}
  var todayKey = localDayKey(new Date(Number(nowMs)))
  var tomorrowKey = localDayKey(new Date(Number(nowMs) + 86400000))
  var list = occurrences || []
  for (var i = 0; i < list.length; i++) {
    var start = new Date(list[i].start)
    var key = localDayKey(start)
    if (!byKey[key]) {
      var label = key === todayKey ? "Today"
        : (key === tomorrowKey ? "Tomorrow"
          : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][start.getDay()]
            + " " + start.getDate() + "." + (start.getMonth() + 1) + ".")
      byKey[key] = { key: key, label: label, items: [] }
      groups.push(byKey[key])
    }
    byKey[key].items.push(list[i])
  }
  return groups
}

function localDayKey(d) {
  var pad = function (n) { return n < 10 ? "0" + n : String(n) }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function formatEventTime(occurrence) {
  if (!occurrence || occurrence.allDay) return "All day"
  var pad = function (n) { return n < 10 ? "0" + n : String(n) }
  var start = new Date(occurrence.start)
  var text = pad(start.getHours()) + ":" + pad(start.getMinutes())
  if (occurrence.end > occurrence.start) {
    var end = new Date(occurrence.end)
    text += "–" + pad(end.getHours()) + ":" + pad(end.getMinutes())
  }
  return text
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_REFRESH_MINUTES: DEFAULT_REFRESH_MINUTES,
    AGENDA_DAYS: AGENDA_DAYS,
    unfold: unfold,
    splitLine: splitLine,
    parseIcsDate: parseIcsDate,
    parseEvents: parseEvents,
    parseRRule: parseRRule,
    expand: expand,
    agenda: agenda,
    matchesByDay: matchesByDay,
    countLimitMs: countLimitMs,
    normalizeUrls: normalizeUrls,
    fetchCommand: fetchCommand,
    stateDir: stateDir,
    cachePath: cachePath,
    mergeAgendas: mergeAgendas,
    upcoming: upcoming,
    countdownLabel: countdownLabel,
    groupByDay: groupByDay,
    formatEventTime: formatEventTime
  }
}
