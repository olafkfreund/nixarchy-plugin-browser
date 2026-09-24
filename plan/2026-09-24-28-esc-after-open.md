---
status: approved
issue: 28
spec: spec/2026-09-24-28-esc-after-open.md
---

# Plan: Esc after an outside window goes back one step, not out

This plan is self-contained; it carries every approved decision (intent
`dc40375`, spec `9dd3394`). Line numbers are on `master` at `d0e4dfc`. It
plans a reproduction, not a fix.

**Decisions**

- **Most likely already fixed by `4d3035a`** (`o` now closes the panel). No
  QML fix unless a variant reproduces.
- **Evidence from a temporary debug build:** one commit of `console.log`
  lines (all prefixed `pb28`) on the **local** branch
  `debug/28-esc-focus-log`, cut from `fix/28-esc-after-open`. Never pushed,
  never opened as a PR, never merged; deleted afterwards. `fix/28` carries no
  QML change.
- **The owner runs the four variants once, at the desktop.** Agents never
  drive the live desktop: no ai-mirror, no `hyprctl dispatch`, no synthetic
  keys, no `omarchy-restart-shell`, no touching the plugin symlink.
- **The agent reads the journal afterwards, read-only**, and posts the
  excerpt on #28 with the owner's lines.
- **Variants (c)/(d):** if Hyprland never gives the new window the keyboard
  (Exclusive keyboard focus on the Overlay layer), that is a valid "does not
  reproduce" for that variant, evidenced by the `pb28 active` lines (no
  `active false` while the panel is up).
- **Decision tree:** no repro → close #28 and update the panel plan's "Open"
  item; repro → a spec amendment on `fix/28` names the fix and goes through
  the approval gate. The debug branch is deleted either way.
- **Log lines never include typed text** (`event.text` is not logged): key
  codes, mode, object names only.

## Steps

### Agent

1. Create the local debug branch and a worktree for it (nothing pushed):

   ```bash
   git branch debug/28-esc-focus-log fix/28-esc-after-open
   git worktree add /tmp/pb28-plugin debug/28-esc-focus-log
   ```

   → verify by `git -C /tmp/pb28-plugin branch --show-current` printing
   `debug/28-esc-focus-log`, and `git config branch.debug/28-esc-focus-log.remote`
   printing nothing (no upstream).

2. In `/tmp/pb28-plugin`, `BrowserView.qml`:
   - first line of the search field's `Keys.onPressed` (line 198):
     `console.log("pb28 key", event.key, event.isAutoRepeat ? "repeat" : "", "handler=search", "mode", root.mode, "focus", Window.activeFocusItem, "help", root.helpOpen, "confirm", root.confirmOpen)`;
   - the same as the first line of `detailKeys`' `Keys.onPressed` (line
     275), with `"handler=detail"`;
   - on `root`:
     `property Item pb28Focus: Window.activeFocusItem`,
     `onPb28FocusChanged: console.log("pb28 focus", pb28Focus, "mode", root.mode)`,
     `property bool pb28Active: Window.active`,
     `onPb28ActiveChanged: console.log("pb28 active", pb28Active, "mode", root.mode)`;
   - first line of `focusForMode()` (line 62):
     `console.log("pb28 focusForMode", root.mode)`;
   - `import QtQuick.Window` only if qmllint or the run says `Window` is
     unresolved.

   `Menu.qml`:
   - first lines of `close()` (line 54):
     `console.log("pb28 close", view.mode); console.trace()`;
   - first line of `open(payloadJson)` (line 47):
     `console.log("pb28 open", payloadJson)`.

   Commit on `debug/28-esc-focus-log` only:
   `debug: pb28 focus and key logging (#28, never merge)`.
   → verify by `nix shell nixpkgs#kdePackages.qtdeclarative -c qmllint BrowserView.qml Menu.qml`
   showing 0 `[syntax]` (in `/tmp/pb28-plugin`),
   `node tests/model-check.mjs <(bash lib/catalog.sh list)` passing there,
   `git -C /tmp/pb28-plugin diff fix/28-esc-after-open --stat` listing only
   the two QML files, and `git grep -n pb28 fix/28-esc-after-open -- '*.qml'`
   empty. Then hand over to the owner (step 3) and stop.

### Owner (at the desktop, p620)

3. Load the debug build, mark the start:

   ```bash
   P=~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser
   readlink "$P" > /tmp/pb28-old-target          # today: /nix/store/…-nixarchy-plugin-browser-0.5.0
   ln -sfn /tmp/pb28-plugin "$P"
   date '+%F %T' > /tmp/pb28-start
   omarchy-restart-shell                          # BrowserState is a singleton
   echo "pb28 start" | systemd-cat -t omarchy-shell
   ```

   → verify by `readlink "$P"` printing `/tmp/pb28-plugin`, and after
   opening the panel once, `journalctl --user -t omarchy-shell -n 20 --no-pager | grep pb28`
   showing a `pb28 open` line.

4. Run each variant once. Before each, mark the journal (replace `a` with the
   letter):

   ```bash
   echo "pb28 variant a" | systemd-cat -t omarchy-shell
   ```

   `<id>` is any plugin with a GitHub repo, e.g. `crmne.hyprmoncfg`.

   - **(a) The issue's steps.** Super+Alt+U; type part of `<id>`'s name,
     Enter (details); `o` (Chrome opens, the panel closes); close the Chrome
     window; Super+Alt+U; Esc once. Expected: the panel reopened in the list
     (`open` → `reset()`), so one Esc with an empty search closes it, by
     design.
   - **(b) Reopen straight into the details.**
     `omarchy-shell shell toggle io.github.olafkfreund.nixarchy-plugin-browser '{"id":"<id>"}'`;
     Esc once. Expected: details → list, panel still open; a second Esc
     closes.
   - **(c) Outside window while the panel shows details.**
     `sleep 8; omarchy launch terminal`; within the 8 s: Super+Alt+U, Enter
     on a plugin. When the terminal maps, click it if reachable, close it
     (click or Super+W), then Esc once in the panel. Expected: details → list.
   - **(d) As (c), Chrome left open and focused by the mouse.**
     `sleep 8; omarchy launch browser https://github.com`; within the 8 s
     open the panel in the details. When Chrome maps, click into it, leave
     it open, click back on the panel card, Esc once. Expected: details →
     list.

   After each, write one line on #28: variant, what one Esc did (to the list
   / closed the panel), anything odd (e.g. the new window never got the
   keyboard). → verify by four lines on #28.

5. Restore the installed plugin and mark the end:

   ```bash
   echo "pb28 end" | systemd-cat -t omarchy-shell
   ln -sfn "$(cat /tmp/pb28-old-target)" "$P"
   omarchy-restart-shell
   ```

   → verify by `[[ $(readlink "$P") == "$(cat /tmp/pb28-old-target)" ]] && echo restored`.
   (A Home Manager switch also restores the symlink.) Tell the agent the run
   is done.

### Agent (read-only)

6. Read the journal:

   ```bash
   journalctl --user -t omarchy-shell --since "$(cat /tmp/pb28-start)" --no-pager | grep pb28
   ```

   For each variant, between its marker and the next: any `active`/`focus`
   lines before the first Esc; the `key` line for that Esc (handler, `mode`,
   focus item, repeat flag); whether a `close` line with its stack follows.
   Classify each variant's first Esc in the details as "to the list" or
   "closed", and check it matches the owner's line. For (c)/(d): no
   `pb28 active false` while the panel was up means the new window never got
   the keyboard → "does not reproduce" for that variant.
   → verify by a marker and at least one `pb28 key` line per variant. Post
   the excerpt on #28 with the classification.

7. Decision tree:
   - **No variant reproduces** (every Esc in the details went to the list;
     the only closes are from the list with an empty search or a click away;
     or (c)/(d) never lost the keyboard): comment on #28 "not reproducible on
     `4d3035a` and later" with the excerpt, and close it. On
     `fix/28-esc-after-open`, `plan/2026-09-22-4-qml-panel.md:274-276` (the
     first "Open" item) becomes a one-line pointer to that comment; commit
     `docs(plan): #28 not reproducible, link the evidence (#28)`.
     → verify by #28 closed and `git log master..fix/28-esc-after-open --stat`
     touching only `intent/`, `spec/`, `plan/`.
   - **A variant reproduces**: name the case from the journal (search
     handler got Esc in `mode` "detail"; no handler got it and a host
     `close` followed; `active` went false and back with focus on no item;
     a repeated key). Draft a spec amendment on `fix/28` naming the fix for
     that case, `status: draft`, and stop for approval. The owner later
     reruns that variant on the fixed build.

8. Cleanup (after step 5 is confirmed; either branch of step 7):

   ```bash
   git worktree remove /tmp/pb28-plugin
   git branch -D debug/28-esc-focus-log
   ```

   → verify by `git branch --list 'debug/28*'` and `git worktree list | grep pb28`
   both empty. The owner may `rm /tmp/pb28-old-target /tmp/pb28-start`.

## Tests

| Command | Expected |
| --- | --- |
| `nix shell nixpkgs#kdePackages.qtdeclarative -c qmllint BrowserView.qml Menu.qml` (debug worktree) | 0 `[syntax]` |
| `node tests/model-check.mjs <(bash lib/catalog.sh list)` (debug worktree) | passes |
| `git grep -n pb28 fix/28-esc-after-open -- ':!intent' ':!spec' ':!plan'` | empty (the docs name `pb28` themselves) |
| `git log master..fix/28-esc-after-open --stat` | only `intent/`, `spec/`, `plan/` |
| `git ls-remote origin 'debug/28*'` | empty (never pushed) |
| journal read-back (step 6) | a marker and ≥1 `pb28 key` line per variant |
| `readlink ~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser` | equals `/tmp/pb28-old-target` |
| `git branch --list 'debug/28*'` after step 8 | empty |

## Rollback

- Debug build still installed: the owner runs step 5 (or a Home Manager
  switch restores the store symlink), then `omarchy-restart-shell`.
- Debug branch: step 8. It was never pushed, so nothing remote to undo.
- The only commit that can land on `fix/28` in the no-repro branch is the
  one-line "Open" pointer in the panel plan; `git revert` it.

## Deviations

- **Outcome: closed without the live run (owner decision, 2026-09-24).**
  Step 3 was attempted once. `omarchy-restart-shell` (called by the step 3
  and step 5 helper scripts) left the desktop with no shell both times
  (17:57 and 18:01): the new instance saw the old one still tearing down
  after a plugin hot-reload, printed "already running" and exited
  (nixarchy#953). The debug build never loaded, so there is no pb28 data.
  The owner then chose the no-repro branch of the decision tree on the
  existing evidence: both sightings predate 4d3035a, after which `o`
  closes the panel and reopening starts in the list, so the reported path
  no longer exists. Config was restored byte-identical; the shell was
  brought back with a single `omarchy-launch-shell`.
- Step 8 cleanup done: `/tmp/pb28-plugin` removed, `debug/28-esc-focus-log`
  deleted (never pushed), `/tmp/pb28-*` removed.
- Lesson for any future live check here: do not call `omarchy-restart-shell`;
  the shell hot-reloads a plugin when its symlink changes.
