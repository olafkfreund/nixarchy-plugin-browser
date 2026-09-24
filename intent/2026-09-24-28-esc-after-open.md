---
status: draft
issue: 28
author: olafkfreund
---

# Intent: Esc after an outside window goes back one step, not out

## Problem

During the #4 G1 run on 2026-09-23, after `o` had opened a plugin's repo in
Chrome and the Chrome window was closed again, **one Esc closed the whole
panel** instead of going details → list. The panel plan records it under
"Open" (`plan/2026-09-22-4-qml-panel.md:274-276`), and #20 plan step 7 filed
it as #28.

What is known:

- It was seen once. In G1 part 3 (09:14) the same steps went details → list,
  with the panel still open. It was not seen without Chrome.
- The guess was that keyboard focus goes wrong after an outside window takes
  the keyboard. That is not confirmed.
- **Both runs came before `4d3035a` (09:33 the same day).** Since then `o`
  closes the panel after it launches the browser
  (`BrowserView.qml:294`, `if (BrowserState.openRepo(…)) root.closeRequested()`),
  as `e` and `f` do. So the path in the report no longer exists as it was.
  Returning to the panel now means opening it again (Super+Alt+U sends
  `'{}'`), and `Menu.open()` calls `view.reset()`, which starts in the
  list. In the list, with an empty search, one Esc closing the panel is
  the intended behaviour (G1 part 3: "details → list → clears the search →
  closes").
- The panel can still stay open while another window takes the keyboard:
  when `openRepo` refuses a repo URL and returns false, or when something
  outside the panel (a notification action, a polkit prompt, another app)
  maps a window while the panel is up. Whether Esc misbehaves after that is
  not known.

So there is no reliable reproduction, and it is not clear which build or
path the bug belongs to. A fix written now would be a guess.

## Proposed outcome

In order:

1. **A reliable reproduction, or a recorded "does not reproduce".** The
   owner runs the steps in the issue on the current build, and the variants
   listed under Open questions, at the live desktop. The result is written
   down: the build, the steps, what Esc did, and, if it can be seen, which
   item had keyboard focus.
2. **If it reproduces:** a fix, so that after any outside window has taken
   and given back the keyboard, one Esc in the details goes to the list,
   and the panel closes only from the list with an empty search. The steps
   that showed the bug are then run again and show the right behaviour.
3. **If it does not reproduce on the current build:** #28 is closed with the
   record from step 1, and the "Open" line in the panel plan points to it.
   No code changes.

## Affected users and systems

- People using the Plugin Browser panel (`Menu.qml`, `BrowserView.qml`) on
  Hyprland with the Overlay layer and `WlrKeyboardFocus.Exclusive`.
- If a fix is needed: `BrowserView.qml` focus handling (`focusForMode`, the
  `Keys.onPressed` handlers of the search field and `detailKeys`), maybe
  `Menu.qml` (`onVisibleChanged`, the layer-shell keyboard focus).
- The owner's desktop session (razer) for the reproduction.

## Constraints

- **The reproduction needs the owner at the live desktop.** Agents must not
  drive the user's live desktop (keyboard or pointer input, window or panel
  control, or toggling the shell), not even through the ai-mirror tools. A
  previous run crashed the user's shell. An agent may prepare the steps,
  read the code and logs, and read a recording the owner makes. Only the
  owner presses the keys.
- No fix before the reproduction: step 2 needs step 1's result, and the
  spec is written only after it.
- Whatever changes, these keep working as G1 recorded them: Esc details →
  list → clears the search → closes; `e`, `f` and `o` close the panel after
  launching, so their window is not hidden behind the overlay; a click away
  closes; `?` and the confirm prompt take Esc first.
- No change to the layer (`Overlay`) or to exclusive keyboard focus without
  a spec that weighs it, since `e`/`f`/`o` rely on the panel closing, not on
  sharing the keyboard.

## Open questions

- **Is the report about a path that no longer exists?** Both G1 runs came
  before `4d3035a`. On the current build, the issue's steps reopen the
  panel in the list, where one Esc closes it by design.
  *Recommendation:* yes, most likely. Run the issue's steps once on the
  current build to confirm, then test the paths where the panel really
  stays open (below).
- **Which variants should the owner run?** *Recommendation:*
  (a) the issue's steps as written, on the current build;
  (b) reopen with a payload that lands in the details
  (`omarchy-shell shell toggle io.github.olafkfreund.nixarchy-plugin-browser '{"id":"<id>"}'`),
  then Esc;
  (c) with the panel open in the details, let an outside window take the
  keyboard (for example `notify-send` with an action, or an app launched
  from another terminal onto the same workspace), close it, then Esc;
  (d) the same as (c), but with the Chrome window left open and focused by
  mouse.
  Record for each whether one Esc went to the list or closed the panel.
- **If (c) or (d) reproduces, where does the Esc go?** Only the search
  field's handler closes the panel on Esc (list mode, empty search). So the
  questions for the spec are:
  - Does `search` keep or regain active focus while `mode` is "detail"?
  - Does `detailKeys` lose active focus when the layer surface loses and
    regains the keyboard? `focusForMode()` runs only on `onVisibleChanged`,
    on mode changes, and not when keyboard focus comes back.
  - Does the host shell (omarchy-shell) close the surface itself on some
    event that looks like Esc?
  - Does one key press arrive twice (for example a repeat after the focus
    change)?
  These are questions to answer from the reproduction, not fixes.
- **How can focus be seen without an agent at the desktop?**
  *Recommendation:* a temporary debug build (spec decision) that logs
  `activeFocusItem` and `mode` on each key press to the shell journal. The
  owner runs it, and the agent reads the journal afterwards.
