.pragma library

// The panel's logic. No QML in here: tests/model-check.mjs runs this file under
// plain Node, and the QML side only draws and wires.
//
// The panel never reads a plugin's files. It reads two things, both as data:
// the projection `lib/catalog.sh list` prints, and the JSON report
// `omarchy-plugin-audit --json` prints. Every command it starts is a fixed,
// absolute argv built here -- no shell string, no PATH lookup.

var SW = "/run/current-system/sw/bin/"
var BASH = SW + "bash"

var Glyph = {
  verified: "✔",     // ✔ verified snapshot, upstream matches
  snapshot: "◐",     // ◐ snapshot verified, newer upstream unverified
  unverified: "·",   // · no automated check on record
  star: "★",
  search: String.fromCodePoint(0xF0349),
  plugin: String.fromCodePoint(0xF0431)
}

// One list of keys, shown by the shortcut sheet and matched by the view.
var SHORTCUTS = [
  { group: "List", keys: "type", what: "search name, author, tag, category" },
  { group: "List", keys: "↑ ↓  Ctrl+K Ctrl+J", what: "move" },
  { group: "List", keys: "Enter", what: "details and audit" },
  { group: "List", keys: "Ctrl+R", what: "refresh the catalog" },
  { group: "List", keys: "Esc", what: "clear the search, then close" },
  { group: "Details", keys: "a", what: "audit again" },
  { group: "Details", keys: "e", what: "explain with your default agent (terminal)" },
  { group: "Details", keys: "f", what: "fix a copy with your default agent (terminal)" },
  { group: "Details", keys: "i", what: "install, disabled (asks y/n)" },
  { group: "Details", keys: "c", what: "copy the install command" },
  { group: "Details", keys: "o", what: "open the repository" },
  { group: "Details", keys: "j k", what: "scroll the report" },
  { group: "Details", keys: "Esc  ←", what: "back to the list" },
  { group: "Anywhere", keys: "?", what: "this sheet" },
  { group: "Anywhere", keys: "Super+Alt+U", what: "open or close the browser" }
]

var ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

function isSafeId(id) {
  return typeof id === "string" && ID_RE.test(id)
}

// Display text from the catalog or a report: a string, no control characters,
// capped. Shown with Text.PlainText as well; this only keeps layouts sane.
function clean(value, max) {
  var s = value === undefined || value === null ? "" : String(value)
  s = s.replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, " ")
  return s.length > (max || 400) ? s.slice(0, (max || 400) - 1) + "…" : s
}

// `omarchy-shell shell toggle <id> '<json>'`: {"id": ...} opens that plugin's
// details, {"query": ...} opens with a search typed. Anything else is {}.
function parsePayload(json) {
  var p
  try { p = JSON.parse(String(json || "{}")) } catch (e) { return {} }
  if (!p || typeof p !== "object") return {}
  var out = {}
  if (isSafeId(p.id)) out.id = p.id
  if (typeof p.query === "string") out.query = clean(p.query, 80)
  return out
}

// Parse the catalog projection once; keep only rows with a safe id, and give
// each a lower-case haystack so a keystroke is one indexOf per row.
function parseRows(text) {
  var data
  try { data = JSON.parse(String(text || "[]")) } catch (e) { return null }
  if (!Array.isArray(data)) return null
  var rows = []
  for (var i = 0; i < data.length; i++) {
    var r = data[i]
    if (!r || !isSafeId(r.id)) continue
    var tags = Array.isArray(r.tags) ? r.tags.map(function(t) { return clean(t, 40) }) : []
    var row = {
      id: r.id, name: clean(r.name || r.id, 80), author: clean(r.author, 60),
      category: clean(r.category, 40), stars: Number(r.stars) || 0, tags: tags,
      badge: (r.badge === "verified" || r.badge === "snapshot") ? r.badge : "unverified",
      description: clean(r.description, 600), repo: clean(r.repo, 200),
      installCommand: clean(r.installCommand, 300), installAvailable: r.installAvailable === true
    }
    row.hay = [row.name, row.id, row.author, row.category, tags.join(" ")].join("\n").toLowerCase()
    rows.push(row)
  }
  return rows
}

// Every whitespace-separated term must appear somewhere; order is kept (the
// projection is already most-starred first).
function filterRows(rows, query) {
  var terms = String(query || "").toLowerCase().split(/\s+/).filter(function(t) { return t.length > 0 })
  if (terms.length === 0) return rows
  return rows.filter(function(r) {
    for (var i = 0; i < terms.length; i++) if (r.hay.indexOf(terms[i]) < 0) return false
    return true
  })
}

function badgeGlyph(badge) {
  return Glyph[badge] || Glyph.unverified
}

// Words and a tone for the two verdicts the audit reports.
function verdictLabel(outcome) {
  switch (outcome) {
    case "passed": return { text: "passed", tone: "good" }
    case "review-required": return { text: "review required", tone: "warn" }
    case "needs-fixes": return { text: "needs fixes", tone: "bad" }
    default: return { text: "unknown", tone: "dim" }
  }
}
function nixLabel(verdict) {
  switch (verdict) {
    case "likely-ok": return { text: "likely ok on NixOS", tone: "good" }
    case "needs-review": return { text: "needs review on NixOS", tone: "warn" }
    case "blocked": return { text: "blocked on NixOS", tone: "bad" }
    default: return { text: "NixOS: unknown", tone: "dim" }
  }
}

function parseReport(text) {
  try {
    var r = JSON.parse(String(text || ""))
    return r && typeof r === "object" && typeof r.outcome === "string" ? r : null
  } catch (e) { return null }
}

function lastLines(text, n) {
  var lines = String(text || "").replace(/\u001b\[[0-9;]*[A-Za-z]/g, "").split("\n")
    .filter(function(l) { return l.trim().length > 0 })
  return lines.slice(-n).map(function(l) { return clean(l, 200) }).join("\n")
}

// ---- argv (root = this plugin's folder; id already checked) ----------------
function catalogArgv(root, refresh) {
  var a = [BASH, root + "/lib/catalog.sh", "list"]
  if (refresh) a.push("--refresh")
  return a
}
function auditArgv(root, id) {
  return [BASH, root + "/bin/omarchy-plugin-audit", id, "--json"]
}
function installArgv(root, id) {
  return [BASH, root + "/bin/omarchy-plugin-audit", id, "--install"]
}
// The agent is interactive, and nixarchy-plugin-fix needs a TTY and asks its
// own questions, so it runs in a floating terminal.
function agentArgv(root, id, mode) {
  return [SW + "omarchy-launch-tui", "--app-id=TUI.float",
          BASH, root + "/bin/nixarchy-plugin-fix", id, "--mode", mode === "fix" ? "fix" : "explain"]
}
function copyArgv(text) {
  return [SW + "wl-copy", "--", String(text)]
}
function openArgv(repo) {
  return /^https:\/\/github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/?$/.test(repo)
    ? [SW + "omarchy", "launch", "browser", repo] : null
}
function toggleArgv(id) {
  return [SW + "omarchy-shell", "shell", "toggle", id, "{}"]
}
function tuiArgv(root) {
  return [SW + "xdg-terminal-exec", "--app-id=" + "io.github.olafkfreund.nixarchy-plugin-browser",
          "--title=Plugin Browser", "-e", BASH, root + "/bin/omarchy-plugin-browser"]
}

// The detail pane's report as flat lines ({text, tone, indent}), so the view
// only repeats them. Evidence strings come from the plugin's own files: they
// are cleaned and capped here and drawn as plain text.
function reportLines(report) {
  if (!report) return []
  var out = []
  function add(text, tone, indent) { out.push({ text: clean(text, 220), tone: tone || "", indent: indent || 0 }) }
  var sec = verdictLabel(report.outcome)
  add("Security: " + sec.text + (report.manifestValidate === "fail" ? " · manifest fails validation" : ""), sec.tone)
  var finds = Array.isArray(report.findings) ? report.findings : []
  for (var i = 0; i < finds.length && i < 12; i++)
    add("● " + finds[i].id + "  " + finds[i].at + "  " + finds[i].evidence, "bad", 1)
  if (finds.length > 12) add("… " + (finds.length - 12) + " more findings", "dim", 1)
  var caps = {}
  var capList = Array.isArray(report.capabilities) ? report.capabilities : []
  for (var c = 0; c < capList.length; c++) caps[capList[c].id] = (caps[capList[c].id] || 0) + 1
  var capIds = Object.keys(caps).sort()
  if (capIds.length) add("Capabilities: " + capIds.map(function(k) { return k + " ×" + caps[k] }).join(", "), "warn", 1)
  var nix = report.nixosCompatibility || {}
  var nl = nixLabel(nix.verdict)
  add(nl.text.charAt(0).toUpperCase() + nl.text.slice(1), nl.tone)
  var nf = Array.isArray(nix.findings) ? nix.findings : []
  for (var n = 0; n < nf.length && n < 12; n++)
    add((nf[n].severity === "blocker" ? "✘ " : "◆ ") + nf[n].id + "  " + nf[n].at + "  " + nf[n].evidence,
        nf[n].severity === "blocker" ? "bad" : "warn", 1)
  if (nf.length > 12) add("… " + (nf.length - 12) + " more", "dim", 1)
  var scanned = String(report.scannedCommit || ""), verified = String(report.verifiedCommit || "")
  add("Scanned " + scanned.slice(0, 12) + (verified ? "   verified " + verified.slice(0, 12) : "   no verified commit on record"),
      "dim")
  return out
}
