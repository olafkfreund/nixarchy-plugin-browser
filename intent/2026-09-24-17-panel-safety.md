---
status: approved
issue: 17
author: olafkfreund
---

# Intent: Panel safety and state

## Problem

The 2026-09-24 review (items 6, 7 and 15) found places where the panel does
something the user did not see or did not ask for, or loses track of its own
work. Line numbers are on master at the time of writing.

**Hidden clipboard text (item 6).**

- `c` in the detail pane copies the catalog's `installCommand` verbatim
  (`BrowserView.qml:276`, `BrowserState.copy`). The command is never shown in
  the panel, so the user pastes text they have not read into a terminal.
- `Model.clean()` (`Model.js:56-60`, used for `installCommand` at
  `Model.js:90`) strips control characters but keeps `\n` and `\t`. A catalog
  entry with a newline in its install command puts a multi-line string on the
  clipboard, and a terminal runs every line on paste.

**Modifier keys ignored in the detail pane (item 7).**

- The detail keys (`BrowserView.qml:260-283`) match on `event.key` alone.
  Ctrl+F, Alt+E, Shift+O and so on fire the same actions as the bare keys:
  Ctrl+F (a habit from "find") launches the fix agent and closes the panel.

**Work and state that go wrong (item 15).**

- **Queued audit looks idle.** A second audit while one runs is only stored in
  `pendingAudit` (`BrowserState.qml:80`); the "Auditing…" line
  (`BrowserView.qml:365`) only shows for `auditingFor`, so the plugin the user
  asked about shows nothing.
- **Audit cannot be stopped.** There is no key to cancel it and no timeout on
  the QML side (`BrowserState.qml:78-106`); a hung audit blocks every later
  one.
- **`i` ignores `installAvailable`.** `BrowserView.qml:275` opens the install
  question for any plugin, including ones the catalog marks as not
  installable.
- **Pending work survives close/reopen.** `Menu.qml:48-51` / `dismiss()` clear
  only the dialogs; a queued audit or preview still runs after the panel is
  closed and reopened on another plugin.
- **The payload stub row is never replaced.** Opening with `{"id": …}` while
  the catalog is still loading shows a stub (`BrowserView.qml:66-74`) with no
  description, repo or install command, and it stays a stub after the catalog
  arrives.
- **Ctrl+R is dropped during a load.** `BrowserView.qml:191` calls
  `loadCatalog(true)`, which returns early while a load is running
  (`BrowserState.qml:39`), so the refresh the user asked for never happens.
- **`clean()` misses bidi and zero-width characters.** U+202A-202E,
  U+2066-2069 and U+200B-200F pass through, so marketplace text can reorder
  what is drawn or hide characters, even as plain text.
- **Null entries blank the report.** `Model.reportLines` reads
  `finds[i].id` and `capList[c].id` (`Model.js:193-198`) without a null check;
  one `null` in the audit JSON throws and the whole report disappears.
- **Bar popup on bad update data.** `BarWidget.qml:150` calls
  `updateInfo.notes.slice(...)`; if `notes` is not an array the popup throws.

## Proposed outcome

- Before anything reaches the clipboard, the user can see exactly what will
  be copied, and it is a single line: no newlines, no hidden or
  direction-changing characters.
- Detail-pane action keys fire only on the bare key (Shift only where a key
  needs it). Ctrl/Alt/Super combinations do nothing there.
- Every audit the user asks for is visible as running or queued; a running
  audit can be cancelled and gives up on its own after a time limit, with a
  message saying so.
- `i` does nothing (or says why) for a plugin the catalog marks as not
  installable.
- Closing the panel ends or forgets work started for it; reopening starts
  clean.
- A plugin opened by id before the catalog loaded shows its full details once
  the catalog arrives.
- Ctrl+R during a load results in a fresh catalog, not silence.
- Malformed audit or update JSON shows what can be shown and never blanks the
  report or breaks the bar popup.

## Affected users and systems

- Everyone who uses the Plugin Browser panel, especially anyone who copies an
  install command into a terminal.
- This repo: `BrowserView.qml`, `BrowserState.qml`, `Model.js`, `Menu.qml`,
  `BarWidget.qml`, and whatever tests cover `Model.js`.
- `omarchy-plugin-audit` is only called differently if cancel or timeout
  needs it; its JSON contract does not change.

## Constraints

- Keyboard-first design; key letters stay the same (a, e, f, i, c, o, j/k,
  Esc, ?, Ctrl+R).
- All marketplace and audit text stays `Text.PlainText`.
- No new dependencies; must work in omarchy-shell's plugin host as it is.
- Processes keep fixed argv and absolute paths; no shell strings.
- The security posture of issue #4 does not regress: fail-closed audit,
  nothing enabled automatically, install still behind the y/n question.
- Issue #16 also edits `BrowserView.qml`. This task lands after #16, or
  rebases on it.

## Open questions

- **Clipboard content.** Show the catalog's `installCommand` (sanitised to one
  line) before copying, or build the command ourselves from the plugin id
  (`omarchy-plugin-add <id>` or similar) and ignore the catalog's text?
- **Showing it.** Always visible in the detail pane, or a confirm step on `c`?
- **Audit timeout.** How long before the panel gives up (the audit clones a
  repo), and which key cancels (Esc already means back)?
- **Queue depth.** Keep "newest request wins" with one slot, or show that an
  earlier queued request was replaced?
- **On close.** Cancel a running audit, or let it finish and keep the result
  for the next open?
- **Scope.** Is this one task, or should item 6 (clipboard) be split out and
  land first as the security-relevant part?
