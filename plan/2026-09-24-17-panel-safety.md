---
status: approved
issue: 17
spec: spec/2026-09-24-17-panel-safety.md
---

# Plan: Panel safety and state

This plan is self-contained; it carries every approved decision. Line
numbers are on `master` at `449636c`; after the rebase on #16 (step 0)
find each place by the code quoted, not the number.

**Decisions**

- **Order.** This branch rebases on #16 before any code is written. One
  #17 PR; its **first commit is the clipboard fix** (Part A), so it can be
  reviewed and, if needed, cherry-picked alone.
- **Dependency on #15.** The SIGTERM trap in `bin/omarchy-plugin-audit`
  (kill the `_bound_run` child's process group, then `exit` so the `EXIT`
  trap removes `$STAGE`) is **#15's item 9**, not this PR. This PR does not
  touch `bin/omarchy-plugin-audit`. The QML side still sets
  `auditProcess.running = false`. Without #15 a cancel still ends the audit
  script and frees the queue slot, but its `git clone` child runs to its
  120 s stage deadline. The PR description names the dependency; the
  "no clone left" check (step 12) runs once #15 is merged.
- **Fonts.** Every new `Text` uses `Style.font.subtitle`, the token #16
  gives detail text; conflicts on the rebase take #16's token and this
  plan's text.
- **A1 `c` copies a built command.** `Model.js` gains
  `REPO_RE = /^https:\/\/github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/?$/`
  and `installCommandFor(row)`: `""` unless `row.installAvailable === true`
  and `row.repo` matches `REPO_RE`; otherwise
  `"omarchy plugin add " + repo` with the trailing `/` removed. No
  `--enable`, no `--yes`. `openArgv` uses the same `REPO_RE`.
  `installCommand` leaves `parseRows` and the `applyPayload` stub; the
  panel never reads the catalog's `installCommand`. `lib/catalog.sh` keeps
  emitting it for the TUI (#18's).
- **A2 copy boundary.** `copyArgv(text)` returns `null` for empty text or
  text containing any of `\r \n U+2028 U+2029`. `BrowserState.copy` runs
  nothing and returns `false` on `null`.
- **A3 the pane shows the command.** A new `Text` after the repo line in
  the detail `Column`, `textFormat: Text.PlainText`,
  `wrapMode: Text.WrapAnywhere`: `c copies:  <cmd>` (dim) or
  `Copied:  <cmd>` (accent, when `copiedFor === selected.id`), or
  `Nothing to copy: the catalog marks this plugin as not installable` /
  `Nothing to copy: its repository is not a GitHub URL` (dim). View property
  `copiedFor: ""`, set by `c` on a successful copy, cleared by
  `openDetails`. Detail `c`:
  `case Qt.Key_C: if (BrowserState.copy(Model.installCommandFor(root.selected))) root.copiedFor = id; break`.
  `SHORTCUTS` `c` → `"copy the install command shown in the pane"`.
- **A4 `clean()`** also strips U+200B–U+200F, U+202A–U+202E, U+2060–U+2069
  and U+FEFF, and maps U+2028/U+2029 to a space. `\n` and `\t` stay.
- **B modifier keys.** In the detail `Keys.onPressed`, right after the
  `commonKey` line:
  `if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)) return`
  with the comment "Bare keys only: Ctrl+F is "find" in every other app, not
  "launch the fix agent"." **Only `?`** (handled by `commonKey`, on
  `event.text`) accepts Shift; every other detail key, the y/n confirm
  included, requires no modifier. The event is not accepted. List keys are
  unaffected.
- **C1 audit timeout and cancel** (`BrowserState.qml`).
  `property string auditStop: ""`; `readonly property int auditTimeoutMs: 300000`
  (**5 minutes, approved**); a `Timer` (`auditTimer`) started when an audit
  process starts, stopped in `onExited`, firing `stopAudit("timeout")`.
  `cancelAudit()` clears `pendingAudit` and calls `stopAudit("cancelled")`
  if running. `stopAudit(why)` sets `auditStop` then
  `auditProcess.running = false` (fallback `auditProcess.signal(15)` if
  step 6 shows `running = false` does not send SIGTERM). `onExited` with
  `auditStop !== ""`: `reportFor = auditingFor`, `report = null`,
  `auditError` = `"Audit cancelled."` or
  `"The audit gave up after 5 minutes. Press a to try again."`, clear
  `auditStop`, then start `pendingAudit` as today. `audit(id)` returns early
  when `id === auditingFor` and an audit runs. `back()` calls
  `BrowserState.cancelAudit()`.
- **C3** a `Text` beside "Auditing in a sandbox…", visible when
  `BrowserState.pendingAudit === root.selected.id`:
  `Queued: starts when the current audit stops`. One slot, newest wins.
- **C4** `i`: `if (root.selected.installAvailable && !BrowserState.installing) root.confirmOpen = true`.
- **C5** `dismiss()` also calls `BrowserState.cancelAudit()` and a new
  `BrowserState.forgetPreview()` (`pendingPreview = null; previewFor = ""`).
  A confirmed install is **not** stopped.
- **C6** the `applyPayload` stub gets `stub: true`; a
  `Connections { target: BrowserState; function onRowsChanged() {…} }`
  replaces a stub `selected` with `BrowserState.rowFor(id)` and calls
  `BrowserState.preview(row)`. The audit is left alone.
- **C7** `loadCatalog(refresh)` while running: `refresh === true` sets
  `pendingRefresh = true` and returns; `catalogProcess.onExited` ends with
  `if (root.pendingRefresh) { root.pendingRefresh = false; root.loadCatalog(true) }`.
- **C8** `reportLines`: `finds`, `capList`, `nf` filtered to
  `x && typeof x === "object"` before use (the 12 cap counts real entries);
  `nixosCompatibility` used only when it is an object.
- **C9** `BarWidget.qml:150`:
  `model: root.updateAvailable && Array.isArray(root.updateInfo.notes) ? root.updateInfo.notes.slice(0, 4) : []`.
- **Sheet:** `Esc  ←` → `"back to the list (stops a running audit)"`.
- **Docs:** one sentence each in `docs/manual/the-panel.md` (`c` line) and
  `docs/manual/installing.md` about the pane line. `03-details-preview.webp`
  is retaken last (#16's retake predates this line); the tour is not.

## Steps

0. Rebase: `git rebase fix/16-panel-scaling` (or `master` once #16 is
   merged). → verify by `git log --oneline` showing #16's commits under
   this branch's, and `tests/model-check.mjs` printing `ok`.

**Commit 1: clipboard (Part A)**

1. `tests/model-check.mjs` (test first): export `installCommandFor`; add
   the asserts:
   - `installCommandFor({installAvailable:true, repo:"https://github.com/a/b/"}) === "omarchy plugin add https://github.com/a/b"`;
   - `""` for `installAvailable:false`, `repo:"https://evil.example/a/b"`,
     `"https://github.com/a/b;rm"`, a repo with `\n`, and `null`;
   - `copyArgv("a\nb")`, `copyArgv("a b")`, `copyArgv("")` are `null`;
     `copyArgv("-n x")` still keeps `--`;
   - `clean("a‮b​c⁦d") === "abcd"`, `clean("a\nb")` keeps
     the newline;
   - `parseRows` output has no `installCommand` key.
   → verify by `nix run nixpkgs#nodejs -- tests/model-check.mjs` **failing**.
2. `Model.js`: `REPO_RE`, `installCommandFor`, `openArgv` on `REPO_RE`,
   `copyArgv` null rule, `clean()` second replace, `installCommand` out of
   `parseRows`, `SHORTCUTS` `c`.
   → verify by the same command printing `ok`.
3. `BrowserState.qml` `copy()`: take `Model.copyArgv(text)`, return
   `false` on `null`. `BrowserView.qml`: drop `installCommand` from the stub,
   `copiedFor`, the A3 `Text`, the new `c` handler, clear `copiedFor` in
   `openDetails`. `docs/manual/the-panel.md`, `installing.md`: the sentence.
   → verify by `grep -rn "installCommand" *.qml Model.js` finding only
   `installCommandFor`, then commit
   `fix(panel): c copies a command built from the checked repo (#17)`.

**Commit 2: keys and state (Parts B and C)**

4. `tests/model-check.mjs` (test first): `reportLines` with
   `findings: [null, {id:"x",at:"f:1",evidence:"e"}]`, `capabilities: [null]`,
   `nixosCompatibility: {findings:[null]}` does not throw and has exactly
   one finding line; `nixosCompatibility: "oops"` does not throw; the `Esc`
   sheet entry reads "back to the list (stops a running audit)".
   → verify by the test **failing**.
5. `Model.js`: C8 and the sheet text. → verify by the test printing `ok`.
6. Check Quickshell's kill semantics before relying on them: in the shell's
   Quickshell, run a `Process { command: ["sleep","300"] }`, set
   `running = false`, and check with `ps` that `sleep` got SIGTERM (it is
   gone, with no SIGKILL-only behaviour needing a grace). If it is not gone,
   C1 uses `auditProcess.signal(15)`.
   → verify by recording the result in this plan's step notes.
7. `BrowserState.qml`: C1 (`auditStop`, `auditTimeoutMs`, `auditTimer`,
   `cancelAudit`, `stopAudit`, the `onExited` branch, the duplicate guard),
   C5 `forgetPreview`, C7 `pendingRefresh`.
   → verify by `qmllint BrowserState.qml` (from `nix run nixpkgs#kdePackages.qtdeclarative`)
   reporting no new errors against master's baseline.
8. `BrowserView.qml`: B guard, C1 `back()` → `cancelAudit()`, C3 queued
   `Text`, C4 `i`, C5 `dismiss()`, C6 `stub: true` and `Connections`.
   → verify by `qmllint BrowserView.qml` as above, and
   `grep -n "ShiftModifier" BrowserView.qml` showing the one guard after the
   `commonKey` line.
9. `BarWidget.qml`: C9. → verify by `qmllint BarWidget.qml`.
10. `CHANGELOG.md` and `manifest.json`: an entry naming #17 and the #15
    dependency. → verify `jq . manifest.json` parses. Commit
    `fix(panel): bare detail keys, audit cancel and timeout, state fixes (#17)`.

**Runtime (p620, this machine)**

11. Load the branch: `./install.sh --plugin` from the worktree, then
    `omarchy-restart-shell`. Open with Super+Alt+U.
    → verify:
    - details show `c copies: omarchy plugin add …`; after `c`, `wl-paste`
      prints exactly that one line and the pane says `Copied`;
    - a plugin with `installAvailable:false` shows "Nothing to copy", and
      neither `c` nor `i` acts;
    - Ctrl+F, Alt+E, Shift+O, Shift+Esc and Ctrl+Y in the details do
      nothing; `?` opens the sheet;
    - open a plugin, press Esc: the pane is gone and
      `pgrep -f omarchy-plugin-audit` is empty once the script's current
      command ends; Enter on another plugin during an audit shows
      "Queued…", then "Auditing…";
    - with `auditTimeoutMs` set to 5000 locally (not committed) on a slow
      repo, the "gave up" message appears and `a` retries;
    - close the panel during an audit, reopen: nothing is running;
    - `rm -rf` the catalog cache, then
      `omarchy-shell shell toggle io.github.olafkfreund.nixarchy-plugin-browser '{"id":"crmne.hyprmoncfg"}'`:
      the stub, then the full details and preview;
    - Ctrl+R twice quickly gives two loads, the second with `--refresh`
      (`pgrep -af catalog.sh`);
    - the bar popup opens with a string `notes` in `lib/update.sh`'s cache
      and shows no bullet list.
12. Once #15 is merged (and this branch rebased on it): open a plugin with
    a slow clone, press Esc during the clone.
    → verify `pgrep -f "git clone"` is empty within a few seconds and the
    stage directory is gone.
13. Small screen: a headless output, so the real monitors are untouched:
    `hyprctl output create headless PBTEST`,
    `hyprctl keyword monitor PBTEST,1280x800@60,auto,1`,
    `hyprctl dispatch focusmonitor PBTEST`, open the panel, open details,
    `grim -o PBTEST /tmp/pb17.png`, then `hyprctl output remove PBTEST`.
    → verify the A3 line and the C3 line wrap inside the card and nothing
    is cut off.
14. Screenshot (last): retake `docs/img/03-details-preview.webp` with the
    #12 procedure on razer (current theme, ai-mirror control granted by the
    owner, announced on the bus, cropped to the card, `nix run nixpkgs#imagemagick`).
    → verify under 200 KB, reviewed for private data (noted in the PR), and
    the Pages image-exists check passes.

## Tests

- `nix run nixpkgs#nodejs -- tests/model-check.mjs` → `ok`.
- `grep -rn "installCommand" *.qml Model.js` → only `installCommandFor`.
- `git diff master -- bin/omarchy-plugin-audit` → empty (the trap is #15's).
- Steps 11–13 pass on p620; step 12 after #15; step 14 for the image.
- The PR's CI is green.

## Rollback

All changes are in this plugin. Revert commit 2 alone to keep the clipboard
fix, or both commits for everything (`git revert`). On a machine that has
it: `omarchy plugin update io.github.olafkfreund.nixarchy-plugin-browser`,
then `omarchy-restart-shell` (the `BrowserState` singleton survives a plain
update). Reverting #17 does not need #15 reverted: #15's trap is harmless
without a caller that cancels. A leftover headless output is removed with
`hyprctl output remove PBTEST`.
