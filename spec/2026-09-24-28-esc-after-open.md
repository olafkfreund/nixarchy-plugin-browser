---
status: approved
issue: 28
intent: intent/2026-09-24-28-esc-after-open.md
---

# Spec: Esc after an outside window goes back one step, not out

Approved in the intent: treat #28 as most likely fixed by `4d3035a` (`o` now
closes the panel); the owner runs the four variants once at the desktop; a
temporary debug build logs `activeFocusItem` and `mode` to the journal for the
agent to read afterwards; no fix unless it reproduces.

Decided at spec review (olafkfreund):

- **One short plan** covers: the debug commit on the local branch
  `debug/28-esc-focus-log` (never pushed, never merged), the owner's manual
  run of the four variants (the plan lists the owner's exact commands,
  including saving and restoring the plugin symlink and the journal markers),
  the agent's journal read-back, the decision tree, and cleanup (delete the
  debug branch, restore the symlink). Agents never drive the live desktop.
- **Variants (c) and (d):** if Hyprland never gives the new window the
  keyboard (the panel's `WlrKeyboardFocus.Exclusive` on the Overlay layer),
  that is a valid "does not reproduce" for that variant, evidenced by the
  `pb28 active` lines (no `active false` while the panel is up).

This spec designs the reproduction, not a fix. The plan that follows it
covers the debug commit, the owner's run and the read-back; the debug commit
waits for that plan's approval like any other edit. If it reproduces, the fix
gets its own spec amendment (see the decision tree).

## Design

### 1. The debug build (branch-only, never merged)

A branch `debug/28-esc-focus-log`, cut from `fix/28-esc-after-open`, with one
commit that only adds `console.log` lines. It is never pushed, never opened as
a PR, and deleted after the run. The `fix/28` branch itself carries no QML
change.

Every line starts with `pb28` so one `grep` finds them. Quickshell writes
`console.log` to stderr as `DEBUG qml: …`, and `omarchy-launch-shell` runs the
shell under `systemd-cat -t omarchy-shell`, so the lines land in the user
journal under that tag (checked: the journal already holds `DEBUG qml:` lines
from other plugins).

`BrowserView.qml`:

- First line of **both** `Keys.onPressed` handlers (the search field, and
  `detailKeys`):
  `console.log("pb28 key", event.key, event.isAutoRepeat ? "repeat" : "", "handler=search|detail", "mode", root.mode, "focus", Window.activeFocusItem, "help", root.helpOpen, "confirm", root.confirmOpen)`
  (the handler name written literally in each). This answers "which handler
  got the Esc", "which item had focus", and "did one press arrive twice".
- Focus changes, logged even when no key arrives:
  `property Item pb28Focus: Window.activeFocusItem` with
  `onPb28FocusChanged: console.log("pb28 focus", pb28Focus, "mode", root.mode)`,
  and `property bool pb28Active: Window.active` with
  `onPb28ActiveChanged: console.log("pb28 active", pb28Active, "mode", root.mode)`.
  The second shows the layer surface losing and regaining the keyboard, the
  moment `focusForMode()` is not re-run for today.
- `focusForMode()`: `console.log("pb28 focusForMode", root.mode)`.

`Menu.qml`:

- `close()`: `console.log("pb28 close", view.mode); console.trace()`. The
  stack shows who closed the panel: the search field's Esc (via
  `closeRequested`), the click-away `MouseArea`, `toggle()`, or the host
  calling `close()` directly.
- `open(payloadJson)`: `console.log("pb28 open", payloadJson)`.

If `Window.activeFocusItem` needs it, the commit adds `import QtQuick.Window`
to `BrowserView.qml`. About ten lines in all; `qmllint` on both files.

### 2. Loading it (the owner, not an agent)

The installed plugin is a symlink,
`~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser`
→ a `/nix/store/…-nixarchy-plugin-browser-0.5.0` path. `./install.sh --plugin`
does not repoint an already-registered plugin, so the owner does it by hand:

```bash
P=~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser
readlink "$P" > /tmp/pb28-old-target          # to put it back afterwards
ln -sfn <path of the debug/28-esc-focus-log worktree> "$P"
omarchy-restart-shell                          # BrowserState is a singleton
```

Afterwards: `ln -sfn "$(cat /tmp/pb28-old-target)" "$P"` and
`omarchy-restart-shell` again (a Home Manager switch also restores it).

### 3. The four variants (the owner runs each once)

Before each variant the owner marks the journal, so the agent can tell them
apart:

```bash
echo "pb28 variant a" | systemd-cat -t omarchy-shell
```

Replace `a` with the variant letter. `<id>` is any plugin with a GitHub repo,
for example `crmne.hyprmoncfg`.

- **(a) The issue's steps as written.** Super+Alt+U; type part of `<id>`'s
  name, Enter (details); `o` (Chrome opens, the panel closes); close the
  Chrome window; Super+Alt+U; Esc once.
  Expected on this build: the panel reopens in the list (`open` → `reset()`),
  so one Esc with an empty search closes it, by design.
- **(b) Reopen straight into the details.** From a terminal:
  `omarchy-shell shell toggle io.github.olafkfreund.nixarchy-plugin-browser '{"id":"<id>"}'`;
  Esc once. Expected: details → list, panel still open; a second Esc closes.
- **(c) An outside window while the panel is open in the details.** From a
  terminal: `sleep 8; omarchy launch terminal`; within the 8 s, Super+Alt+U,
  Enter on a plugin (details). When the new terminal maps, click it if it
  can be reached, close it (click or Super+W), then Esc once in the panel.
  Expected: details → list.
- **(d) As (c), with Chrome left open and focused by the mouse.** From a
  terminal: `sleep 8; omarchy launch browser https://github.com`; within the
  8 s, open the panel in the details. When Chrome maps, click into it and
  leave it open; click back on the panel card; Esc once. Expected: details →
  list.

For each, the owner writes one line in the issue: variant, what one Esc did
(went to the list, or closed the panel), and anything odd (for example, the
new window never got the keyboard).

### 4. Reading the result (the agent, afterwards, read-only)

```bash
journalctl --user -t omarchy-shell --since "<the time the owner started>" --no-pager | grep pb28
```

For each variant, between its marker and the next: the `key` line for the
first Esc (handler, `mode`, focus item, repeat flag), any `active`/`focus`
lines before it, and whether a `close` line with its stack follows. The agent
posts that excerpt on #28 with the owner's lines.

### 5. Decision tree

- **No variant reproduces** (every Esc in the details went to the list; the
  only closes are from the list with an empty search, or a click away; a (c)
  or (d) whose new window never got the keyboard, shown by no
  `pb28 active false` while the panel was up, counts as not reproducing):
  close #28 as "not reproducible on `4d3035a` and later", with the owner's
  lines and the journal excerpt. On `fix/28-esc-after-open`, update the
  "Open" item in `plan/2026-09-22-4-qml-panel.md:274-276` to point to that
  comment. No QML is merged. The debug branch is deleted.
- **Any variant reproduces**: the journal shows which case it is (the search
  handler got the Esc in `mode` "detail"; no handler got it and a `close`
  came from the host; `active` went false and back with focus on no item; a
  repeated key). A spec amendment on `fix/28` names the fix for that case and
  goes through the approval gate, then a plan. The owner reruns the variant
  that reproduced on the fixed build. The debug branch is deleted either way.

## Alternatives rejected

- **An agent drives the desktop** (ai-mirror, `hyprctl dispatch`, synthetic
  keys, toggling the shell). Forbidden by the intent's constraint: a
  previous run crashed the owner's shell.
- **Write a fix now** (re-run `focusForMode()` when the surface regains the
  keyboard). A guess without a reproduction; declined at the intent.
- **Keep the logging in the product, behind a setting.** A debug switch for
  one issue; the intent asks for a temporary build.
- **A screen recording instead of logs.** It shows what Esc did, not which
  item had focus or who called `close()`. The owner may record as well; the
  journal is the evidence.
- **A headless or nested compositor run by an agent.** The bug is about
  layer-shell keyboard focus on the real Hyprland session, which a nested
  run would not reproduce faithfully, and earlier headless-output work
  disturbed the live session.

## Risks

- **The debug build is left installed.** Mitigated by the restore steps and
  the saved old target; a Home Manager switch also restores it. The log
  lines only print key codes, mode and object names, nothing typed into the
  search field (`event.text` is not logged).
- **Restarting the shell** (twice) is on the owner's own terms at the
  desktop; the agent never runs `omarchy-restart-shell`.
- **(c) and (d) may not be reachable**: with `WlrKeyboardFocus.Exclusive` on
  the Overlay layer, Hyprland may keep the keyboard on the panel, so the new
  window never takes it. That is a finding in itself (the "outside window
  takes the keyboard" premise does not hold while the panel is up), recorded
  from the `pb28 active` lines, and counts as "does not reproduce" for that
  variant (decided at spec review).
- **Debug lines ship by mistake.** The branch is never pushed; the review of
  anything on `fix/28` checks `git grep pb28` is empty.
- **Host:** p620 (the owner's desktop session). No Nix or system change.

## Verification

- `git grep -n pb28 fix/28-esc-after-open` is empty; `git log
  master..fix/28-esc-after-open --stat` touches only `intent/`, `spec/`,
  `plan/` (and, on the no-repro branch, the panel plan's "Open" line).
- The debug commit passes `qmllint BrowserView.qml Menu.qml`, and
  `node tests/model-check.mjs <(bash lib/catalog.sh list)` still passes on it.
- The journal holds a `pb28 variant` marker and at least one `pb28 key` line
  for each of the four variants; each variant's first Esc in the details is
  classified as "to the list" or "closed", matching the owner's line.
- Outcome recorded on #28 (issue comment) with the excerpt; the issue is
  closed (no repro) or a spec amendment is drafted (repro).
- The installed plugin symlink points back to the store path
  (`readlink` equals `/tmp/pb28-old-target`), and the debug branch is gone
  (`git branch --list 'debug/28*'` empty).
