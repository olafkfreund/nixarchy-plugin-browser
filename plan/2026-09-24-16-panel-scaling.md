---
status: approved
issue: 16
spec: spec/2026-09-24-16-panel-scaling.md
---

# Plan: The panel follows the desktop's size and scale

This plan is self-contained; it carries every approved decision.

**Decisions**

- **The card is a share of the screen, clamped** (spec approved, question 1).
  60% of the screen's width by 70% of its height, with a floor of
  `Style.space(560)` × `Style.space(420)` and a ceiling of
  `Style.space(960)` × `Style.space(760)`. It never comes closer than
  `Style.gapsOut` to a screen edge; on a screen smaller than the floor plus
  the gaps it fills the screen minus the gaps. The shares are fixed
  properties with a `ponytail:` comment, not a setting.
- **The logic lives in `Model.js`** as a pure function, tested in
  `tests/model-check.mjs`:

  ```js
  // The card's extent along one axis: `share` of the screen, kept between
  // `floor` and `ceiling`, and never closer than `margin` to either screen edge.
  // On a screen smaller than floor + 2 * margin the card fills the screen
  // minus the margins.
  function cardExtent(screen, share, floor, ceiling, margin) {
    var room = Math.max(0, Math.round(screen - 2 * margin))
    return Math.min(room, Math.max(floor, Math.min(ceiling, Math.round(screen * share))))
  }
  ```

  Worked numbers at base font 12, `gapsOut` 10: 1280×800 → 768×560;
  1920×1080 → 960×756; 3840×2160 → 960×760; 800×600 → 560×420;
  500×400 → 480×380.
- **The card's height comes from the screen**, not from
  `view.implicitHeight`. `panel.width`/`panel.height` are Wayland logical
  pixels, so Hyprland's monitor scale is already applied, and `Style.space()`
  follows the theme's base font size. There is no setting in this plugin.
  The card keeps `y: Math.max(Style.gapsOut, Math.round((panel.height - height) / 3))`.
- **No transform.** `uiScale`, `viewWidth`, and `BrowserView`'s
  `width/height: frame.* / uiScale`, `scale:` and `transformOrigin` go.
  `BrowserView` gets `anchors.fill: parent` inside `frame`.
  `BrowserView.qml`'s `implicitWidth: Style.space(680)` and
  `implicitHeight: Style.space(520)` are deleted (nothing else reads them).
  The `Menu.qml` header comment ("the view drawn larger so it reads from a
  distance") says instead that the card is a share of the screen, drawn at
  the theme's sizes.
- **Fonts move two token steps up** (approved, question 2), on the ladder
  `caption` → `body` → `subtitle` → `title` → `heading`:

  | Where | Now | New | px at base 12 (today at 1.45×) |
  | --- | --- | --- | --- |
  | `BrowserView.qml` title (`:138`) and detail name (`:326`), bold | `font.body` | `font.heading` | 16 (17.4) |
  | `BrowserView.qml` search input (`:172`) | `font.body` | `font.title` | 14 (17.4) |
  | every `font.caption` in `BrowserView.qml` (`:150 :233 :244 :338 :348 :358 :370 :380 :395 :408 :427`) | `font.caption` | `font.subtitle` | 13 (14.5) |
  | `ShortcutSheet.qml:28` heading, bold | `font.body` | `font.heading` | 16 (17.4) |
  | `ShortcutSheet.qml:45 :53 :59` | `font.caption` | `font.subtitle` | 13 (14.5) |

  Titles stop at `heading`: the next text token is `display` (24 px).
- **`ShortcutSheet.qml` changes too** (approved, question 3). Its column
  widths grow with the text (×1.3): `Style.space(90)` → `Style.space(120)`
  (`:41`), `Style.space(170)` → `Style.space(220)` (`:49`).
- **Unchanged:** the spacing tokens, the `Style.space(40)` scroll step, the
  `Style.space(260)` preview cap, `BarWidget.qml`, every key binding, every
  `Text.PlainText`, `BrowserState.qml`, `bin/` and `lib/`.
- **Screenshots are retaken as the last step** (approved, question 4):
  `docs/img/01-list.webp` … `09-agent-warning.webp`, `tour.gif`, `tour.webm`,
  `tour-poster.webp`, with the #12 capture procedure on razer.
  `10-add-plugin-row.webp` shows the shell's Setup menu and is not retaken.
- **#17 rebases on this branch** at implementation time. The conflicts in
  `BrowserView.qml` are mechanical: take this plan's token and #17's text.
- CI wiring for `tests/model-check.mjs` belongs to #19.

## Steps

1. `tests/model-check.mjs` (test first): add `cardExtent` to the export
   list on line 11 and add:
   ```js
   // card size
   assert.equal(M.cardExtent(1280, 0.6, 560, 960, 10), 768)  // share wins
   assert.equal(M.cardExtent(3840, 0.6, 560, 960, 10), 960)  // ceiling
   assert.equal(M.cardExtent(800, 0.7, 420, 760, 10), 560)   // share, above floor
   assert.equal(M.cardExtent(600, 0.7, 420, 760, 10), 420)   // floor
   assert.equal(M.cardExtent(500, 0.6, 560, 960, 10), 480)   // room beats floor
   assert.equal(M.cardExtent(10, 0.6, 560, 960, 10), 0)      // degenerate
   ```
   → verify by `nix run nixpkgs#nodejs -- tests/model-check.mjs` **failing**
   with `cardExtent is not defined`.
2. `Model.js`: add `cardExtent` (the function above, with its comment).
   → verify by the same command printing `ok`.
3. `Menu.qml`: delete `uiScale` and `viewWidth`; add `widthShare`,
   `heightShare`, `minCardWidth`, `minCardHeight`, `maxCardWidth`,
   `maxCardHeight` with the `ponytail:` comment; `card.width`/`card.height`
   become `Model.cardExtent(panel.width, root.widthShare, root.minCardWidth, root.maxCardWidth, Style.gapsOut)`
   and the same for height; `BrowserView` loses its sizing, `scale:`,
   `transformOrigin` and their comment and gets `anchors.fill: parent`;
   rewrite the header comment.
   → verify by `grep -n "uiScale\|scale:\|implicitHeight" Menu.qml` finding
   nothing.
4. `BrowserView.qml`: delete `implicitWidth`/`implicitHeight` (`:19-20`);
   change the font tokens per the table.
   → verify by `grep -c "font.caption" BrowserView.qml` giving 0,
   `grep -c "font.subtitle" BrowserView.qml` giving 11,
   `grep -n "font.title\|font.heading" BrowserView.qml` showing `:138`,
   `:172`, `:326`, and `grep -rn "implicitWidth\|implicitHeight" *.qml`
   finding no reader of the view's size.
5. `ShortcutSheet.qml`: heading to `font.heading`, the three captions to
   `font.subtitle`, the widths to `Style.space(120)` and `Style.space(220)`.
   → verify by `grep -c "font.caption" ShortcutSheet.qml` giving 0.
6. Runtime check on p620 (this machine; three 2560×1440 outputs at
   scale 1). Load the branch into the running shell: `./install.sh --plugin`
   from the worktree, then `omarchy-restart-shell` (the `BrowserState`
   singleton survives `omarchy plugin update`). Open with Super+Alt+U.
   → verify on DP-1 (2560×1440, scale 1: card 960 × 760 at base 12):
   - the card is centred, at the ceiling, and nothing is off-screen;
   - the text is as sharp as the bar's;
   - every key in `?` works and the key sheet's labels fit their columns;
   - a click on the scrim closes the panel;
   - Enter on a plugin opens the details, and the verdicts wrap.
7. Small-screen and 4K checks on a headless output, so the real monitors are
   not touched:
   ```sh
   hyprctl output create headless PBTEST
   hyprctl keyword monitor PBTEST,1280x800@60,auto,1   # laptop size
   hyprctl dispatch focusmonitor PBTEST
   omarchy-shell shell toggle io.github.olafkfreund.nixarchy-plugin-browser '{}'
   grim -o PBTEST /tmp/pb-1280x800.png   # outside the repo
   ```
   Repeat with `800x600@60,auto,1` (floor), `560x400@60,auto,1` (room
   beats the floor), `3840x2160@60,auto,1` and `3840x2160@60,auto,2`
   (ceiling), then `hyprctl output remove PBTEST`. Screenshots go to the
   scratchpad, not the repo.
   → verify from each screenshot: 1280×800 gives a card of about 768 × 560;
   800×600 gives 560 × 420; 560×400 gives 540 × 380, the screen minus
   the gaps, with more rows elided rather than cut off; both 4K runs give a
   centred card at the ceiling (960 × 760 logical) with sharp text; the list
   shows more rows on the laptop size than the 1.45× build did.
8. Theme follow: set the theme's base font size 12 → 14 and reopen the
   panel, then restore it.
   → verify the text, spacing, floor and ceiling grow by 14/12, as the bar's
   text does, and the theme file is byte-identical afterwards.
9. Bar unaffected.
   → verify the bar button, its right click and the update popup look and
   behave as before.
10. `CHANGELOG.md` and `manifest.json`: a patch entry naming #16.
    → verify `jq . manifest.json` parses and the versions match.
11. Screenshots (last). Retake `docs/img/01`–`09`, `tour.gif`, `tour.webm`
    and `tour-poster.webp` with the #12 procedure: on razer, in its current
    theme, under ai-mirror control granted by the owner, announced on the
    bus, `gpu-screen-recorder` on eDP-1, stills cropped to the card, the
    tour in one take following the #12 script (no `o`, `c`, real `y`, or
    menu search); convert with `nix run nixpkgs#imagemagick` and
    `nix run nixpkgs#ffmpeg`. Razer needs this branch's build loaded first.
    → verify each still is under 200 KB, the GIF under 4 MB, **every still
    and every GIF frame is reviewed for private data** (noted in the PR),
    and the Pages image-exists check passes.

## Tests

- `nix run nixpkgs#nodejs -- tests/model-check.mjs` → prints `ok`.
- `grep -n "uiScale\|scale:" Menu.qml BrowserView.qml` → no output.
- `grep -c "font.caption" BrowserView.qml ShortcutSheet.qml` → `0` for both.
- Steps 6–9 runtime checks pass on p620; step 11 checks pass for the media.
- The PR's CI (Pages build, existing checks) is green.

## Rollback

Everything is in this plugin. Revert the PR's commits (`git revert`), and on
a machine that already has it run `omarchy plugin update
io.github.olafkfreund.nixarchy-plugin-browser` then `omarchy-restart-shell`.
The screenshots are reverted with the same commits. A leftover headless
output from step 7 is removed with `hyprctl output remove PBTEST`.

## Deviation (implementation, 2026-09-24)

- **Step 6, loading the branch:** `./install.sh --plugin` cannot load a
  worktree: it stops at "already registered" when the plugin dir exists, it
  needs `.git` to be a directory (it is a file in a worktree), and it relinks
  `~/.local/bin`. The branch was loaded instead by pointing
  `~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser`
  at the worktree and adding the id to `shell.json`'s `plugins` (it was
  disabled there). Both were put back afterwards, byte for byte, and the shell
  was restarted once.
- **Step 6, results:** the plugin loads with no QML warnings. On DP-2
  (2560×1440, scale 1), the card measured about 957 × 758 against the
  expected 960 × 760; it was centred and nothing was off-screen. The text is
  as sharp as the bar's. `?` opens the key sheet and its labels fit their
  columns. Details open, and the description wraps. The scrim click, a second
  Esc closing the panel, and the verdict wrap after an audit finishes were not
  exercised (no synthetic clicks on the user's live desktop); they are
  checked by hand in the PR.
- **Step 7, blocked:** on this Hyprland (0.56, Lua config),
  `hyprctl output create headless PBTEST` made omarchy-shell exit with
  "The Wayland connection experienced a fatal error: Invalid argument" (it
  restarted itself), and `hyprctl keyword monitor PBTEST,…` did not change
  the output's mode (it stayed 1920×1080 at scale 2). PBTEST was removed. It
  was not retried, so as not to crash the user's shell twice. The
  small-screen and 4K sizes rest on the `cardExtent` tests in step 1, and
  the visual check is left for razer (eDP-1) or a manual check.
- **Step 8, pending:** a user-level `~/.config/omarchy/shell.toml` with
  `[font] base-size = 14` (created and then removed; the theme file was never
  touched) triggers a full shell reload. Across two attempts the panel's
  open/close toggle got out of step with the capture, so no valid base-14
  shot exists. Left for a manual check.
- **Step 9, pending:** checked by hand. `BarWidget.qml` is not changed by
  this branch.
