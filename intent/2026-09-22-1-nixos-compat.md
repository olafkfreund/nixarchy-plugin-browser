---
status: draft
issue: 1
author: olafkfreund
---

# Intent: NixOS compatibility check + nixarchy port

## Problem

Two problems, and the first one blocks the second.

1. **This tool does not run on nixarchy.** It is a fork of the Omarchy Plugin
   Browser, and every entry point assumes Arch's FHS layout:
   - `PATH` is fixed to `/usr/local/bin:/usr/bin:/bin:/usr/share/omarchy/bin`
     (`bin/omarchy-plugin-audit:44`, `bin/omarchy-plugin-browser:19`,
     `lib/update.sh:25`, `BarWidget.qml:35`). None of it exists on NixOS, so
     jq, gum, git and omarchy all look missing.
   - The bar widget, the update check and the in-sandbox scan launch
     `/usr/bin/bash` and `/usr/bin/xdg-terminal-exec`. On nixarchy these live
     in `/run/current-system/sw/bin`.
   - The bwrap sandbox binds only `/usr`, so on NixOS it has no bash, no grep
     and no `omarchy-plugin-validate`.
   - When `bwrap` is missing, which is the case on this machine, the audit
     **silently falls back to no sandbox**, even though the README promises
     one.
   - The plugin id (`io.github.modpunk.plugin-browser`) and the update feed
     (`OmarchyFans/omarchy-fans-plugin-browser`) still point at upstream. Update
     alerts therefore track someone else's releases, not this fork's.
   - Smaller issues:
     - `install.sh` suggests `omarchy pkg add bubblewrap`, which refuses on
       nixarchy.
     - The scanner skips `docs/`, `test/` and similar directories, but QML can
       import code from them.
     - `CHANGELOG.md` has no 0.2.1 or 0.2.2 sections.
     - `--commit` is passed to `git checkout` without validation.

2. **Nothing tells a nixarchy user whether a marketplace plugin will run on
   NixOS.** Omarchy plugins are written for Arch. They hardcode `/usr/bin/...`
   and `/usr/share/omarchy`, call `pacman`/`yay` or `omarchy pkg add`, ship
   prebuilt ELF binaries, or write to `/etc`. On nixarchy these plugins
   install and then fail at runtime. The user has no way to find out
   beforehand, and no guided way to fix it.

## Proposed outcome

- The browser, the auditor, the bar button and the update alerts work on
  nixarchy. The audit is really sandboxed, or it refuses to run unless the
  user explicitly passes `--no-sandbox`.
- Every audit also reports a **NixOS compatibility verdict**, with evidence
  as file and line. The verdict is one of `likely-ok`, `needs-review` or
  `blocked`, and it appears both in the text report and in `--json`.
- From the browser, the user can hand those findings to **their own default
  agent**: whichever one `omarchy-default-agent` names, launched the way
  `nixarchy ask` launches it. The agent is pointed at the `nixarchy`, `nixos`
  and `nixos-binaries` skills. The user then chooses one of two modes:
  - **Explain:** the agent proposes changes and the user decides what to
    change.
  - **Fix a copy:** the agent edits a disposable copy of the plugin. The user
    sees the diff, the patched copy is re-audited, and it is installed
    (disabled) only after an explicit confirmation. The patch is saved so it
    can be re-applied.

## Affected users and systems

- nixarchy users who browse or install Omarchy marketplace plugins.
- Files in this repo: `bin/omarchy-plugin-audit`, `bin/omarchy-plugin-browser`,
  `lib/omarchy-plugin-scan.sh`, `lib/update.sh`, `BarWidget.qml`,
  `manifest.json`, `install.sh`, `uninstall.sh`, `CHANGELOG.md` and
  `README.md`, plus one new script for the agent hand-off.
- Nixarchy commands it relies on but does not change: `omarchy-agent-prompt`,
  `omarchy-default-agent`, `omarchy-plugin-validate`, `omarchy plugin add` and
  `omarchy plugin update`.

## Constraints

- **Security posture must not regress.** The audit still never executes
  plugin code, and it still never enables a plugin. `PATH` stays limited to
  root-owned directories on NixOS.
- **The plugin under test is untrusted input to the agent.** The agent runs
  in auto-approve mode, so the plugin's own text must never be pasted into
  the prompt. The agent works only on a disposable copy, and nothing it
  produces is installed without a re-audit and the user's confirmation.
- **Declarative only.** Nothing is installed imperatively. Packages a plugin
  needs are reported as `nixarchy pkg add <attr>` suggestions, never
  installed by the tool or the agent.
- **Agent-neutral.** No agent is named in the code; the tool uses whatever the
  user chose as the default.
- The existing exit-code contract (`0 / 10 / 20 / 2 / 3`) keeps its security
  meaning.
- This is a nixarchy fork. It gets its own id and update feed and does not
  need to keep running on Arch.

## Open questions

- Should the NixOS verdict ever change the exit code, for example through a
  `--nix-strict` flag for CI? The proposal is to leave it out until someone
  needs it.
- Should saved patches be re-applied automatically after
  `omarchy plugin update`? The proposal is no for v1: the update's
  `merge --ff-only` fails safely on a local commit, and the user re-runs the
  fix.
