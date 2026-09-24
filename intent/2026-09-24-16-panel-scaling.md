---
status: approved
issue: 16
author: olafkfreund
---

# Intent: The panel follows the desktop's size and scale

## Problem

The Plugin Browser surface ignores the screen it opens on and the theme's
text sizes. In the user's words: "the text and the windows need to follow the
desktop size and scale". From review item 8:

- **A fixed zoom factor.** `Menu.qml:27` hard-codes `uiScale: 1.45`. Every
  piece of text and spacing in the panel is drawn 1.45 times the theme's size,
  whatever the theme or the screen says.
- **A fixed-size view, enlarged by a transform.** `BrowserView.qml:19-20` lays
  the view out at `Style.space(680)` × `Style.space(520)`, and
  `Menu.qml:108-115` lays it out at `frame / uiScale` and then draws it with a
  `scale:` transform. Text drawn through a scale transform is rasterised at
  one size and stretched, so it renders soft next to the rest of the shell.
- **The same size on every screen.** The card is `viewWidth * uiScale`
  (`Menu.qml:86-89`), which does not depend on the screen. On a 4K display it
  is a small island in the middle; on a laptop it hits the 90% × 85% cap.
- **On a small screen the frame shrinks but the text does not.** When the cap
  applies (`Menu.qml:87`, `:89`), the view gets less room but is still drawn at
  1.45×, so fewer rows fit and long lines are cut off, rather than the layout
  using the space it has.
- **The rest of the shell already gets this right.** The `qs.Commons` Style
  singleton scales `Style.space()` and `Style.font.*` by the theme's
  `baseFontSize / 12`, and Hyprland's monitor scale reaches QML as Wayland
  logical pixels. `BarWidget.qml` and `ShortcutSheet.qml` use those tokens and
  nothing else. Only the menu's own layer overrides them.

## Proposed outcome

- The panel is sized relative to the screen it opens on: a larger screen
  gives a larger card, a laptop screen a smaller one, with no part of it
  off-screen.
- Text is drawn at the theme's own sizes (`Style.font.*`), crisp, the same
  sharpness as the bar and the other nixarchy panels, on a laptop and on 4K
  alike.
- Changing the theme's base font size, or the monitor scale in Hyprland,
  changes the panel the same way it changes the rest of the shell, with no
  setting in this plugin.
- On a small screen the layout uses the room it has (more rows or wrapped
  lines), instead of shrinking the frame around oversized text.
- The bar button and its update popup (`BarWidget.qml`) are unaffected.

## Affected users and systems

- Everyone who opens the Plugin Browser surface (Super+Alt+U, the Add Plugin
  menu row, the bar button), in particular on HiDPI, 4K or small laptop
  screens, and anyone with a non-default theme font size.
- This repo: `Menu.qml` (the scale factor and the card size) and
  `BrowserView.qml` (its fixed implicit size). `ShortcutSheet.qml` and
  `BarWidget.qml` are expected to stay as they are.
- `docs/` screenshots taken with the 1.45× panel (issue #12) may look
  different afterwards.
- Relies on omarchy-shell's `qs.Commons` Style and Quickshell's
  `PanelWindow` / screen geometry. No change to the shell itself.

## Constraints

- Keyboard-first design and every key binding stay exactly as they are.
- All marketplace and audit text stays `Text.PlainText`.
- No new dependencies, and nothing outside this plugin changes: it must work
  in omarchy-shell's plugin host as it is today.
- Sizes come from the shell's tokens (`Style.space()`, `Style.font.*`,
  `Style.spacing.*`) and the screen's logical size, not new hard-coded pixel
  values.
- Issue #17 also edits `BrowserView.qml`; this task lands first and #17
  rebases on it.

## Open questions

- **Share of the screen.** What fraction of the screen should the card take,
  for example about 60% wide by 70% high, or keep the current 90% × 85% as
  the upper bound only?
- **Limits.** A minimum size, below which the card fills the screen, and a
  maximum, so a 4K or ultrawide screen does not give a card with very long
  lines? If so, in theme units (`Style.space`) or as a share of the screen?
- **"Reads from a distance".** The 1.45× was chosen so the surface reads from
  a distance (`Menu.qml:12`). Keep that by using larger font tokens
  (`Style.font.subtitle`, `heading`) inside the menu, drop it and use the
  same sizes as the rest of the shell, or leave it to the theme's base size?
