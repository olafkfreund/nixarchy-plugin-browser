---
status: approved
issue: 17
intent: intent/2026-09-24-17-panel-safety.md
---

# Spec: Panel safety and state

Approved decisions this spec builds on (intent approval, `b495a8d`):

1. `c` copies a command built from the checked repo, `omarchy plugin add <repo>`,
   and the detail pane shows it.
2. An audit has a timeout, and going back from the details cancels it.
3. The queue keeps a single slot, and the newest request wins.
4. The clipboard fix lands first.
5. #17 rebases on #16 when it is implemented.

Line numbers are on `master` at `449636c`. After the rebase on #16, the
`font.pixelSize` lines in `BrowserView.qml` change token (#16's approved
two steps: `caption` becomes `subtitle`), and every new `Text` below uses
`subtitle`, the token #16 gives the detail text.

## Design

### Part A: clipboard (item 6), lands first

**A1. The command is built, not taken from the catalog.** Add to `Model.js`:

```js
var REPO_RE = /^https:\/\/github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/?$/
// What `c` copies: an install command built from a checked GitHub URL, or ""
// when the catalog marks the plugin as not installable or its repo is not one.
function installCommandFor(row) {
  if (!row || row.installAvailable !== true || !REPO_RE.test(row.repo || "")) return ""
  return "omarchy plugin add " + row.repo.replace(/\/$/, "")
}
```

`openArgv` (`Model.js:171-174`) uses the same `REPO_RE`, so there is one
definition of a "checked repo". The command has no `--enable` and no
`--yes`, which keeps the #4 posture: nothing is enabled automatically.
`omarchy plugin add [git-url]` is the shell's own subcommand (from
`omarchy plugin` help).

`installCommand` is removed from the row in `parseRows` (`Model.js:90`) and
from the payload stub (`BrowserView.qml:70`). The panel no longer reads the
catalog's `installCommand` at all. `lib/catalog.sh:148` keeps emitting it,
because the terminal UI (`bin/omarchy-plugin-browser:88`) reads it. That
consumer is #18's to fix.

**A2. The copy boundary refuses multi-line text.** `copyArgv(text)`
(`Model.js:168`) returns `null` when the text contains a character from
`[\r\n  ]`, or is empty. `BrowserState.copy` (`BrowserState.qml:185-189`)
runs nothing when it gets `null`. The text built in A1 never trips this. The
check stays because it guards the clipboard boundary: the next caller of
`copy()` cannot hand it a multi-line string by mistake.

**A3. The pane shows the command.** A new `Text` goes in the detail
`Column`, right after the repo line (`BrowserView.qml:349-358`).
`textFormat: Text.PlainText`, `wrapMode: Text.WrapAnywhere`. It shows one of:

- `c copies:  omarchy plugin add https://github.com/owner/repo` (dim), or
  `Copied:  omarchy plugin add …` (accent) after `c`;
- `Nothing to copy: the catalog marks this plugin as not installable`, or
  `Nothing to copy: its repository is not a GitHub URL` (dim).

The `Copied` state is a view property `copiedFor: ""`. `c` sets it to the
plugin's id, and `openDetails` clears it. The detail `c` handler
(`BrowserView.qml:276`) becomes:

```qml
case Qt.Key_C: if (BrowserState.copy(Model.installCommandFor(root.selected))) root.copiedFor = id; break
```

`SHORTCUTS` (`Model.js:34`) changes to
`{ keys: "c", what: "copy the install command shown in the pane" }`.

**A4. `clean()` removes invisible and direction-changing characters.**
`Model.js:58` gains a second replace:
`/[​-‏‪-‮⁠-⁩﻿]/g` → `""`, and
` `/` ` → `" "`. `\n` and `\t` are kept, because descriptions are
multi-line. Every catalog and report string already passes through
`clean()`, so this one change covers all of them.

### Part B: modifier keys (item 7)

In the detail `Keys.onPressed` (`BrowserView.qml:260`), just after the
`commonKey` line:

```qml
// Bare keys only: Ctrl+F is "find" in every other app, not "launch the fix agent".
if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)) return
```

The guard comes after `commonKey`, so `?` (Shift+/, matched on
`event.text`) still opens the sheet. `?` is the only detail key that
accepts Shift; every other detail key needs no modifier at all (approver,
question 4). The guard also covers the y/n
confirmation, so Ctrl+Y does not install. The event is not accepted, so it
propagates as it does today for keys the handler does not know. The list
keys (the search field's Ctrl+J, Ctrl+K and Ctrl+R) are not affected.

### Part C: work and state (item 15)

**C1. Audit timeout and cancel (`BrowserState.qml:68-106`).**

- New `property string auditStop: ""` (`""`, `"cancelled"` or `"timeout"`),
  and `readonly property int auditTimeoutMs: 300000` (5 min, approved).
- `Timer { id: auditTimer; interval: root.auditTimeoutMs; onTriggered: root.stopAudit("timeout") }`,
  restarted in `audit()` when a process starts, and stopped in `onExited`.
- `function cancelAudit()` clears `pendingAudit`, then calls
  `stopAudit("cancelled")` if an audit is running.
- `function stopAudit(why)` sets `auditStop = why`, then
  `auditProcess.running = false`. Quickshell sends SIGTERM when `running`
  goes false. The plan's first step for C1 checks this against the
  Quickshell version in the shell, and falls back to `auditProcess.signal(15)`.
- `onExited`: when `auditStop !== ""`, it sets `reportFor = auditingFor`,
  `report = null` and `auditError` to either `"Audit cancelled."` or
  `"The audit gave up after 5 minutes. Press a to try again."`. It then
  clears `auditStop` and starts `pendingAudit` as it does today. Because
  `report` is `null`, reopening that plugin audits it again
  (`openDetails`, `BrowserView.qml:97`).
- `audit(id)` returns early when `id === auditingFor` and an audit is
  running, so pressing `a` twice does not queue a duplicate.
- `back()` (`BrowserView.qml:101`) calls `BrowserState.cancelAudit()`.

**C2. The audit script stops its child on SIGTERM: moved to #15**
(approver, question 2). A bash script killed with SIGTERM runs its `EXIT`
trap, so the `$STAGE` cleanup happens, but the `setsid` child of
`_bound_run` (the `git clone`) keeps running with no watchdog. The trap that
kills that child's process group is item 9 of
`spec/2026-09-24-15-audit-hardening.md` (approved), not part of this work.
This work does not change `bin/omarchy-plugin-audit`.

**#17 depends on #15 for real cancellation.** The QML side still sets
`auditProcess.running = false` (C1), and the panel shows "Audit cancelled."
and frees the slot when the process exits, with or without #15. Without
#15 the clone it started runs on to its own 120 s stage deadline. The
exit code is not read: the panel uses its own `auditStop` flag.

**C3. A queued audit is visible.** A new `Text` goes next to "Auditing in a
sandbox…" (`BrowserView.qml:363-371`). It is visible when
`BrowserState.pendingAudit === root.selected.id`, and reads
`Queued: starts when the current audit stops`. The queue keeps its one
slot, and the newest request replaces the older one (decision 3). The
replaced plugin's pane is no longer on screen, so nothing needs to say that
it was dropped.

**C4. `i` respects `installAvailable`.** `BrowserView.qml:275` becomes
`if (root.selected.installAvailable && !BrowserState.installing) root.confirmOpen = true`.
For a plugin that is not installable, the A3 line already says so. `i`
does nothing, and the footer is unchanged.

**C5. Closing forgets the work.** `dismiss()` (`BrowserView.qml:57-60`,
called from `Menu.close()`) also calls `BrowserState.cancelAudit()` and
`BrowserState.forgetPreview()`. `forgetPreview()` is new: it sets
`pendingPreview = null` and `previewFor = ""`. A preview fetch that is
already running finishes, and its answer is dropped by the existing
`previewingFor === previewFor` check (`BrowserState.qml:141`). An install
the user confirmed with `y` is **not** stopped: killing
`omarchy plugin add` part-way could leave a half-written plugin folder. Its
output is shown the next time that plugin's details open, because
`installFor` is kept.

**C6. The stub row is replaced.** The stub in `applyPayload`
(`BrowserView.qml:70`) gets `stub: true`. A
`Connections { target: BrowserState; function onRowsChanged() { … } }` in
`BrowserView` checks two things. When `root.selected` is a stub and
`BrowserState.rowFor(root.selected.id)` finds a row, it sets
`root.selected` to that row and calls `BrowserState.preview(row)`. The
audit is keyed by id and is left as it is.

**C7. Ctrl+R during a load is kept.** `BrowserState.loadCatalog(refresh)`
(`:38-44`): while a load runs, `refresh === true` sets
`property bool pendingRefresh: true` and returns. `catalogProcess.onExited`
ends with `if (root.pendingRefresh) { root.pendingRefresh = false; root.loadCatalog(true) }`.

**C8. Null entries do not blank the report.** In `reportLines`
(`Model.js:192-207`), `finds`, `capList` and `nf` are filtered to entries
where `x && typeof x === "object"` before they are used, so the `12` cap
counts only real entries. `nixosCompatibility` is used only when it is an
object.

**C9. Bar popup.** `BarWidget.qml:150` becomes
`model: root.updateAvailable && Array.isArray(root.updateInfo.notes) ? root.updateInfo.notes.slice(0, 4) : []`.

### Shortcut sheet

`Model.SHORTCUTS` also changes `Esc  ←` to `"back to the list (stops a running audit)"`.
The key letters stay the same.

## Alternatives rejected

- **Copy the catalog's `installCommand`, cleaned to one line.** The text
  still comes from the marketplace. A catalog entry could point
  `installCommand` at another repo, or add flags, while the pane shows the
  plugin's own repo. Rejected by decision 1.
- **A confirm step on `c`.** It adds a key press, and the pane already shows
  the text before `c` is pressed. Decision 1 chose to show it.
- **Build the command from the id (`omarchy-plugin-audit <id> --install`).**
  That command runs the audit first, which is safer, but it is this
  plugin's own script, not something a user can paste on any Omarchy
  machine. Decision 1 named `omarchy plugin add <repo>`.
- **A different key for cancel** (for example `x`). Esc already means back,
  and going back is the moment the user stops caring about the audit.
  Decision 2.
- **A queue of every request.** Moving through the list with Enter would
  line up audits for plugins the user has already left. Decision 3.
- **Let the audit finish on close, and keep the result.** A hidden audit
  would keep cloning after the user dismissed the panel, which the intent's
  outcome rules out.
- **Kill the install on close.** This risks a half-installed plugin, and the
  user already said `y`.
- **Rely on the script's own 120 s stage deadlines, with no QML timeout.** A
  hang outside `_bound_run` (the scanner, `jq`) is not covered by them.
- **A QML-only cancel, with no script change anywhere.** This was
  checked: the `setsid` clone outlives its parent and runs with no deadline.
  The script change lives in #15 (item 9) instead.
- **The trap in this PR.** #15 already edits that script's trap area; one
  owner avoids two traps. Approver, question 2.

## Risks

- **Dependency on #15.** Real cancellation (the clone stops) needs #15's
  item 9. If #17 merges first, Esc and close still stop the audit script
  and free the queue slot, but its `git clone` child runs to its stage
  deadline. The runtime check for a stopped clone runs only once #15 is in.
- **Quickshell kill semantics.** The spec assumes `running = false` sends
  SIGTERM. The plan checks this first, and `signal(15)` is the fallback.
  This affects every host.
- **The trap runs after a sleep.** Bash handles a TERM trap only after its
  current foreground command ends: the `sleep 0.5` in the `_bound_run` loop,
  or a `timeout`-bounded `du`/`find` (up to 120 s at `:265-266`). A cancel
  during the `local dir` measurement can take that long (with #15's trap). The panel shows
  "Audit cancelled." only once the process exits. A new audit waits in the
  queue until then, and C3 shows that it is queued.
- **Rebase on #16.** Both change the `font.pixelSize` lines and the detail
  `Column` in `BrowserView.qml`. The conflicts are mechanical.
- **The terminal UI still copies the catalog's command.**
  `bin/omarchy-plugin-browser:88` keeps the old behaviour until #18 changes
  it. This spec only covers the panel.
- **Existing tests.** `tests/model-check.mjs:77` asserts
  `copyArgv("-n x")` keeps `--`. That test still passes. No existing test
  reads `installCommand`.
- **Docs.** `docs/manual/the-panel.md:44` and `installing.md:40` describe `c`
  ("copy the install command"). They need one sentence about the pane
  line. Screenshot `03-details-preview.webp` will gain the line. #16 retakes
  the screenshots as its last step, before this work lands, so this work
  retakes `03-details-preview.webp` again as its own last step. The tour's
  detail frames will not show the line; they are not retaken for it.

## Verification

- **`tests/model-check.mjs`** adds `installCommandFor` to the export list,
  and these asserts:
  - `installCommandFor({installAvailable:true, repo:"https://github.com/a/b/"}) === "omarchy plugin add https://github.com/a/b"`;
    it returns `""` for `installAvailable:false`, for
    `repo:"https://evil.example/a/b"`, for `"https://github.com/a/b;rm"`, for
    a repo with `\n`, and for `null`;
  - `copyArgv("a\nb") === null`, `copyArgv("a b") === null`,
    `copyArgv("") === null`, and `copyArgv("-n x")` is unchanged;
  - `clean("a‮b​c⁦d")` gives `"abcd"`, and `clean("a\nb")`
    keeps the newline;
  - `reportLines` with `findings: [null, {id:"x",at:"f:1",evidence:"e"}]`,
    `capabilities: [null]` and `nixosCompatibility: {findings:[null]}`
    does not throw, and has exactly one finding line;
  - `reportLines` with `nixosCompatibility: "oops"` does not throw;
  - `parseRows` output has no `installCommand` key.

  Run `nix run nixpkgs#nodejs -- tests/model-check.mjs`. It prints `ok`.
- **Script check (C2)** belongs to #15's verification. Here, once #15 is
  in, the panel's cancel leaves no `git clone` behind (`pgrep -f "git clone"`).
- **Manual runtime check in the panel:**
  - The details show `c copies: omarchy plugin add …`. After `c`,
    `wl-paste` prints exactly that one line, and the pane says `Copied`.
  - A plugin with `installAvailable:false` shows "Nothing to copy", and
    neither `c` nor `i` does anything.
  - Ctrl+F, Alt+E, Shift+O, Shift+Esc and Ctrl+Y in the details do
    nothing. `?` (Shift+/) still opens the key sheet: it is the only detail
    key that accepts a modifier.
  - Open a plugin (the audit starts), press Esc, and check the audit process
    is gone (`pgrep -f omarchy-plugin-audit`). Enter on another plugin shows
    "Queued…" until the first one exits, then "Auditing…".
  - With `auditTimeoutMs` temporarily set to 5000 on a slow repo, the
    "gave up" message appears and `a` retries.
  - Close the panel during an audit, reopen it, and check nothing is
    running.
  - `omarchy-shell shell toggle … '{"id":"crmne.hyprmoncfg"}'` right after a
    cache wipe shows the stub, then the full details and preview once the
    catalog arrives.
  - Ctrl+R twice in quick succession gives two loads, the second with
    `--refresh`.
- **Bar.** Feed `lib/update.sh`'s cache a `notes` that is a string. The popup
  opens and shows no bullet list.
- CI wiring belongs to #19.

## Approver decisions (olafkfreund, 2026-09-24)

1. **Order of landing:** Part A (the clipboard fix) is the first commit of
   the same #17 PR, not its own PR.
2. **C2's home:** the SIGTERM trap in `bin/omarchy-plugin-audit` moves to
   #15 (its item 9). #17 depends on #15 for real cancellation. The QML side
   still sets `running = false`.
3. **Timeout:** 5 minutes, approved.
4. **Shift:** only `?` accepts Shift. Every other detail key requires no
   modifiers.
5. **Rebase:** #17 rebases on #16 at implementation time (from the intent
   approval).
