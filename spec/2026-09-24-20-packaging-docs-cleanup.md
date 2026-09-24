---
status: approved
issue: 20
intent: intent/2026-09-24-20-packaging-docs-cleanup.md
---

# Spec: Packaging, release and docs drift cleanup

## Design

The work is split into two phases, following the ownership rules in the
intent. Phase A touches only files that no open issue owns, so it can merge
now and releases 0.5.1. Phase B waits for #15, #17 and #18 to merge, then
re-checks its line numbers against `master` before it edits anything.

The approved decisions from the intent:

- release 0.5.1 now;
- in `docs/update-alerts.md`, fix only the "In this plugin" section;
- reword the plugin count so it cannot drift;
- keep `preview.png` and document it as the marketplace image;
- keep the STAT records and `stat()`: #15 relies on the `STAT scan complete`
  marker, so they are not removed, and `stat()` is left as it is unless #15
  changes it;
- keep the HANCORE comments, reworded to state intent.

The spec-review decisions (the former approver questions):

- the shared "install.sh asks" wording in `lib/update.sh` and
  `docs/update-alerts.md` is not changed here. A separate issue is filed
  upstream, in `OmarchyFans/omarchy-fans-help`, the reference implementation
  named in `docs/update-alerts.md:10-11`;
- getting-started keeps `nixarchy-plugin <id>` and gains the clarifying
  sentence;
- `install.sh` keeps `chmod +x`, but only runs it when the file is not
  already executable, which is safer for zip downloads;
- #18 now changes the terminal UI's copy command and the `jq` chain area, so
  every phase B item in `bin/omarchy-plugin-browser` waits for #18.

All line numbers below were checked on `26216da`, which has the same code as
`master` at `449636c`.

### Phase A: can go now

**A1. `flake.nix`: `nix run .#cli`.** Add `meta.mainProgram =
"omarchy-plugin-browser";` to the `runCommand` attribute set in `cliFor`
(`flake.nix:56`). That set is `{ }` today. The TUI is the natural default,
and the other two tools stay on `PATH` from the same package.
`nix run .#cli -- --help` then prints the TUI help (`bin/omarchy-plugin-browser:31`).

**A2. `flake.nix`: the `homeModules` alias.** Add
`homeModules = self.homeManagerModules;` next to `flake.nix:69`. This is one
line, so there is only one module to maintain. The README and manual
snippets keep `homeManagerModules.default`, so nobody's config changes. The
outputs table (`README.md:85`, `docs/manual/getting-started.md:72`) gains
"(also `homeModules.default`)".

**A3. README and getting-started: `follows` and uninstall first.**

- Below the input line (`README.md:65`, `docs/manual/getting-started.md:46`),
  add `nixarchy-plugin-browser.inputs.nixpkgs.follows = "nixpkgs";`.
- Above the snippet in "Install with Nix" (`README.md:57-62`), add one
  paragraph: "Installed it with `install.sh` or `omarchy plugin add` before?
  Run `./uninstall.sh` from that clone first." That script removes the
  `~/.local/bin` symlinks and the `~/.config/omarchy/plugins/<id>` checkout
  (`uninstall.sh:8-16`). Without that step, the symlinks shadow the `cli`
  package and the checkout sits where nixarchy links the plugin.

**A4. `install.sh`: check prerequisites where the tools look.**

- At `install.sh:41-42`, run the checks with the same root-owned `PATH` the
  tools pin (`bin/omarchy-plugin-audit:51`):
  `TOOL_PATH="/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-}/bin"`,
  then `PATH="$TOOL_PATH" command -v "$c"`. A prefix assignment on
  `command -v` changes the lookup only for that call. This was checked in
  bash: `PATH=/nonexistent command -v ls` returns 1.
- Add one comment line saying the string must match the tools' own `PATH`
  line.
- The failure message names the missing tools and points at
  `nixarchy pkg add …`, as the bwrap note already does.
- Keep both `chmod` lines (`install.sh:50`, `:54`), guarded so they only
  write when the bit is missing: `[[ -x $src ]] || chmod +x "$src"`, and the
  same for the scanner. Git already stores them as `100755`, so a git clone
  is never written to; a zip download without modes still gets fixed.

**A5. `manifest.json:8`: the description.** Replace "A bar button that opens a
terminal browser" with "A bar button and a full-screen panel (Super+Alt+U)".
The rest of the sentence stays.

**A6. Release 0.5.1.**

- Set `manifest.json:5` to `0.5.1`. The flake takes its version from there
  (`flake.nix:11`).
- Add a `## 0.5.1` section above `CHANGELOG.md:6`, with one short line per
  bullet, as the file's header asks:
  - "e, f and o close the panel, so the terminal or browser they open gets the keyboard" (`611ed79`, `4d3035a`);
  - "Both confirms before an agent runs or a workspace is deleted now default to No" (`611ed79`);
  - "Nix: `nix run …#cli` works, `homeModules.default` is exported" (A1, A2).
- The version bump is the last commit of phase A. The update alert reads
  `manifest.json` on `master`, so merging it is the release. There are no
  git tags or GitHub releases in this repository.

**A7. Docs drift.** Each item edits text only.

- **"asks first" in this plugin's own text:**
  - `BarWidget.qml:163`: "…then install.sh relinks the commands."
  - `BarWidget.qml:164`: "Run install.sh once so the linked commands match. It only relinks this plugin's commands."
  - `README.md:109`: "then `install.sh`, which relinks the commands without asking."
  - `docs/update-alerts.md:141`: the "In this plugin" bullet.

  `lib/update.sh:19-20`, `lib/update.sh:199` and `docs/update-alerts.md:44`
  are not edited. They are the shared, cross-plugin text, and for other
  plugins "install.sh asks" can be true. The wording is raised upstream
  instead (A8). The intent's outcome "nothing claims install.sh asks" is
  narrowed to this plugin's own text.
- **`docs/update-alerts.md` "In this plugin" (`:134-141`), rewritten to match
  the code:**
  - "Kind: bar widget (`BarWidget.qml`) plus a full-screen panel (`Menu.qml`)";
  - cache `~/.cache/nixarchy-plugin-browser/update-check.json` and config
    `~/.config/nixarchy-plugin-browser/config.json`, from `lib/update.sh:35-36`;
  - `install.sh` relinks without asking;
  - a Nix install (no `.git`) gets the "update with nix flake update" text in
    place of the Update button (`BarWidget.qml:60-62`).

  Nothing else in the file changes.
- **Bind command (`docs/manual/getting-started.md:23`).** `nixarchy-plugin`
  is a real nixarchy command (`/run/current-system/sw/bin/nixarchy-plugin`).
  `docs/manual/the-panel.md:59` documents it, and it reports a plugin that is
  turned off. So the line is kept as it is, and one sentence is added after it:
  "The binds file this plugin ships uses
  `omarchy-shell shell toggle <id> '{}'` (`hypr/plugin-browser-binds.lua:14`).
  Both open the same panel."
- **`secret-reference`.**
  - `README.md:295-296`: add `secret-reference` to the capability list.
  - `docs/manual/the-audit.md:35`: add "mentions of secrets or tokens" to the
    "review required" row.

  If #15 changes the capability list first, this item follows #15's list.
- **README Layout (`README.md:328-346`).** Add these rows:
  - `lib/update.sh`: the update check, shared with the other Omarchy.Fans plugins;
  - `tests/preview.sh`;
  - `tests/model-check.mjs`;
  - `docs/`: the manual and the GitHub Pages site;
  - `CHANGELOG.md`: read by the update alert;
  - `preview.png`: the marketplace listing image, not shipped by the flake.
- **Plugin count.** `README.md:153` becomes "for the plugins that have one".
  `docs/manual/previews-and-privacy.md:13-14` becomes "if it has one". No
  number is left.
- **Review history in docs.** `README.md:262`: drop "— the corrected step
  list". The heading becomes "How the audit works".

**A8. File the two leftover panel items** (`plan/2026-09-22-4-qml-panel.md:273-278`)
as GitHub issues:

- "Esc closes the whole panel after `o` opened a Chrome window" (needs a repro);
- "`omarchy-shell` IPC misses a running shell after a nixarchy redeploy (matches on `$OMARCHY_PATH/shell`)".

Each issue links back to the plan lines. The plan's Open list gets the two
issue numbers, in the same PR.

A third issue goes to `OmarchyFans/omarchy-fans-help`, where the shared
helper's reference copy lives (`docs/update-alerts.md:10-11`): "install.sh
asks" in `lib/update.sh` (header and the `run` step) and in
`docs/update-alerts.md` is not true for every plugin, so the shared wording
should become "may ask" or similar. It is filed at implementation time and
linked from this issue.

### Phase B: after #15, #17 and #18 merge

Each item below starts by re-reading the lines, because those PRs will move
them. None of them changes behaviour.

**B1. `bin/omarchy-plugin-audit`, after #15.**

- **`--pause`.** Remove the help line (`:34`), `PAUSE=0` (`:84`), the case
  arm (`:92`) and the pause branch in `finish()` (`:113`). `finish` keeps
  `exit "$1"`. The step is: grep `bin/ lib/ *.qml Model.js docs/` for
  `--pause`, expect no match, then edit.
- **The dead fallbacks** (`:66`, `:70`). Delete the `SELF_DIR/…` fallback
  lines. Every layout, the clone, the plugin folder and the `cli` wrapper
  (which execs `${plugin}/bin/<tool>`, `flake.nix:59`), has `lib/` beside
  `bin/`. The `die … not found` guards stay, reworded to "not found in
  ../lib".
- **The `grep -c` chains** (`:379-380`, `:559`). Rewrite them as
  `n_find=$(grep -c … "$RAW" 2>/dev/null) || :; n_find=${n_find:-0}`.
  `grep -c` prints `0` and exits 1 on no match. The `|| echo 0` then
  appended a second `0`, which is why the digit stripping existed.
- **The HANCORE comments** (`:75`, `:185`, `:299`). Each one is reworded to
  lead with the rule it enforces, for example "Staging is bounded in time,
  bytes and file count before the sandbox starts, so a hostile target cannot
  hang or fill the disk". The review reference is kept as a trailing
  "(from HANCORE-linux's review, #5581 v2)".

**B2. `lib/omarchy-plugin-scan.sh`: no change.** The STAT records and
`stat()` stay, because #15 relies on the `STAT scan complete` marker
(`:287`). `stat()` is not renamed unless #15 changes it.

**B3. `bin/omarchy-plugin-browser`, after #18.** #18 changes the terminal
UI's copy command and the `jq` chain area, so both items below wait for it
and re-read the script after it merges.

- **`run_fix` and `run_audit`** (`:130-146`) become one
  `run_tool <script> <id>`. The id check, the `bash` call and the "Enter to
  return" prompt are shared. The two call sites pass `nixarchy-plugin-fix` or
  `"$AUDIT"`.
- **`show_detail`** (`:80-91`): the 13 `jq` calls become one `jq -r` that
  prints the fields tab-separated, read with `IFS=$'\t' read -r …`. Each
  field goes through `gsub("[\t\n]"; " ")` first, so a hostile description
  cannot shift the columns. #18's malformed-entry guard stays in front of it.

**B4. SHORTCUTS, coordinated with #17.**

- `Model.js:23` becomes "The keys the shortcut sheet lists. The view matches
  keys itself (BrowserView.qml) and the footer is its own string, so keep all
  three in step."
- `ShortcutSheet.qml:5-6` is reworded to match.
- Add the keys the view answers that the list misses:
  - List: `PgUp PgDn`, "move ten" (`BrowserView.qml:188-189`);
  - Details: `Esc ← Backspace`, "back to the list" (`:270`);
  - Anywhere: "`q` closes this sheet", in the `?` row (`:116`).

  These are rechecked against #17's final key handling.

**B5. Duplicated `PATH`, coordinated with #17.** `BrowserState.qml:21-24`
already says "The same root-owned PATH the bar widget gives its children". A
matching note goes at `BarWidget.qml:35` ("also in BrowserState.qml
childEnv"). Both copies stay. See alternatives.

**B6. `BrowserView.qml:80`, coordinated with #17.** Drop "(found in G1 on
razer)". The comment keeps the behaviour it explains.

## Alternatives rejected

- **`mainProgram` as `omarchy-plugin-audit`.** The audit needs a target and
  exits with an error on its own. The browser is the tool a first-time
  `nix run` user wants.
- **Three `apps.<system>.*` outputs.** More outputs to keep in step for no
  new capability. `nix shell .#cli` already gives all three tools.
- **Renaming the module to `homeModules` and dropping `homeManagerModules`.**
  That breaks every existing consumer. The alias costs one line.
- **Sourcing the pinned `PATH` from one shared file in `install.sh`.** There
  are three copies in `bin/` already, plus two in QML. A sixth copy with a
  "must match" comment is cheaper than a new sourced file for a shell
  installer.
- **A shared `childEnv` in `Model.js` or a QML singleton.** It would add an
  import to `BarWidget.qml` and plumb `Quickshell.env` into pure JS, to save
  two lines that already point at each other.
- **Editing `lib/update.sh` and the generic part of `update-alerts.md`.**
  This breaks parity with the other Omarchy.Fans plugins, and the approver
  chose "In this plugin" only.
- **Bundling 0.5.1 with #15-#18.** Rejected by the approver. The
  confirm-default-No fix should reach users now.
- **Updating "3,379" on each release.** Rejected by the approver. The
  number drifts between releases anyway.
- **Removing `chmod +x` from `install.sh`.** Rejected by the approver. A zip
  download has no modes, and the guarded chmod costs nothing on a git clone.
- **Replacing the getting-started bind line with the `omarchy-shell` form.**
  Rejected by the approver. `nixarchy-plugin <id>` is nixarchy's own command
  and works; the added sentence names the other form.
- **Dropping the STAT records and `stat()`.** Rejected: #15 relies on the
  `STAT scan complete` marker.
- **Deleting `preview.png`, or shipping it in the flake.** It is the
  marketplace image, so it stays. The plugin does not need it at runtime, so
  it stays out of `files` (`flake.nix:16-28`).

## Risks

- **`nix flake check` may warn "unknown flake output 'homeModules'"** on older
  Nix versions. It is a warning, not an error. Newer Nix and flake-parts know
  the name.
- **The new `install.sh` check can fail where the old one passed.** This
  happens when `gum`, `jq` and the rest are only in a devenv or in
  `~/.local/bin`. That is the point of the change, since the tools could not
  have run there, but the message has to say what to install. On non-NixOS
  hosts the pinned `PATH` does not exist. The plugin already targets nixarchy
  only (`bin/*` pin the same `PATH`), so this is not a regression.
- **The guarded `chmod +x`.** `[[ -x ]]` is true on a normal clone, so a git
  clone is never written to. A zip download or a `core.fileMode=false` clone
  still gets the bit set, as before.
- **The 0.5.1 update alert fires for everyone on 0.5.0 as soon as phase A
  merges.** This is intended. Everything user-visible that 0.5.1 claims must
  be in that merge.
- **Phase B line numbers will move** after #15, #17 and #18. Every B step
  starts by re-locating its lines with grep. The numbers above are only for
  review.
- **B3's single `jq`.** A field that contains a tab or newline could shift the
  columns. The `gsub` guards against it, and it is tested with a fixture entry
  whose description has a tab.

## Verification

Phase A:

- `nix flake check` passes. It runs `tests/scan-nix.sh` and
  `tests/model-check.mjs` against the package, and asserts there are no
  symlinks and no repo-only files.
- `nix run .#cli -- --help` prints the `omarchy-plugin-browser` help and
  exits 0.
- `nix eval .#homeModules.default --apply builtins.isFunction` prints `true`.
- `bash tests/catalog-list.sh` and `bash tests/preview.sh` pass, as before.
- `jq -r .version manifest.json` prints `0.5.1`, and `CHANGELOG.md` has
  `## 0.5.1` as its first section.
- These greps return nothing:
  - `grep -n "asks first\|asks again\|asks before changing" BarWidget.qml README.md`
  - `sed -n '/^## In this plugin/,$p' docs/update-alerts.md | grep -n "asks\|omarchy-plugin-browser/\|terminal"`
  - `grep -rn "3,379\|3379 of" README.md docs/manual`
  - `grep -n "corrected step list" README.md`
  - `grep -n "opens a terminal browser" manifest.json`
  - `grep -nE "^\s*chmod" install.sh` (every chmod sits behind `[[ -x … ]] ||`)
- These greps return a match:
  - `grep -n "follows" README.md docs/manual/getting-started.md` (one each);
  - `grep -n "secret-reference" README.md`;
  - `grep -n "preview.png\|lib/update.sh\|CHANGELOG.md" README.md`, for the
    Layout block.
- On this host, where every prerequisite is in the system profile,
  `./install.sh` succeeds as before, and `ls -l ~/.local/bin/omarchy-plugin-*`
  shows the links.
- Run the check loop with `TOOL_PATH` pointed at an empty directory. It must
  fail and name all five tools, even though they are on the caller's `PATH`.
  This proves the lookup ignores the caller's `PATH`.
- The two issues exist, and the plan's Open list cites them.
- The upstream issue exists in `OmarchyFans/omarchy-fans-help` and is linked
  from #20.

Phase B, for each item:

- `nix flake check` and all of `tests/*` pass.
- `grep -rn -- "--pause" bin lib` returns nothing.
- `grep -c "STAT" lib/omarchy-plugin-scan.sh` is unchanged (kept for #15).
- `grep -n "|| echo 0" bin/omarchy-plugin-audit` returns nothing.
- `grep -n "found in G1" BrowserView.qml` returns nothing.
- `omarchy-plugin-audit --json` on a fixture plugin gives the same JSON before
  and after, diffed with `jq -S`. This covers the tally rewrite.
- The TUI details view for a real entry, and for a fixture entry with a tab in
  its description, shows the same fields as before.
- `tests/model-check.mjs` still finds the `?` row. The sheet lists
  PgUp/PgDn, Backspace and q.

## Approver decisions

Resolved by olafkfreund at spec review, and folded into the design above:

1. **Shared "asks" wording.** Not changed here. A separate issue is filed in
   `OmarchyFans/omarchy-fans-help` at implementation time (A8).
2. **Bind line in getting-started.** Keep `nixarchy-plugin <id>` and add the
   clarifying sentence (A7).
3. **`chmod +x` in `install.sh`.** Kept, guarded by `[[ -x ]] ||` (A4).
4. **STAT and `stat()`.** Kept, because #15 relies on the `STAT scan
   complete` marker (B2).
5. **`bin/omarchy-plugin-browser`.** #18 changes the copy command and the
   `jq` chain area, so every B item in that file waits for #18 (B3).
