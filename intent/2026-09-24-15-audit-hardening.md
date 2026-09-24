---
status: draft
issue: 15
author: olafkfreund
---

# Intent: Harden the audit and the scanner

## Problem

The 2026-09-24 deep review found eight defects in the auditor
(`bin/omarchy-plugin-audit`), the scanner (`lib/omarchy-plugin-scan.sh`) and
`uninstall.sh`. The auditor is the one thing that stands between an untrusted
plugin and `omarchy plugin add`. Every defect below lets a plugin author weaken
the audit's verdict, its output, or what gets installed.

1. **A file name can spoof the manifest check.**
   - `emit()` replaces tabs in the evidence field only. The path field
     (`$rel:$ln`) goes out raw (`lib/omarchy-plugin-scan.sh:31`, `:82`).
   - The audit takes the first `VALIDATE` line it sees
     (`bin/omarchy-plugin-audit:381`, `head -1`). The scanner's real
     `VALIDATE` line comes last (`scan.sh:272-277`).
   - Scenario: a plugin with an invalid manifest and one capability hit, in a
     file named `x<newline>VALIDATE<tab>ok<tab>fine`. The injected line wins.
     The failing manifest is not counted, the exit code stays 10, and the
     `--install` gate (`OC_EXIT >= 20`, `audit:585`) lets it through.

2. **Plugin text reaches the terminal unfiltered.** The scanner strips control
   characters from evidence (`scan.sh:82`), but not from paths, not in the
   `cargo-git-unpinned` evidence (`scan.sh:106`), and not from anything the
   audit prints itself:
   - the commit subject (`audit:286`, `:318`, printed at `:456`);
   - the catalog name (`audit:176`, printed at `:453`).

   Scenario: a commit subject carrying an OSC 52 sequence writes to the user's
   clipboard. Other escapes can repaint the report so `needs-fixes` looks like
   `passed`.

3. **`--install` of a local folder installs code that was not scanned.**
   - A local folder is scanned as its working tree (`copy_hardened`,
     `audit:283`), but `SCAN_COMMIT` is set to its `HEAD` (`audit:285`).
   - When that folder has an `origin` remote, `REPO_URL` is set
     (`audit:145`), so the "local folder, skipping" guard (`audit:581`) does
     not fire.
   - Install then clones the copy and checks out `SCAN_COMMIT`
     (`audit:596-597`).

   Scenario: clean, uncommitted edits in the working tree pass the audit.
   `HEAD` is installed, and `HEAD` holds the malicious version.

4. **Catalog repo URLs are not restricted to https.**
   - `REPO_URL` can come from the catalog's `.repo` (`audit:155`).
   - The only check is against transport helpers (`audit:161-167`). It is
     skipped entirely for a bare `/path`, and it lets `file://` and `ssh://`
     through.
   - The clone runs outside bwrap (`audit:252-255`).

   Scenario: a poisoned or compromised catalog entry makes the audit clone
   `file:///home/you/.ssh` or another local repo, or open an ssh connection
   to a host the entry chooses, with the user's own credentials and agent.

5. **Symlinks are only off for the clone, not the checkout.**
   - `git -c core.symlinks=false` is passed on the command line
     (`audit:254`), so it does not persist in the new repo's config.
   - The later checkout (`audit:313-314`) runs without it and writes real
     symlinks into the staging dir. The install checkout (`audit:597`) has
     the same problem.
   - The symlink detection at `audit:348-351` still reads the index, so
     `--install` still refuses. But the scanner reads through those links
     (`find`, `grep`, `file`).

   Scenario: `a.qml -> /home/you/.config/...` makes the scan read and quote
   files from outside the plugin.

6. **The scanner has blind spots.**
   - Extensionless files in pruned directories (`docs/`, `test/`, …) are never
     scanned (`scan.sh:39-51`). The second pass only picks up
     `.qml/.js/.mjs/.sh`.
   - Any line whose first non-blank character is `*` counts as a comment
     (`scan.sh:83`, `:108`). In JS and QML that also matches ordinary code,
     for example a line starting with `*` inside a multi-line expression.
   - `[^\n]` in an ERE (`scan.sh:131`) means "not backslash, not n". It is not
     "not newline", so the `privileged-process-control-from-shared-temp`
     detector misses any line with an `n` between `sudo` and `kill`.

7. **Some identifiers are used before they are checked.**
   - `PLUGIN_ID` from `manifest.json` (`audit:144`, `:337-338`) builds the
     path `~/.config/omarchy/plugins/$PLUGIN_ID` (`audit:605`) and is passed
     to `omarchy plugin enable`.
   - `uninstall.sh:12-15` passes the manifest id straight to
     `omarchy plugin remove`.
   - The catalog's `verificationCommit` (`audit:170`) becomes `SCAN_COMMIT`
     and is passed to `git checkout` without a SHA check.

   Scenario: an id such as `../../x` or `-rf` points the install check, or
   the removal, at the wrong path or makes it an option.

8. **The audit fails its own plugin.** Run on this repo, the audit reports
   `needs-fixes`/`blocked`, because the scanner's own detector patterns look
   like the things they detect. A tool that fails itself trains its users to
   ignore `needs-fixes`.

## Proposed outcome

- No plugin-controlled text (file names, file contents, commit subjects,
  catalog fields) can add, change or reorder the lines the audit reads from
  the scanner. A test with a crafted file name proves that the real
  `VALIDATE` result is the one used.
- Nothing from a plugin or the catalog reaches the terminal, or the `--json`
  output, with control characters in it.
- `--install` installs exactly the bytes that were scanned, or it refuses.
- A repo URL from the catalog or a local `origin` is cloned only if it is an
  allowed kind of URL. Everything else is refused with exit 2.
- No stage of the audit writes a real symlink into its staging or install
  directories.
- Every scanner blind spot in item 6 is closed, each with a test.
- Plugin ids and commit hashes are validated before they are used in a path,
  an argv or a git command. A bad one is refused, not sanitised.
- Auditing this plugin returns an honest result. Its own detector code is
  not flagged, and a real finding in it still would be.

## Affected users and systems

- Everyone who audits or installs a plugin through the Plugin Browser panel,
  `omarchy-plugin-audit`, or `nixarchy-plugin-fix`.
- Files in this repo: `bin/omarchy-plugin-audit`,
  `lib/omarchy-plugin-scan.sh`, `uninstall.sh`, their tests, `CHANGELOG.md`,
  and possibly `README.md`/`SECURITY.md` if the accepted URL kinds change.
- Callers that read the audit's exit code and `--json`: the panel
  (`BrowserState.qml`) and `bin/nixarchy-plugin-fix`.
- Commands used but not changed: `omarchy plugin add|enable|remove`,
  `omarchy-plugin-validate`, `omarchy-git-url-check`, `bwrap`.

## Constraints

- **Keep the exit-code contract.** `0` passed, `10` review-required, `20`
  needs-fixes, `2` refused, `3` error. The panel and `nixarchy-plugin-fix`
  depend on it. (The issue's summary says `0/20/2/3`; the code also has `10`,
  and it stays.) New refusals use `2`, new failures `3`.
- **Keep the scanner's line format** (`KIND<TAB>id<TAB>path:line<TAB>text`),
  or change it in a way the callers already handle. `--json` keeps its keys.
- **Security must not regress.** The audit still never runs plugin code, never
  enables a plugin, and still refuses to run unsandboxed without
  `--no-sandbox`.
- **Bash only, no new dependencies.** Only tools already on the pinned NixOS
  `PATH` (`/run/current-system/sw/bin`) and inside the bwrap sandbox.
- **Stays grep-grade.** This is hardening, not a rewrite into a parser.
- **Coordination with #18.** `bin/omarchy-plugin-audit:152` (the catalog note,
  moving to stderr for `--json`) belongs to issue #18. This work must not
  change that line, and should expect it to move.
- Each fix comes with a test that fails on today's code.

## Open questions

- **URL kinds.** Allow only `https://`, or also `ssh://`/`git@` for private
  plugin repos that a user passes by hand? The proposal is https only for
  catalog-derived URLs. A hand-typed ssh URL would be allowed, since the user
  chose it. `file://` and bare paths are refused unless they are the local
  folder the user named.
- **Local `--install`.** When the working tree differs from `HEAD`, should
  `--install` refuse, or install the working tree as scanned? The proposal is
  to refuse, and to tell the user to commit first.
- **Self-audit false positive.** Fix it by an allowlist (skip this plugin's
  own scanner file by id and path), or by rewriting the detector patterns so
  they do not match their own source? The proposal is to rewrite the
  patterns: an allowlist keyed on the plugin id is exactly what an attacker
  would copy.
- **Bad identifiers.** Should a malformed `PLUGIN_ID` or `verificationCommit`
  from the catalog fail the whole audit (exit 2), or only drop that field and
  carry on unverified? The proposal is: a bad id refuses, and a bad
  `verificationCommit` falls back to "unverified" with a warning.
- **One issue or several?** All eight items touch the same two files. The
  proposal is one spec and one plan, with a commit per item.
