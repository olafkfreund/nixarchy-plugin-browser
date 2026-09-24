---
status: approved
issue: 16
intent: intent/2026-09-24-16-panel-scaling.md
---

# Spec: The panel follows the desktop's size and scale

Approved decisions this spec builds on (intent approval, `9968fc7`):

1. The card is a share of the target screen, with a floor and a ceiling in
   `Style.space()` units.
2. The 1.45 `scale:` transform goes.
3. If the panel needs more reading size, it uses larger theme font tokens, not
   a factor.

Token names below come from the `qs.Commons` Style singleton (read from the
copy at `~/.config/omarchy/plugins/omamail/app/qml/imports/qs/Commons/Style.qml`):
`Style.space(n)` = `n * spacingScale`, and `spacingScale` follows
`baseFontSize / 12`. The font tokens at the default base size of 12 are
`caption` 10, `bodySmall` 11, `body` 12, `subtitle` 13, `title` 14,
`heading` 16. `Style.gapsOut` is not in that copy. `Menu.qml:91` uses it
already, so the real shell's Style has it.

## Design

### 1. Card size: a share of the screen, clamped (`Menu.qml`)

Delete `uiScale` (`Menu.qml:27`) and `viewWidth` (`Menu.qml:28`). Add:

```qml
// ponytail: fixed shares; a setting only if someone asks for one
readonly property real widthShare: 0.6
readonly property real heightShare: 0.7
readonly property int minCardWidth: Style.space(560)
readonly property int minCardHeight: Style.space(420)
readonly property int maxCardWidth: Style.space(960)
readonly property int maxCardHeight: Style.space(760)
```

`card.width` and `card.height` (`Menu.qml:86-89`) become:

```qml
width:  Model.cardExtent(panel.width,  root.widthShare,  root.minCardWidth,  root.maxCardWidth,  Style.gapsOut)
height: Model.cardExtent(panel.height, root.heightShare, root.minCardHeight, root.maxCardHeight, Style.gapsOut)
```

A new pure function in `Model.js`:

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

The card no longer depends on `view.implicitHeight`. The height comes from the
screen, and the view fills whatever room it gets. `panel.width` and
`panel.height` are Wayland logical pixels, so Hyprland's monitor scale is
already applied. `Style.space()` follows the theme's base font size. The two
together give the "follows the desktop" behaviour the intent asks for, with no
setting in this plugin.

The card keeps `y: Math.max(Style.gapsOut, Math.round((panel.height - height) / 3))`
(`Menu.qml:91`). That puts it a third of the way down, never above the gap.
Because `cardExtent` leaves at least `margin` on each side, the card's bottom
edge now stays on screen as well.

Worked numbers at base font size 12 (`Style.space(n) = n`), `gapsOut` taken as 10:

| Screen (logical) | Example | Card |
| --- | --- | --- |
| 1280 × 800 | 1920×1200 laptop at scale 1.5 | 768 × 560 |
| 1920 × 1080 | 4K at scale 2 | 960 × 756 (width at ceiling) |
| 3840 × 2160 | 4K at scale 1 | 960 × 760 (both at ceiling) |
| 800 × 600 | small window or odd scale | 560 × 420 (both at the floor) |
| 500 × 400 | smaller than the floor | 480 × 380 (fills the screen minus the gaps) |

### 2. No transform (`Menu.qml:108-119`)

`BrowserView` loses `width: frame.width / root.uiScale`,
`height: frame.height / root.uiScale`, `scale: root.uiScale` and
`transformOrigin: Item.TopLeft`, and the comment above them goes as well. It
gets `anchors.fill: parent` inside `frame`. Text is drawn at its real pixel
size, so it renders as sharp as the bar's. Input needs no mapping.

`BrowserView.qml:19-20` (`implicitWidth: Style.space(680)`,
`implicitHeight: Style.space(520)`) are deleted. Nothing reads them once
`Menu.qml:88` stops using `view.implicitHeight`: a grep for `implicitHeight`
and `implicitWidth` across the `*.qml` files finds no other reader of the
view's own size. The header comment at `Menu.qml:11-12` ("the view drawn
larger so it reads from a distance") is changed to say the card is a share of
the screen, drawn at the theme's sizes.

### 3. Reading size: two token steps up (`BrowserView.qml`, `ShortcutSheet.qml`)

Without the transform, text drops from 1.45× to 1× the theme's size. Caption
text goes from 14.5 px to 10 px at base 12, which is smaller than the bar's
body text. Following decision 3 and the approver's answer to question 2
(two steps, not one), the panel moves two steps up the ladder this spec
counts in (`caption` → `body` → `subtitle` → `title` → `heading`):

| Where | Now | New | Now at 1.45× | New px (base 12) |
| --- | --- | --- | --- | --- |
| Title `BrowserView.qml:138`, detail name `:326` | `font.body` bold | `font.heading` bold | 17.4 | 16 |
| Search input `:172` (the placeholder inherits it) | `font.body` | `font.title` | 17.4 | 14 |
| Every `font.caption` in `BrowserView.qml` (header count `:150`, rows `:233` `:244`, detail text `:338` `:348` `:358` `:370` `:380` `:395` `:408`, footer `:427`) | `font.caption` | `font.subtitle` | 14.5 | 13 |
| `ShortcutSheet.qml:28` heading | `font.body` bold | `font.heading` bold | 17.4 | 16 |
| `ShortcutSheet.qml:45` `:53` `:59` | `font.caption` | `font.subtitle` | 14.5 | 13 |

Titles stay at `font.heading`: it is the largest text token below
`display` (24 px), and `iconLarge` is an icon size, so there is no
second step for them. Body text lands at about 0.9× of today's size
(13 px against 14.5 px), a little above the rest of the shell's panel
text. A larger theme base size still makes all of it larger.
`ShortcutSheet.qml` is included (approved, question 3): it is drawn inside
`BrowserView`, so it also loses the 1.45× today. Its column widths
`Style.space(90)` and `Style.space(170)` (`ShortcutSheet.qml:41`, `:49`)
grow by the same 1.3 as the text (10 → 13 px), to `Style.space(120)` and
`Style.space(220)`, so the longest key labels still fit.

The spacing tokens (`Style.spacing.*`), `Style.space(40)` scroll step
(`BrowserView.qml:110`) and the preview cap `Style.space(260)` (`:310`) stay
as they are. They were scaled 1.45× before and now are not. The preview's
height is capped at `Style.space(260)`, and the card's height now comes from
the screen, so a larger share of the detail pane goes to text.

### 4. Small screens use the room

The list's height is `parent.height - y - footer.height - Style.spacing.md`
(`BrowserView.qml:205`), so it gets every pixel of the card and shows more
rows. Detail text already wraps (`wrapMode: Text.Wrap` on the description,
the verdicts and the report lines). List rows keep `elide: Text.ElideRight`
(one plugin, one row), and they elide later because the text is smaller than
it was at 1.45×. No layout change is needed beyond items 1 to 3.

### Unchanged

`BarWidget.qml`, every key binding, every `Text.PlainText`, `BrowserState.qml`,
and the scripts in `bin/` and `lib/`.

## Alternatives rejected

- **Keep 1.45 and compute it from the screen** (for example
  `uiScale = panel.width / 1280`). This keeps the transform, and the
  transform is what makes the text soft. It also ignores the theme's base
  font size. Rejected by decision 2.
- **Scale the font tokens by a factor** (`Style.font.caption * 1.45`). This
  gives crisp text, but it is still a private zoom that ignores the theme's
  own scale steps. Rejected by decision 3.
- **The card fills a fixed 90% × 85% of the screen** (the current caps,
  applied without a view size). On 4K at scale 1 that gives 3456 px lines
  of 12 px text. The ceiling exists to stop that.
- **Share only, no floor.** On a 1280 × 800 laptop 60% is fine, but on a
  small window or a portrait screen 60% of 800 wide is 480, too narrow for a
  row plus its stars. The floor keeps it usable, and `room` still stops the
  floor from pushing the card off-screen.
- **Height from the content (`view.implicitHeight`), as now.** This needs the
  view to report a natural height, which is the fixed `Style.space(520)`
  this intent removes. A list has no natural height.
- **The sizing inline in QML, with no `Model.js` function.** It would work,
  but `tests/model-check.mjs` could not test the clamp. `Model.js` is where
  this repo keeps logic it tests.

## Risks

- **Docs screenshots (#12).** `docs/img/01-list.webp` to `09-agent-warning.webp`,
  `tour.gif`, `tour.webm` and `tour-poster.webp` show the 1.45× panel.
  After this change the card is larger relative to its text, and the text is
  a little smaller. They are retaken with the #12 capture procedure on
  razer as the last step of this plan (approved, question 4), so the PR
  does not merge with images that do not match the build.
  `10-add-plugin-row.webp` shows the shell's Setup menu, not this panel,
  and is not retaken.
- **Slightly smaller text than today.** At base 12, body text goes from
  14.5 px to 13 px and titles from 17.4 px to 16 px. The approver chose two
  steps so the text is not smaller than today; at base 12 it is still about
  10% smaller, because the theme has no token at 14.5 px. The remedy is the
  theme's base font size (at base 13, `subtitle` is 14 px), not a factor.
- **`Style.gapsOut` in the real shell.** The Style copy used here does not
  define it. `Menu.qml:91` already relies on it, so the risk is low. If it
  were ever missing, `cardExtent` would get `undefined`, `room` would be
  `NaN`, and the card would have no size. The margin argument could fall back
  to `Style.spacing.huge`. That fallback is left out because the existing
  code already depends on `gapsOut`.
- **Wide ceiling on ultrawide screens.** On a 5120 × 1440 screen the card is
  960 × 760 (height at ceiling), which is intended.
- **Sibling plugins.** `nixarchy.podman` and others copied the same
  `uiScale: 1.45` pattern. They are out of scope. This change makes the
  Plugin Browser look different from them until they follow.
- **#17 rebases on this.** #17 edits `BrowserView.qml` (the footer, the detail
  pane). The token changes in item 3 touch many lines in `BrowserView.qml`,
  so the rebase will have conflicts. They are mechanical: take the new token
  and #17's text.

## Verification

- **`tests/model-check.mjs`:** add `cardExtent` to the export list on line 11,
  and add asserts:
  - share wins in range: `cardExtent(1280, 0.6, 560, 960, 10) === 768`;
  - ceiling: `cardExtent(3840, 0.6, 560, 960, 10) === 960`;
  - floor: `cardExtent(800, 0.7, 420, 760, 10) === 560` and
    `cardExtent(600, 0.7, 420, 760, 10) === 420`;
  - room beats floor: `cardExtent(500, 0.6, 560, 960, 10) === 480`;
  - degenerate: `cardExtent(10, 0.6, 560, 960, 10) === 0`.
  Run `nix run nixpkgs#nodejs -- tests/model-check.mjs`. It passes.
- **Grep checks:** `grep -n "uiScale\|scale:" Menu.qml BrowserView.qml` finds
  nothing, and `grep -c "font.caption" BrowserView.qml ShortcutSheet.qml`
  gives 0 for both files.
- **Manual runtime check, laptop size:** on a screen with a logical size of
  about 1280 × 800 (razer's panel, or `hyprctl keyword monitor` set to scale
  1.5 on a 1920 × 1200 screen), open the panel with Super+Alt+U.
  - The card is about 60% × 70% of the screen.
  - The text is as sharp as the bar's.
  - The list shows more rows than before.
  - Every key in `?` works, and the key sheet fits.
  - A click on the scrim closes the panel.
  - Open a plugin's details with Enter, and check the verdicts wrap.
- **Manual runtime check, 4K size:** on a 3840 × 2160 output at scale 1, and
  again at scale 2 (a real 4K output, or a headless Hyprland output of that
  size), check the card is at the ceiling (960 × 760 logical at base 12), is
  centred, and has sharp text.
- **Theme follow:** change the theme's base font size (for example 12 → 14)
  and reopen the panel. The text, the spacing and the floor and ceiling all
  grow by 14/12, as the bar's text does.
- **Bar unaffected:** the bar button and its update popup look as they did
  before.
- CI wiring for `tests/model-check.mjs` belongs to #19 and is not in scope here.

## Approver decisions (olafkfreund, 2026-09-24)

1. **Share and limits:** approved. 60% × 70% of the screen, floor
   `Style.space(560)` × `Style.space(420)`, ceiling `Style.space(960)` ×
   `Style.space(760)`.
2. **Token step:** two steps up, not one, so the text is not smaller than
   today (item 3 above; see the risk on how close base 12 gets).
3. **`ShortcutSheet.qml`:** changes too.
4. **Screenshots:** retaking `docs/img/01`–`09` and the tour is the last
   step of the #16 plan.
