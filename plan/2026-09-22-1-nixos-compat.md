---
status: draft
issue: 1
spec: spec/2026-09-22-1-nixos-compat.md
---

# Plan: NixOS compatibility check + nixarchy port

This plan is self-contained; it carries every approved spec decision.

**Decisions**

- **Fork.** This repo is a nixarchy fork. It no longer needs to run on Arch.
  - New id: `io.github.olafkfreund.nixarchy-plugin-browser`.
  - Update feed: `olafkfreund/nixarchy-plugin-browser@master`.
  - Version: 0.3.0.
  - The CLI commands keep their names, `omarchy-plugin-audit` and
    `omarchy-plugin-browser`.
- **Fixed `PATH`** (these directories are root-owned only):
  `/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin`.
  - `OMARCHY_BIN` defaults to `/run/current-system/sw/bin`.
  - QML launches use `/run/current-system/sw/bin/{bash,xdg-terminal-exec}`.
  - Nothing relies on envfs or nix-ld.
- **Sandbox.**
  - bwrap binds `/nix/store` and `/run/current-system/sw` read-only.
  - It runs `/run/current-system/sw/bin/bash` with that `PATH`.
  - All the other isolation flags stay as they are.
  - A missing bwrap makes the audit exit 3 unless `--no-sandbox` is passed.
  - `--commit` must match `^[0-9a-f]{7,40}$`.
  - Code files (`qml/js/mjs/sh`) are scanned even inside the pruned
    directories.
- **NixOS pass.**
  - It adds a `NIX` record kind and seven rules. Three are blockers:
    `fhs-path`, `fhs-shebang`, `imperative-pkg`. Four need review:
    `bundled-elf`, `etc-write`, `global-lang-install`, `download-exec`.
  - It produces a separate verdict: `likely-ok`, `needs-review` or `blocked`.
  - The text report gets a section for it, and the JSON gets a
    `nixosCompatibility` field.
  - **Exit codes are unchanged.** There is no `--nix-strict`.
- **Agent hand-off.** A new command, `bin/nixarchy-plugin-fix <id|url|dir>
  [--mode explain|fix] [--commit <sha>]`.
  - It refuses if the security outcome is `needs-fixes`.
  - It copies the tree into
    `${XDG_STATE_HOME:-~/.local/state}/nixarchy-plugin-browser/work/<id>-<sha12>/tree`.
    The copy has no upstream `.git`, gets a fresh baseline commit, and the
    report sits next to it as `report.json`.
  - The prompt is written in the style of `nixarchy-ask` and names the
    `nixarchy`, `nixos-binaries` and `nixos` skills.
  - The plugin's text never goes into the prompt, and the prompt tells the
    agent to treat the files as untrusted data.
  - A warning and a `gum confirm` come before the launch. The launch is
    `omarchy-agent-prompt --inline`.
  - When the agent exits: show the diff, re-audit the copy, and save the patch
    to `${XDG_DATA_HOME:-~/.local/share}/nixarchy-plugin-browser/patches/<id>/<basesha>.patch`.
  - The user then chooses Install patched, Keep patch only, or Discard.
    Install patched uses a fresh hardened clone at the base commit, then
    `git apply`, a commit on branch `nixarchy-local`, a re-scan, and the
    existing install tail, so the plugin lands disabled.
  - Nothing is ever installed from the agent's tree.
  - Patches are not re-applied automatically. `omarchy plugin update` fails
    ff-only on the local commit, and the README says to re-run the fix.
- **PRs.** Phase A is PR 1, merged by fast-forward push as `docs/` in this repo
  describes. Phases B and C are PR 2, on the same branch.

## Steps

### Phase A: port (PR 1)

A1. `bin/omarchy-plugin-audit`, `bin/omarchy-plugin-browser`,
    `lib/omarchy-plugin-scan.sh`, `lib/update.sh`, `install.sh`, `uninstall.sh`:
    change the shebang to `#!/usr/bin/env bash`.
    → verify: `head -1` of each file, then `bash -n` on each.

A2. The same three runtime scripts (audit, browser, update.sh) get the fixed
    `PATH` export. In the audit, `OMARCHY_PATH`/`OMARCHY_BIN` default to
    `/run/current-system/sw` and `/run/current-system/sw/bin`. The browser's
    `run_audit` calls `/run/current-system/sw/bin/bash` instead of
    `/usr/bin/bash`.
    → verify: under `env -i HOME=$HOME USER=$USER`, `bin/omarchy-plugin-audit
    --help` prints the help, and the tool check at line 96 passes.

A3. `bin/omarchy-plugin-audit`: make three changes.
    - Rewrite `run_sandboxed` with the new binds.
    - Fail closed when bwrap is missing.
    - Validate `--commit`.

    → verify:
    - `nix shell nixpkgs#bubblewrap -c bin/omarchy-plugin-audit crmne.hyprmoncfg`
      runs sandboxed, and the report says `VALIDATE ok`.
    - Without bwrap, the audit exits 3. With `--no-sandbox` it runs.
    - `--commit 'x;y'` exits 2.

A4. `lib/omarchy-plugin-scan.sh`: change the inventory so that
    `*.qml/*.js/*.mjs/*.sh` files are collected even inside the pruned
    directories. `.git` and `node_modules` are still skipped.
    → verify: the fixture from B5 has `docs/Evil.qml` containing `eval(`, and
    the scan reports `dynamic-code-load` for it.

A5. Update the fork's identity.
    - `manifest.json`: new id and author, version `0.3.0`.
    - `lib/update.sh`: `UPD_ID`, `UPD_NAME`, `UPD_REPO`, `UPD_SLUG`,
      `UPD_CONFIG`.
    - `BarWidget.qml`: `moduleName`, the `--app-id`, `childEnv.PATH` and the
      absolute paths `/run/current-system/sw/bin/{bash,xdg-terminal-exec}`.

    → verify:
    - `lib/update.sh check --force` prints JSON with `latest` read from the new
      feed. Until the push it is null or offline, which is acceptable.
    - `omarchy-plugin-validate .` passes.

A6. `install.sh`: the bubblewrap hint becomes `nixarchy pkg add bubblewrap &&
    nixarchy apply`. `CHANGELOG.md` gets `## 0.2.1` (the pre-sandbox deadline
    and ceilings), `## 0.2.2` (the bounded remote checkout) and `## 0.3.0`
    (the nixarchy port).
    → verify: `lib/update.sh` `changelog_notes CHANGELOG.md 0.2.0 0.3.0`
    returns bullets.

A7. `README.md`: rewrite it for nixarchy. Cover:
    - Requirements, including bubblewrap through nixarchy.
    - Install.
    - The one-time move from the old id: `omarchy plugin remove
      io.github.modpunk.plugin-browser`, then `./install.sh --plugin`.
    - An updated audit step list that describes the new sandbox binds.

    → verify: read it through. Every path it mentions exists.

A8. Push the branch and open PR 1, linking the intent, spec and plan and
    closing nothing. Its checks are A2–A6, plus a manual bar-button click once
    it is installed at the new id.
    → verify: the PR exists and the diff matches steps A1–A7.

### Phase B: NixOS pass (PR 2)

B1. `lib/omarchy-plugin-scan.sh`: add the `NIX` rules through `scan NIX <id>
    <regex> [filter]`.
    - `fhs-path`: pattern
      `/usr/s?bin/[A-Za-z]|/usr/share/omarchy|/usr/lib/|(^|[^A-Za-z0-9_.])/opt/`.
      Hits that are only `/usr/bin/env` are excluded. The filter is
      `\.(qml|js|mjs|sh|py)$`, plus extensionless files whose `file` type
      contains "script".
    - `fhs-shebang`: a small loop over the text files, checking line 1 only.
    - `imperative-pkg`, `etc-write`, `global-lang-install`: `scan` with the
      regexes from the spec. `global-lang-install` skips a file that mentions
      `venv`.
    - `download-exec`: a per-file loop that requires both patterns.
    - `bundled-elf`: emitted from `BIN_EXEC`.

    → verify: run `tests/scan-nix.sh` (B5).

B2. `bin/omarchy-plugin-audit`: add the tally.
    - `nix_sev()` is a `case` mapping each id to `blocker` or `review`.
    - Count the blockers and review findings, and compute `NIX_VERDICT`.
    - The exit code is left untouched.

    → verify: on the fixture, the verdict is `blocked` and the exit code
    matches the pre-change value.

B3. `bin/omarchy-plugin-audit`: add the "NixOS compatibility" section to the
    text report, after Capabilities. It shows one line per finding (severity
    glyph, id, file:line, evidence), then `NixOS: <verdict>`. For `blocked` or
    `needs-review`, it adds the hint "run: nixarchy-plugin-fix <id>".
    → verify: visual check on the fixture and on an installed `nixarchy.*`
    plugin.

B4. `bin/omarchy-plugin-audit`: in the JSON output, add
    `nixosCompatibility: {verdict, blockers, reviews, findings:[{id, severity,
    at, evidence}]}`. Severity comes from a `--argjson` map.
    → verify: `--json | jq -e '.nixosCompatibility.verdict'` on the fixture
    returns `"blocked"`.

B5. Add `tests/scan-nix.sh`, a single self-checking bash script. It builds
    this fixture in `mktemp -d`:
    - A `manifest.json`.
    - `run.sh` with `#!/usr/bin/bash` and `pacman -S foo`.
    - `Widget.qml` containing `"/usr/share/omarchy/bin/x"`.
    - `docs/Evil.qml` containing `eval(`.
    - `ok.sh` with `#!/usr/bin/env bash` and `/usr/bin/env jq`.

    It runs the scanner unsandboxed and asserts that each expected id appears
    at the right file, and that `ok.sh` produces no NIX record. It exits
    non-zero on the first failure.
    → verify: `bash tests/scan-nix.sh` prints `ok`.

B6. Run the false-positive check: audit each
    `~/.config/omarchy/plugins/nixarchy.*` with `--json --no-sandbox`. Record
    each verdict.
    → verify: every one is `likely-ok`. If one is not, inspect it. A real hit
    stays. A false positive tightens the regex in the same commit and adds
    that case to `tests/scan-nix.sh`.

### Phase C: agent hand-off (PR 2)

C1. `bin/omarchy-plugin-audit`: add two internal flags.
    - `--export-tree <dir>`: after the scan, `cp -a "$CHECKOUT/." "$dir"`,
      leaving out `.git`. It refuses if `$SYMLINKS` is non-empty. The copy is
      bounded by `_bound_run`.
    - `--apply-patch <file>`: only valid together with `--install`. After a
      fresh hardened clone and checkout of the target commit, it runs
      `git apply --check "$file"` then `git apply`. It commits on a local
      branch `nixarchy-local`, with the identity `nixarchy-plugin-fix` and
      `core.hooksPath=/dev/null`. Then it re-scans, and the result must not be
      `needs-fixes`. From there the existing install tail runs, and it checks
      HEAD against the patched commit.

    → verify: `--export-tree` on the fixture produces a tree with no `.git`.
    `--apply-patch` with a bad patch exits 3 before anything is installed.

C2. Add `bin/nixarchy-plugin-fix`, about 150 lines, following the spec's
    Phase C steps 1–7.
    - Usage and argument parsing: `--mode explain|fix`, then `--commit`.
    - Run the audit with `--json --export-tree`. Refuse on `needs-fixes`, and
      exit 0 on `likely-ok`.
    - Create the workspace: `git init`, then the baseline commit with a fixed
      identity and hooks off.
    - Build the prompt from a heredoc. Only the id, paths and finding ids are
      interpolated, never the plugin's text.
    - Check `omarchy-default-agent`, show the warning and `gum confirm`, then
      `(cd "$W/tree" && omarchy-agent-prompt --inline "$prompt")`.
    - In fix mode:
      - If the diff is empty, stop.
      - Show `git diff --stat` and the full diff in `gum pager`.
      - Re-audit `$W/tree` with `--json`, and refuse if it is `needs-fixes` or
        worse than the original.
      - Show the new NixOS verdict and `../needs.txt`.
      - Save the patch.
      - `gum choose` between Install patched (`omarchy-plugin-audit <original
        target> --commit <base> --install --apply-patch <patch>`), Keep patch
        only, and Discard.
    - Explain mode ends after the agent exits. It then prints where the
      report lives.

    → verify: run `nixarchy-plugin-fix <fixture> --mode explain`. The agent
    launches inline, and afterwards `git -C W/tree status --porcelain` is
    empty.

C3. `bin/omarchy-plugin-browser` `show_detail`: add the action "🧩 NixOS check
    / fix with agent". It runs `nixarchy-plugin-fix <id>` with the absolute
    `SELF_DIR` path, the same validated id, and a pause afterwards. With no
    `--mode`, the fix script asks with `gum choose` whether to Explain, Fix a
    copy, or go Back.
    → verify: open the TUI, pick a plugin, and the action runs.

C4. `install.sh`, `uninstall.sh`: link and unlink `nixarchy-plugin-fix`, and
    require `git jq curl file gum`. `README.md`: add a "NixOS check and agent
    fixes" section. It covers the flow, the residual risk (a prompt injection
    during the agent session can run commands as the user), the patch
    location, and what to do when `omarchy plugin update` refuses.
    `CHANGELOG.md` 0.3.0 gets bullets for B and C.
    → verify: running `./install.sh` twice is idempotent, and `./uninstall.sh`
    removes all three links.

C5. End-to-end: run `nixarchy-plugin-fix <fixture-as-git-repo> --mode fix`
    with the default agent (claude).
    → verify:
    - A diff is produced, the re-audit runs, and the patch file exists.
    - Install patched adds the plugin disabled, with HEAD on `nixarchy-local`.
    - `omarchy plugin update <id>` refuses ff-only and leaves the files
      unchanged.
    - Clean up with `omarchy plugin remove <fixture-id> --yes`.

C6. Push, then open PR 2 linking the three artifacts and closing #1.

## Tests

| Command | Expected |
|---------|----------|
| `for f in bin/* lib/*.sh install.sh uninstall.sh tests/*.sh; do bash -n "$f"; done` | no output |
| `nix run nixpkgs#shellcheck -- -S warning bin/* lib/*.sh install.sh uninstall.sh tests/*.sh` | no new warnings compared with master |
| `bash tests/scan-nix.sh` | `ok`, exit 0 |
| `nix shell nixpkgs#bubblewrap -c bin/omarchy-plugin-audit crmne.hyprmoncfg` | sandboxed run, `VALIDATE ok`, NixOS section present |
| `bin/omarchy-plugin-audit crmne.hyprmoncfg` (no bwrap) | exit 3 with the nixarchy install hint |
| `bin/omarchy-plugin-audit x --commit 'x;y'` | exit 2 |
| `bin/omarchy-plugin-audit <fixture> --json --no-sandbox \| jq -r .nixosCompatibility.verdict` | `blocked` |
| B6 loop over `nixarchy.*` plugins | all `likely-ok` |
| C2 / C5 manual runs | as described in those steps |

## Rollback

- Before merge: close the PR and delete the branch.
- After PR 1: `git revert` the Phase A commits and push. Users who moved to the
  new id run `omarchy plugin remove io.github.olafkfreund.nixarchy-plugin-browser`
  and re-add the old checkout.
- After PR 2: revert the B and C commits. Phase A stands on its own.
  Workspaces and patches under `~/.local/state` and `~/.local/share`
  (`nixarchy-plugin-browser/`) are plain files, and removing them is safe.
- A plugin installed with a patch: `omarchy plugin remove <id>`, then re-add it
  from upstream.
