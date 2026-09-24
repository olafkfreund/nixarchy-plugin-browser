---
status: approved
issue: 20
spec: spec/2026-09-24-20-packaging-docs-cleanup.md
---

# Plan: Packaging, release and docs drift cleanup

This plan is self-contained: it carries every approved spec decision.

**Decisions**

- **Two phases.** Phase A touches only files no open issue owns, merges now,
  and releases 0.5.1. Phase B waits for #15, #17 and #18 to merge; every B
  step first re-locates its lines on the new `master` with grep, because the
  line numbers here were read at `059d190` (same code as `master` `449636c`).
- **No behaviour change** outside `install.sh`'s prerequisite check. Audit
  exit codes, JSON and verdicts, the scanner output, the TUI and panel keys
  all stay the same. `nix flake check` and `tests/*` pass before and after.
- **Flake.** `packages.cli` gets `meta.mainProgram = "omarchy-plugin-browser"`
  (the TUI; the audit needs a target). `homeModules = self.homeManagerModules;`
  is a one-line alias; `homeManagerModules` stays, snippets keep using it. No
  `apps` outputs.
- **README / getting-started.** Add `inputs.nixpkgs.follows`, an
  uninstall-first paragraph, and "(also `homeModules.default`)" in the outputs
  table. getting-started keeps `nixarchy-plugin <id>` as the bind command and
  gains one sentence naming the `omarchy-shell shell toggle <id> '{}'` form
  the shipped binds file uses.
- **`install.sh`.** Prerequisites are looked up on the tools' own pinned,
  root-owned `PATH`, with a "must match the tools' PATH" comment (no new
  shared file). `chmod +x` is kept but guarded, `[[ -x $f ]] || chmod +x "$f"`,
  so a git clone is never written to and a zip download still works.
- **Release 0.5.1 now**, not bundled with #15-#18. The update alert reads
  `manifest.json` on `master`, so merging the bump is the release. No tags.
- **`docs/update-alerts.md`:** only "In this plugin" is fixed; the
  cross-plugin standard stays for parity.
- **Shared "install.sh asks" wording** (`lib/update.sh:19-20`, `:199`,
  `docs/update-alerts.md:44`) is not changed here. An issue is filed upstream
  in `OmarchyFans/omarchy-fans-help`, the reference implementation named in
  `docs/update-alerts.md:10-11` and pointed to by `lib/update.sh:4-5`. The
  outcome "nothing claims install.sh asks" is narrowed to this plugin's text.
- **Plugin count** is reworded so it has no number. **`preview.png`** stays,
  documented as the marketplace listing image, not added to the flake `files`.
- **STAT records and `stat()` are kept**: #15 relies on the
  `STAT scan complete` marker. `stat()` is not renamed unless #15 changes it.
- **HANCORE comments** are kept, reworded to lead with the rule they enforce,
  the review reference trailing.
- **Duplicated `PATH` in QML** stays as two copies that point at each other;
  no shared singleton.
- **`bin/omarchy-plugin-browser`**: #18 changes its copy command and the `jq`
  chain area, so every item in that file waits for #18.

## Steps

### Phase A (now)

One commit per step, each citing the step. Step A9 is last.

1. `flake.nix` (`cliFor`, `:56`): the `runCommand` attrset `{ }` becomes
   `{ meta.mainProgram = "omarchy-plugin-browser"; }`.
   → verify by `nix run .#cli -- --help` printing the TUI help, exit 0.
2. `flake.nix` (`:69`): add `homeModules = self.homeManagerModules;` beside
   `homeManagerModules.default`. `README.md:85` and
   `docs/manual/getting-started.md:72` gain "(also `homeModules.default`)".
   → verify by `nix eval .#homeModules.default --apply builtins.isFunction`
   printing `true`, and `nix flake check` passing (an "unknown output"
   warning on old Nix is acceptable).
3. `README.md` "Install with Nix" (`:57-65`) and
   `docs/manual/getting-started.md:46`:
   - after the input URL line add
     `nixarchy-plugin-browser.inputs.nixpkgs.follows = "nixpkgs";`;
   - above the README snippet add: "Installed it with `install.sh` or
     `omarchy plugin add` before? Run `./uninstall.sh` from that clone first."
     (it removes the `~/.local/bin` links and the plugin checkout,
     `uninstall.sh:8-16`).
   → verify by `grep -n follows README.md docs/manual/getting-started.md`
   giving one match per file.
4. `install.sh`:
   - `:41-42`: set
     `TOOL_PATH="/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-}/bin"`
     with a comment that it must match the tools' `PATH` line
     (`bin/omarchy-plugin-audit:51`), and look up each tool, and `bwrap`,
     with `PATH="$TOOL_PATH" command -v "$c"`. The failure message names the
     missing tools and points at `nixarchy pkg add …`.
   - `:50` and `:54`: `chmod +x "$src"` becomes
     `[[ -x $src ]] || chmod +x "$src"`; the scanner line likewise, keeping
     its `2>/dev/null || true`.
   → verify by `bash -n install.sh`; `./install.sh` succeeding on this host
   with `ls -l ~/.local/bin/omarchy-plugin-*` showing the links; `git status`
   showing no mode change; and the check loop run with `TOOL_PATH` pointed at
   an empty directory failing and naming all five tools although they are on
   the caller's `PATH`.
5. `manifest.json:8`: "A bar button that opens a terminal browser" becomes
   "A bar button and a full-screen panel (Super+Alt+U)"; the rest of the
   sentence stays.
   → verify by `jq . manifest.json` parsing and
   `grep -n "opens a terminal browser" manifest.json` returning nothing.
6. Docs drift, text only:
   - `BarWidget.qml:163`: "…then install.sh relinks the commands."
   - `BarWidget.qml:164`: "Run install.sh once so the linked commands match.
     It only relinks this plugin's commands."
   - `README.md:109`: "then `install.sh`, which relinks the commands without
     asking."
   - `docs/update-alerts.md` "In this plugin" (`:134-141`) only:
     - Kind: bar widget (`BarWidget.qml`) plus a full-screen panel (`Menu.qml`);
     - cache `~/.cache/nixarchy-plugin-browser/update-check.json`, config
       `~/.config/nixarchy-plugin-browser/config.json` (`lib/update.sh:35-36`);
     - `install.sh` relinks without asking;
     - a Nix install (no `.git`) gets the "update with nix flake update"
       text in place of the Update button (`BarWidget.qml:60-62`).
   - `docs/manual/getting-started.md:23`: keep the line; add after it "The
     binds file this plugin ships uses `omarchy-shell shell toggle <id> '{}'`
     (`hypr/plugin-browser-binds.lua:14`). Both open the same panel."
   - `README.md:295-296`: add `secret-reference` to the capability list;
     `docs/manual/the-audit.md:35`: add "mentions of secrets or tokens" to the
     "review required" row. If #15 has merged and changed the list, follow it.
   - `README.md` Layout (`:328-346`): add `lib/update.sh` (the update check,
     shared with the other Omarchy.Fans plugins), `tests/preview.sh`,
     `tests/model-check.mjs`, `docs/` (the manual and the GitHub Pages site),
     `CHANGELOG.md` (read by the update alert), `preview.png` (the
     marketplace listing image, not shipped by the flake).
   - `README.md:153`: "for the plugins that have one";
     `docs/manual/previews-and-privacy.md:13-14`: "if it has one". No number.
   - `README.md:262`: heading becomes "How the audit works".
   → verify by the greps in Tests (phase A) and the QML still loading
   (`tests/model-check.mjs` via `nix flake check`).
7. GitHub: file two issues in `olafkfreund/nixarchy-plugin-browser`, each
   linking `plan/2026-09-22-4-qml-panel.md` "Open":
   - "Esc closes the whole panel after `o` opened a Chrome window" (needs a
     repro);
   - "`omarchy-shell` IPC misses a running shell after a nixarchy redeploy
     (matches on `$OMARCHY_PATH/shell`)".
   Then add the two issue numbers to that plan's Open list.
   → verify by `gh issue view <n>` for both and the Open list citing them.
8. GitHub: file one issue in `OmarchyFans/omarchy-fans-help`: "install.sh
   asks" in the shared `lib/update.sh` (header `:18-21`, `run` step `:199`)
   and `docs/update-alerts.md:44` is not true for every plugin (this
   plugin's `install.sh` never prompts); suggest "may ask" or similar. Link
   it from #20 with a comment. Nothing in this repo changes.
   → verify by `gh issue view -R OmarchyFans/omarchy-fans-help <n>` and the
   comment on #20.
9. Release, last commit of phase A: `manifest.json:5` to `0.5.1`; above
   `CHANGELOG.md:6` add:
   ```
   ## 0.5.1

   - e, f and o close the panel, so the terminal or browser they open gets the keyboard
   - Both confirms before an agent runs or a workspace is deleted now default to No
   - Nix: `nix run …#cli` works, and `homeModules.default` is exported
   ```
   → verify by `jq -r .version manifest.json` printing `0.5.1`, `## 0.5.1`
   being the first section of `CHANGELOG.md`, and `nix flake check` passing.

Open the phase A PR linking intent, spec and plan. Merging it is the release.

### Phase B (after #15, #17 and #18 merge)

Each step starts with `git pull` and a grep to re-locate its lines.

10. `bin/omarchy-plugin-audit`, after #15:
    - `--pause`: `grep -rn -- --pause bin lib *.qml Model.js docs` must show
      only this file; then remove the help line (`:34`), `PAUSE=0` (`:84`),
      the case arm (`:92`) and the pause branch in `finish()` (`:113`);
      `finish` keeps `exit "$1"`.
    - dead fallbacks (`:66`, `:70`): delete the `SELF_DIR/…` fallback lines;
      keep the `die` guards, reworded "not found in ../lib".
    - `grep -c` chains (`:379-380`, `:559`): become
      `n=$(grep -c … "$RAW" 2>/dev/null) || :; n=${n:-0}` with the digit
      stripping gone.
    - HANCORE comments (`:75`, `:185`, `:299`): lead with the rule, e.g.
      "Staging is bounded in time, bytes and file count before the sandbox
      starts, so a hostile target cannot hang or fill the disk", trailing
      "(from HANCORE-linux's review, #5581 v2)".
    → verify by `omarchy-plugin-audit --json` on a fixture plugin, diffed
    with `jq -S` against the pre-change output: identical; exit codes equal;
    `grep -n "|| echo 0\|--pause" bin/omarchy-plugin-audit` empty.
11. `lib/omarchy-plugin-scan.sh`: no change (STAT and `stat()` kept).
    → verify by `grep -n "STAT" lib/omarchy-plugin-scan.sh` matching as
    before.
12. `bin/omarchy-plugin-browser`, after #18 (re-read the whole file first;
    #18 changes the copy command and the `jq` area):
    - `run_fix` and `run_audit` (`:130-146`) become one
      `run_tool <script> <id>`: shared id check, `bash` call and "Enter to
      return" prompt; the call sites pass `nixarchy-plugin-fix` or
      `"$AUDIT"`.
    - `show_detail` (`:80-91`): the 13 `jq` calls become one `jq -r` printing
      the fields tab-separated, each through `gsub("[\t\n]"; " ")`, read with
      `IFS=$'\t' read -r …`. #18's malformed-entry guard stays in front.
    → verify by `bash -n`; the TUI details view for a real entry and for a
    fixture entry whose description holds a tab showing the same fields as
    before; `f` and `a` still run their tool and return on Enter.
13. SHORTCUTS, after #17 (recheck against #17's final key handling):
    - `Model.js:23`: "The keys the shortcut sheet lists. The view matches
      keys itself (BrowserView.qml) and the footer is its own string, so keep
      all three in step." `ShortcutSheet.qml:5-6` reworded to match.
    - add rows: List `PgUp PgDn` "move ten" (`BrowserView.qml:188-189`);
      Details `Esc ← Backspace` "back to the list" (`:270`); "`q` closes this
      sheet" in the `?` row (`:116`).
    → verify by `node tests/model-check.mjs` passing and the sheet showing
    PgUp/PgDn, Backspace and q in the panel.
14. `BarWidget.qml:35`, after #17: add "also in BrowserState.qml childEnv".
    `BrowserView.qml:80`: drop "(found in G1 on razer)", keep the rest.
    → verify by `grep -n "found in G1" BrowserView.qml` empty and the panel
    opening and closing as before.

Open the phase B PR linking the three files.

## Tests

Run before and after each phase; all must pass:

- `nix flake check` (runs `tests/scan-nix.sh`, `tests/model-check.mjs`, and
  the no-symlink / no-repo-only-file checks).
- `bash tests/catalog-list.sh` and `bash tests/preview.sh`.
- Phase A extras:
  - `nix run .#cli -- --help` exits 0 with the TUI help.
  - `nix eval .#homeModules.default --apply builtins.isFunction` → `true`.
  - `jq -r .version manifest.json` → `0.5.1`.
  - Empty:
    `grep -n "asks first\|asks again\|asks before changing" BarWidget.qml README.md`;
    `sed -n '/^## In this plugin/,$p' docs/update-alerts.md | grep -n "asks\|omarchy-plugin-browser/\|terminal"`;
    `grep -rn "3,379\|3379 of" README.md docs/manual`;
    `grep -n "corrected step list" README.md`;
    `grep -n "opens a terminal browser" manifest.json`;
    `grep -nE "^\s*chmod" install.sh`.
  - Match: `grep -n follows README.md docs/manual/getting-started.md` (one
    each); `grep -n secret-reference README.md`;
    `grep -n "preview.png\|lib/update.sh\|CHANGELOG.md" README.md`.
  - `./install.sh` on this host succeeds; the empty-`TOOL_PATH` run fails
    naming all five tools.
  - The three issues exist (two here, one in `OmarchyFans/omarchy-fans-help`).
- Phase B extras: audit JSON identical before/after (`jq -S` diff); TUI
  details identical including the tab fixture; `grep -rn -- --pause bin lib`
  empty; STAT still present in the scanner.

## Rollback

- Every step is its own commit; `git revert <sha>` undoes one.
- Phase A: revert the merge commit. If 0.5.1 was already seen by users,
  do not lower the version; revert the offending change and release 0.5.2,
  since the update alert only moves forward.
- Filed issues are closed as "not planned" if their step is reverted.
- Phase B: revert per step; none changes output, so no release is needed.

## Deviations

- **Step 6, lead decision.** #18 (PR #23) rewrites `BarWidget.qml:163` and the
  "Kind:" line of `docs/update-alerts.md` "In this plugin". Both are left for
  phase B, so the two PRs merge cleanly. Until then
  `grep -n "asks first" BarWidget.qml` and the "In this plugin" grep for
  "terminal" each still match that one line. New phase B step 15: after #18
  merges, drop "(asks first)" from the `BarWidget.qml` update line and make the
  Kind line "bar widget (`BarWidget.qml`) plus a full-screen panel
  (`Menu.qml`)", keeping what #18 added.
- **Step 4, verification.** `./install.sh` was not run against the real
  `$HOME`. A copy with `REPO` and `BIN_DIR` pointed at the worktree and a
  scratch directory linked all three tools; the same copy with `TOOL_PATH` at
  an empty directory failed naming git, jq, curl, file and gum.
- **Step 8, lead decision.** `OmarchyFans/omarchy-fans-help` exists (public,
  issues on), but the issue is not filed yet: its text is drafted in the
  phase A PR body under "Upstream issue (to file after merge)" for the owner
  to file, and to link from #20 then.
- **Step 9, lead decision.** `manifest.json` is not bumped here: #15 (PR #27)
  and #16 (PR #25) already set 0.5.1. This PR adds the `## 0.5.1` CHANGELOG
  section only; the sections merge when the PRs rebase. The 0.5.1 release is
  whichever of these PRs merges last with the bump in place.
- **Phase B, lead decision.** Phase B was started on top of the stack
  (#19, #15, #18, #16, #17 and phase A: PRs #24, #27, #23, #25, #31, #30)
  before it merged; the stack has since merged to `master` by fast-forward
  (`f13dd0c`), so phase B is built on the merged stack and ships as its own
  draft PR against `master`. Each B step re-locates its lines on that tree
  instead of starting with `git pull`. The approved
  decisions stand: STAT and `stat()` kept, the shared `lib/update.sh` code
  kept, HANCORE comments reworded, no behaviour change.
- **Step 12, `show_detail`.** The one `jq` prints its fields NUL-separated
  (`jq --raw-output0`, jq 1.7+), read by `IFS= read -r -d ''` per field, not
  tab-separated through `gsub("[\t\n]"; " ")`. A tab is IFS whitespace, so
  `IFS=$'\t' read` collapses empty fields and shifts the rest; and a
  non-string value (an object `name`, say) prints over several lines, which
  the `gsub` would have flattened. NUL keeps both exactly as before, and no
  field can hold one (`entry_by_id` turns control characters into spaces).
  Checked with `gum` stubbed to echo its argv: the details view, the copy and
  open actions, and `run_tool` for audit and fix, over a fixture catalog
  (tab and newline in fields, empty fields, odd types, a bad id) and 400 real
  entries: byte-identical.
