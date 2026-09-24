// tests/model-check.mjs — self-check for Model.js under plain Node:
//   nix run nixpkgs#nodejs -- tests/model-check.mjs [catalog-list.json]
// With a real `lib/catalog.sh list` output as the argument it also times the
// parse and a filter (the plan's 16 ms budget for one keystroke).
// tier: hermetic
import { readFileSync } from "node:fs"
import vm from "node:vm"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../Model.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "")
const M = {}
vm.runInNewContext(src + "\nObject.assign(M, {isSafeId, parsePayload, parseRows, filterRows, verdictLabel, nixLabel, parseReport, lastLines, clean, openArgv, agentArgv, auditArgv, installArgv, copyArgv, SHORTCUTS, reportLines, previewArgv, isPreviewPath, cardExtent, installCommandFor})", { M })

// Values made inside the vm context have that realm's prototypes; compare as data.
const j = (v) => JSON.parse(JSON.stringify(v))

// ids
assert.ok(M.isSafeId("crmne.hyprmoncfg"))
for (const bad of ["", "-rf", "a b", "a;b", "../x", "a/b", "$(x)", 5, null]) assert.ok(!M.isSafeId(bad), `unsafe: ${bad}`)

// payload
assert.deepEqual(j(M.parsePayload("{not json")), {})
assert.deepEqual(j(M.parsePayload('"x"')), {})
assert.deepEqual(j(M.parsePayload('{"id":"a;b"}')), {})
assert.deepEqual(j(M.parsePayload('{"id":"a.b","query":"mon"}')), { id: "a.b", query: "mon" })

// rows and filter
const rows = M.parseRows(JSON.stringify([
  { id: "b.high", name: "High", author: "bob", category: "System", stars: 50, tags: ["monitor"], badge: "verified" },
  { id: "a.low", name: "Low", author: "ann", category: "Media", stars: 3, tags: [], badge: "weird" },
  { id: "bad id", name: "dropped" }
]))
assert.equal(rows.length, 2, "rows with unsafe ids are dropped")
assert.equal(rows[1].badge, "unverified", "unknown badge becomes unverified")
assert.equal(M.parseRows("{oops"), null)
assert.equal(M.filterRows(rows, "").length, 2, "empty query returns everything")
assert.deepEqual(j(M.filterRows(rows, "MONITOR").map(r => r.id)), ["b.high"], "matches tags, case-insensitive")
assert.deepEqual(j(M.filterRows(rows, "ann").map(r => r.id)), ["a.low"], "matches author")
assert.deepEqual(j(M.filterRows(rows, "high system").map(r => r.id)), ["b.high"], "all terms must match")
assert.equal(M.clean("a\u0007b\u001b[31m"), "a b [31m", "control characters removed")

// verdicts and report
assert.equal(M.verdictLabel("needs-fixes").tone, "bad")
assert.equal(M.nixLabel("likely-ok").tone, "good")
assert.equal(M.parseReport("nope"), null)
assert.equal(M.parseReport('{"outcome":"passed"}').outcome, "passed")
assert.equal(M.lastLines("\u001b[32mone\u001b[0m\n\ntwo\nthree\n", 2), "two\nthree")

// report lines
const rep = { outcome: "review-required", manifestValidate: "ok", scannedCommit: "a".repeat(40), verifiedCommit: "",
  findings: [], capabilities: [{ id: "privilege" }, { id: "privilege" }, { id: "installer" }],
  nixosCompatibility: { verdict: "blocked", findings: [{ id: "fhs-path", severity: "blocker", at: "W.qml:2", evidence: "x\u0007y" }] } }
const lines = j(M.reportLines(rep))
assert.equal(lines[0].text, "Security: review required")
assert.equal(lines[1].text, "Capabilities: installer \u00D71, privilege \u00D72")
assert.equal(lines[2].tone, "bad")
assert.ok(lines[3].text.startsWith("\u2718 fhs-path  W.qml:2  x y"), "blocker line, control char cleaned")
assert.deepEqual(j(M.reportLines(null)), [])
// a malformed report never throws; only real entries are drawn (#17)
const odd = j(M.reportLines({ outcome: "passed", findings: [null, { id: "x", at: "f:1", evidence: "e" }],
  capabilities: [null], nixosCompatibility: { findings: [null] } }))
assert.equal(odd.filter(l => l.text.startsWith("● ")).length, 1, "one finding line")
assert.ok(!odd.some(l => l.text.startsWith("Capabilities")), "a null capability is not counted")
assert.doesNotThrow(() => M.reportLines({ outcome: "passed", nixosCompatibility: "oops" }))
assert.equal(M.SHORTCUTS.find(s => s.keys === "Esc  ←").what, "back to the list (stops a running audit)")

// previews: same allowlist as catalog.sh
const good = "assets/img/plugins/5-crmne-omarchy-hyprmoncfg-card.webp"
assert.ok(M.isPreviewPath(good))
for (const bad of ["../x.webp", "https://evil/x.webp", "assets/img/plugins/x.webp?y", "assets/img/other/x.webp", "assets/img/plugins/x.svg", "", null])
  assert.ok(!M.isPreviewPath(bad), `bad preview accepted: ${bad}`)
assert.equal(M.previewArgv("/p", "../x.webp"), null)
assert.deepEqual(j(M.previewArgv("/p", good)), ["/run/current-system/sw/bin/bash", "/p/lib/catalog.sh", "preview", good])
const prow = j(M.parseRows(JSON.stringify([{ id: "a.b", preview: good }, { id: "c.d", preview: "https://evil/x.webp" }])))
assert.equal(prow[0].preview, good)
assert.equal(prow[1].preview, "", "an unsafe preview path is dropped")

// argv: absolute, fixed, never a shell string
const root = "/p"
for (const a of [M.auditArgv(root, "x.y"), M.installArgv(root, "x.y"), M.agentArgv(root, "x.y", "fix"), M.copyArgv("-n x")]) {
  assert.ok(a[0].startsWith("/run/current-system/sw/bin/"), `absolute: ${a[0]}`)
  assert.ok(!a.includes("-c"), "no sh -c")
}
assert.equal(M.agentArgv(root, "x.y", "rm -rf").at(-1), "explain", "unknown mode falls back to explain")
assert.deepEqual(j(M.copyArgv("-n x").slice(1)), ["--", "-n x"], "copy text is never read as an option")
assert.equal(M.openArgv("https://evil.example/x"), null)
assert.equal(M.openArgv("https://github.com/a/b;rm"), null)
assert.ok(M.openArgv("https://github.com/crmne/omarchy-hyprmoncfg"))
assert.ok(M.SHORTCUTS.some(s => s.keys === "?"))

// install command: built from a checked repo, never copied from the catalog (#17)
assert.equal(M.installCommandFor({ installAvailable: true, repo: "https://github.com/a/b/" }), "omarchy plugin add https://github.com/a/b")
for (const bad of [{ installAvailable: false, repo: "https://github.com/a/b" },
                   { installAvailable: true, repo: "https://evil.example/a/b" },
                   { installAvailable: true, repo: "https://github.com/a/b;rm" },
                   { installAvailable: true, repo: "https://github.com/a/b\n" },
                   { installAvailable: true, repo: "https://github.com/a/b\nrm -rf ~" }, null])
  assert.equal(M.installCommandFor(bad), "", `no command for ${JSON.stringify(bad)}`)
for (const bad of ["a\nb", "a\rb", "a\u2028b", "a\u2029b", ""]) assert.equal(M.copyArgv(bad), null, `copy refused: ${JSON.stringify(bad)}`)
assert.equal(M.clean("a\u202Eb\u200Bc\u2066d\uFEFF"), "abcd", "bidi and zero-width characters removed")
assert.equal(M.clean("a\u2028b"), "a b", "line separator becomes a space")
assert.equal(M.clean("a\nb\tc"), "a\nb\tc", "newline and tab kept")
assert.ok(!("installCommand" in M.parseRows(JSON.stringify([{ id: "a.b", installCommand: "curl x | sh" }]))[0]), "catalog installCommand is not read")
assert.equal(M.SHORTCUTS.find(s => s.keys === "c").what, "copy the install command shown in the pane")

// card size
assert.equal(M.cardExtent(1280, 0.6, 560, 960, 10), 768)  // share wins
assert.equal(M.cardExtent(3840, 0.6, 560, 960, 10), 960)  // ceiling
assert.equal(M.cardExtent(800, 0.7, 420, 760, 10), 560)   // share, above floor
assert.equal(M.cardExtent(600, 0.7, 420, 760, 10), 420)   // floor
assert.equal(M.cardExtent(500, 0.6, 560, 960, 10), 480)   // room beats floor
assert.equal(M.cardExtent(10, 0.6, 560, 960, 10), 0)      // degenerate

// optional: timing on a real list
const real = process.argv[2]
if (real) {
  const text = readFileSync(real, "utf8")
  let t = performance.now(); const all = M.parseRows(text); const parseMs = performance.now() - t
  let worst = 0
  for (const q of ["a", "mon", "theme dark", "zzzz", "o"]) {
    t = performance.now(); M.filterRows(all, q); worst = Math.max(worst, performance.now() - t)
  }
  console.log(`rows=${all.length} parse=${parseMs.toFixed(1)}ms worst-filter=${worst.toFixed(2)}ms`)
  assert.ok(worst < 16, "a keystroke must filter within 16 ms")
}
console.log("ok")
