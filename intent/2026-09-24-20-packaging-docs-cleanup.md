---
status: approved
issue: 20
author: olafkfreund
---

# Intent: Packaging, release and docs drift cleanup

## Problem

The 2026-09-24 review (items 19-21, 23 and 24) found a set of small problems.
None of them breaks the plugin, but together they make the flake awkward to
consume, leave fixed behaviour unreleased, and let the docs say things the
code no longer does. Each item below was checked against `master` at
`449636c`. All of them hold. One is larger than the issue says: "install.sh
asks first" appears five times, not three.

### Packaging

- **`nix run .#cli` fails.** `packages.cli` has no `meta.mainProgram`
  (`flake.nix:55-62`), so `nix run` looks for
  `bin/nixarchy-plugin-browser-cli`, and that file does not exist.
- **Only `homeManagerModules.default` is exported** (`flake.nix:69`). The
  newer convention, and the one other flakes look for, is `homeModules`.
- **The README flake snippet has no `inputs.nixpkgs.follows`**
  (`README.md:64-65`, and the same snippet in `docs/manual/getting-started.md`).
  Every consumer gets a second nixpkgs.
- **Nothing tells a manual-install user to uninstall before switching to the
  Nix install** (`README.md:57-89`). An `omarchy plugin add` checkout already
  sits at `~/.config/omarchy/plugins/<id>`, and the `~/.local/bin` symlinks
  would shadow the `cli` package.
- **`install.sh` checks prerequisites on the caller's `PATH`**
  (`install.sh:41-42`). The tools themselves pin a root-owned `PATH`
  (`bin/omarchy-plugin-audit:51`, `bin/omarchy-plugin-browser:19`,
  `bin/nixarchy-plugin-fix:22`), so the check can pass on a tool from a
  devenv or `~/.local/bin` that the tools will never see.
- **`install.sh` runs `chmod +x`** on the tools and the scanner
  (`install.sh:50`, `:54`). Git already stores them as `100755`, the scanner
  runs through `bash`, and the chmod writes into the checkout.

### Release

- **Two fixes are on `master` but unreleased.** `611ed79` makes `e`/`f`
  close the panel and makes both confirms default to No. `4d3035a` makes `o`
  close the panel. Both landed after the 0.5.0 bump (`342dfad`).
  `manifest.json:5` still says `0.5.0`, and `CHANGELOG.md:6` has no entry for
  them, so the bar's update alert never tells anyone.

### Docs drift

- **"install.sh asks first", five times.** `install.sh` never prompts. The
  claim is in `BarWidget.qml:163` and `:164`, `lib/update.sh:19-20` and
  `:199`, `README.md:109`, and `docs/update-alerts.md:44` and `:141`.
- **The manifest description is out of date** (`manifest.json:8`). It says "A
  bar button that opens a terminal browser", but the button now opens the QML
  panel (`Menu.qml`).
- **`docs/update-alerts.md` "In this plugin" is wrong** (`:134-141`):
  - it says the plugin is a "bar-only widget … that opens a terminal";
  - the cache and config paths use `omarchy-plugin-browser`, but the code
    uses `nixarchy-plugin-browser` (`lib/update.sh:35-36`);
  - it says `install.sh` asks;
  - it does not mention the Nix-install path (`BarWidget.qml:60-62`).

  The rest of the file is the cross-plugin Omarchy.Fans standard. It is
  excluded from the site (`docs/_config.yml:13`) and linked from
  `README.md:118`.
- **getting-started shows a different bind command**
  (`docs/manual/getting-started.md:23`). It gives `nixarchy-plugin <id>`,
  but the binds file the plugin ships and the Home Manager module writes
  uses `omarchy-shell shell toggle <id> '{}'`
  (`hypr/plugin-browser-binds.lua:14`).
- **The `secret-reference` capability is not documented.** The scanner emits
  it (`lib/omarchy-plugin-scan.sh:172-176`). The capability lists in
  `README.md:295` and `docs/manual/the-audit.md:35` leave it out.
- **The SHORTCUTS comments claim more than the code does**
  (`Model.js:23`, `ShortcutSheet.qml:5-6`). They say the list is shared by
  the footer hints and matched by the view. In fact the footer is a
  hard-coded string (`BrowserView.qml:424`) and the view matches keys itself
  (`BrowserView.qml:186-191`, `:264-279`). The list also misses keys the view
  answers: PageUp and PageDown, Backspace in details, and `q` in the sheet.
- **The README Layout is incomplete** (`README.md:328-346`). It leaves out
  `lib/update.sh`, `tests/preview.sh`, `docs/`, `CHANGELOG.md` and
  `preview.png`.
- **A hard-coded plugin count, "3,379 plugins that have one"**
  (`README.md:153`, `docs/manual/previews-and-privacy.md:13`), drifts with
  the marketplace.

### Dead code and noise

- **`--pause` has no caller** (`bin/omarchy-plugin-audit:34`, `:84`, `:92`,
  `:113`). Nothing in `bin/`, `lib/` or the QML passes it.
- **Two fallbacks can never be taken:**
  - the scanner and catalog "next to this script"
    (`bin/omarchy-plugin-audit:66`, `:70`). Every install layout has
    `lib/` beside `bin/`;
  - `grep -c … || echo 0` plus digit stripping
    (`bin/omarchy-plugin-audit:379-380`, `:559`). `grep -c` already prints 0.
- **The scanner emits STAT records that nothing reads**
  (`lib/omarchy-plugin-scan.sh:15`, `:32`, `:67-68`, `:287`). Its `stat()`
  function also shadows coreutils `stat` inside the scanner.
- **The same `PATH` environment is defined twice:** `childEnv` in
  `BarWidget.qml:35` and again in `BrowserState.qml:21-24`.
- **`run_fix` and `run_audit` are near-duplicates**
  (`bin/omarchy-plugin-browser:130-146`).
- **13 separate `jq` calls per detail view**
  (`bin/omarchy-plugin-browser:80-91`), where one would do.
- **Some comments and headings record review history, not intent.**
  `BrowserView.qml:80` says "found in G1 on razer", and `README.md:262` is
  headed "the corrected step list". The HANCORE review notes
  (`bin/omarchy-plugin-audit:75`, `:185`, `:299`) explain security decisions,
  so they are borderline.

### Follow-up tracking

The panel plan has two Open items with no issue
(`plan/2026-09-22-4-qml-panel.md:273-278`):

- one Esc closes the whole panel after `o` has opened a Chrome window;
- `omarchy-shell` IPC misses a running shell after a nixarchy redeploy.

## Proposed outcome

- `nix run github:olafkfreund/nixarchy-plugin-browser#cli` runs a tool.
- `homeModules.default` works as well as `homeManagerModules.default`.
- The README's Nix section has `follows` and an uninstall-first note.
- `install.sh` checks for the tools the scripts will actually use.
- 0.5.1 is released, with a changelog line for the close-on-launch and
  confirm-default-No fixes, so the update alert offers it.
- Every doc and UI string describes the current behaviour. Nothing claims
  that `install.sh` asks, and the bind command, capability list, shortcuts,
  layout and counts match the code.
- The dead options, fallbacks and duplicates are gone or explained, with no
  change in behaviour.
- The two leftover panel items are GitHub issues.

## Affected users and systems

- **Nix users:** `flake.nix` outputs and the README and manual snippets.
- **Manual installs:** `install.sh`. There is no behaviour change beyond the
  prerequisite check.
- **Everyone on 0.5.0:** the update alert, once 0.5.1 is published
  (`manifest.json`, `CHANGELOG.md`).
- **Docs and site:** `README.md`, `docs/manual/*`, `docs/update-alerts.md`.
- **Code, for the cleanup:**
  - `bin/omarchy-plugin-audit`, `bin/omarchy-plugin-browser`;
  - `lib/omarchy-plugin-scan.sh`, `lib/update.sh` (strings only);
  - `BarWidget.qml`, `BrowserState.qml`, `Model.js`, `ShortcutSheet.qml`.
- **GitHub:** two new issues.

## Constraints

- **`lib/update.sh` is a shared helper.** The same file ships in every
  Omarchy.Fans plugin, and only the "this plugin" block differs
  (`lib/update.sh:4-5`). Its generic parts stay as they are for parity. This
  includes the `mismatch` and `stale` code (`lib/update.sh:104-115`,
  `BarWidget.qml:59-65`), even though it can hardly fire in this plugin.
  Only the plugin block, and wording that is wrong for every plugin, may
  change.
- **The cleanup must not change behaviour.**
  - The audit's exit codes, JSON and verdicts stay the same.
  - The scanner's output format stays the same, apart from dropping STAT if
    that is chosen.
  - The TUI and panel keys stay the same.
  - `nix flake check` and `tests/*` pass before and after.
- **Other issues own the files they fix.** #15-#19 are open, and this issue
  avoids their hunks.
  - **Waits for #15** (audit and scanner hardening touches
    `bin/omarchy-plugin-audit` at `:146-174`, `:254`, `:313`, `:337`, `:381`,
    `:581-605`, and `lib/omarchy-plugin-scan.sh:31` onward):
    - the `grep -c` chains at audit `:379-380`, right next to the VALIDATE
      fix at `:381`;
    - the STAT and `stat()` removal, next to `emit()` at scan `:31-32`;
    - `--pause` and the dead fallbacks at audit `:66` and `:70` (same file,
      so do them after #15 merges to avoid conflicts);
    - the `secret-reference` wording, if #15 changes the capability list.
  - **Waits for #18:**
    - the `jq` chains in `bin/omarchy-plugin-browser`, because #18 fixes
      malformed catalog entries in the same script;
    - any `lib/update.sh` string edits, because #18 changes
      `UPD_KEEP_LOADED` and the fetch.
  - **Coordinate with #17:**
    - the SHORTCUTS doc and comment fixes, because #17 changes detail-key
      handling at `BrowserView.qml:260-283`;
    - `BarWidget.qml`, because of the notes fix there.
  - **Free now:**
    - `flake.nix`, the README and manual text, `install.sh`,
      `manifest.json` and `docs/update-alerts.md`;
    - the `BarWidget.qml:163-164` strings;
    - the release, and filing the two issues.
- **The flake file list stays the source of truth** for what ships
  (`flake.nix:16-29`). Nothing new goes into the plugin folder by accident.

## Open questions

1. **What to do with `docs/update-alerts.md`:**
   - delete it, since it is a cross-plugin standard kept in each repo and is
     already off the site;
   - cut it down to this plugin's section;
   - or keep it and fix only "In this plugin".

   The proposal is to fix the section and keep the standard as it is, for
   parity with the other Omarchy.Fans plugins.
2. **When to release 0.5.1:** now, with only the close-on-launch and
   confirm-default-No fixes, or bundled with the #15-#18 fixes? Releasing
   now gets the safety fix (confirms default to No) to users sooner.
3. **Is `preview.png` the marketplace listing image?** Nothing in the repo
   references it, and the flake does not ship it. If it is the listing image,
   it should be added to the README Layout. If not, delete it.
4. **The STAT records:** drop them and `stat()`, or keep them as scanner
   output for a future consumer? The proposal is to drop them after #15.
5. **The plugin count:** replace "3,379" with wording that does not drift
   ("the plugins that have one"), or keep it and update it on each release?
6. **The HANCORE review comments in the audit:** keep them as provenance for
   the security decisions, or reword them as intent?
