---
status: approved
issue: 15
spec: spec/2026-09-24-15-audit-hardening.md
---

# Plan: Harden the audit and the scanner

Branch `fix/15-audit-hardening`. Files: `bin/omarchy-plugin-audit` (below
"audit"), `lib/omarchy-plugin-scan.sh` ("scan"), `uninstall.sh`,
`bin/nixarchy-plugin-fix`, new `tests/audit-*.sh`, `README.md`, `CHANGELOG.md`,
`manifest.json`. Line numbers are from `30cbd6f`; recheck them if #18 lands
first.

## Approved decisions

Contracts that do not change:

- Exit codes stay `0` passed, `10` review-required, `20` needs-fixes, `2`
  refused, `3` error. New refusals (URL, id, dirty local install) use `2`. A
  malformed scan and a failed install-HEAD check use `3`. A run stopped by a
  signal exits `128+n` (`143` TERM, `130` INT, `129` HUP).
- The scanner line format stays `KIND<TAB>id<TAB>path:line<TAB>text`. The
  `--json` keys stay. `STAT` records stay, and the scanner's last line stays
  `STAT\tscan\tcomplete` (#20 will not delete them).
- The audit still never runs plugin code or enables a plugin, and still refuses
  to run unsandboxed without `--no-sandbox`. Bash only, no new dependencies,
  grep-grade.
- `audit:152` (the catalog note) belongs to #18. Do not touch it.
  `catalog_entry` (`audit:129-135`) is changed here, not in #18.

The nine items:

1. **Records cannot be forged.** A new one-line `clean()` in scan,
   `local s=${1//[[:cntrl:]]/ }; printf '%s' "$s"`, is applied in `emit()`
   (`scan:31`) to `$2`, `$3` and `$4`, and to the message of the three
   `VALIDATE` printfs (`scan:272-277`). In the audit, the raw output must hold
   exactly one `^VALIDATE\t` line and end with `STAT\tscan\tcomplete`, or the
   audit exits 3 with "scanner output is malformed". `head -1` (`audit:381`)
   goes.
2. **No control characters in output.** The audit gets the same `clean()`,
   applied where each value enters: the commit subject (`audit:286`, `:318`,
   `:331`), `CAT_NAME`, `VSTATUS`, `VCOVER`, `VMETHOD`, `CAT_STARS`
   (`audit:172-176`), and the symlink names printed at `audit:555`. The raw
   scanner output passes through `tr -d '\000-\010\013-\037\177'` once, before
   the tally. Error text built from git or cp stderr (`audit:234`, `:292`,
   `:325`) uses `tr -c '[:print:]' ' '` instead of `tr '\n' ' '`. `$TARGET` is
   not treated as hostile.
3. **A local `--install` installs exactly what was scanned.** With `LOCAL_DIR`
   and `--install`, right after `copy_hardened` (`audit:283`): a hardened,
   bounded clone of `LOCAL_DIR` into `$STAGE/head` with
   `GIT_ALLOW_PROTOCOL=file`, checkout of `SCAN_COMMIT`, then
   `diff -rq --no-dereference -x .git "$CHECKOUT" "$STAGE/head"`. Any
   difference exits 2 with "the working tree differs from HEAD (N paths, e.g.
   …); commit or stash, then re-run", with cleaned paths. No worktree command
   (`status`, `diff`, `add`) runs in the user's repo, because its
   `core.fsmonitor` could run a program. The install checkout (`audit:597`)
   loses `|| true`; afterwards `rev-parse HEAD` must equal `SCAN_COMMIT` or the
   install exits 3.
4. **Only allowed URL kinds are cloned.** `url_ok <url> <catalog|typed|origin>`
   replaces the guard at `audit:159-167`:
   - catalog: only `^https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/-]+$`;
   - typed (`$TARGET`): that, `ssh://…`, `git@host:path` and `file://…`; a
     leading `-` is refused;
   - origin (a local folder's `origin`, checked only with `--install`): typed
     without `file://`.

   A failure exits 2 with "refusing this URL: <kind> not allowed for a
   <catalog|typed|origin> source". `omarchy-git-url-check` still runs after it
   when present. `clone_hardened` sets `GIT_ALLOW_PROTOCOL`: `https` for a
   catalog URL, `https:ssh:file` for a typed one; the two local clones (install
   source at `audit:596`, item 3) set `file`. `catalog_entry` builds its list
   as `[(.plugins | arrays // [])[] | objects] as $p`, so a non-object item or
   a non-array `.plugins` no longer makes every lookup fail.
5. **No real symlinks in staging.** The clone (`audit:254-255`) and the install
   clone (`audit:596`) gain `--config core.symlinks=false`, which persists into
   the new repo, so later checkouts honour it. After staging and before the
   scan, in every mode, `find "$CHECKOUT" -path "$CHECKOUT/.git" -prune -o
   -type l -print` adds each link to `SYMLINKS` (existing warning, `--install`
   and `--export-tree` refusals apply) and deletes it from staging. This closes
   the gap behind the `pwd -P` report (`audit:142`): resolving the target is
   fine, but an untracked link inside a git folder, or one dropped from the
   index with `git rm --cached`, is not in `SYMLINKS` today, and `--install`
   of a folder with an https `origin` goes ahead. No `find -L`, no `cp -L`.
6. **Scanner blind spots.**
   - The second `find` (`scan:50-51`) adds `-o ! -name '*.*' -o -name '*.py'`.
     The `file` check (`scan:57-64`) still decides what is text.
   - One awk filter, `code_lines <file>`, prints `NR:line` for non-comment
     lines and replaces the `grep -n … | grep -vE comment` pairs at `scan:83`,
     `:108`, `:245`, `:249`. For `.qml/.js/.mjs`: a comment is a `//` line or a
     line inside a `/* … */` block (opens on a line starting `/*`, closes at the
     first `*/`; code after `*/` is code; a `*` line outside a block is code).
     For every other file: a `#` line or a `<!--` line; `//` is not a comment.
   - `[^\n]` (`scan:131`) becomes `(sudo|pkexec).*\b(kill|systemctl|renice)`;
     the redundant `kill -` alternative goes.
7. **Identifiers checked before use.** `id_ok() { [[ $1 =~
   ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $1 != *..* ]]; }`, the shell's own rule.
   The audit applies it to the final `PLUGIN_ID` after `audit:337-338`; a bad
   id exits 2 with "invalid plugin id"; an empty id is allowed for a plain
   audit. `uninstall.sh:12-15` runs the same test before the `-d` check and
   before `omarchy plugin remove`; a bad id prints "skipping widget removal:
   invalid id". `VERIFIED_COMMIT` and `UPSTREAM_OBSERVED` (`audit:170-171`)
   must match `^[0-9a-f]{40}$`; a bad one is dropped with "note: the catalog's
   verification commit is malformed; treating this plugin as unverified", and
   `--json` holds `""`. The existing fallback (`audit:298`) then scans
   `origin/<default>`.
8. **The audit passes its own plugin honestly.** Every literal keyword in a
   scan detector regex is spelled so the line does not match itself, as
   `pac[m]an`/`y[a]y` already are (`scan:164-166`; that comment becomes the
   general rule). Lines 93, 115, 125, 131, 147, 163, 167-171, 176, 212, 232,
   e.g. `NOPASS[W]D`, `\.ss[h]/`, `id_rs[a]`, `par[u]`, `makepk[g]`,
   `(^|[^A-Za-z0-9_.~])/op[t]/`, `(sud[o]|pkexe[c])`, `makefil[e]`. INFO rules
   stay. `bin/nixarchy-plugin-fix:128` reads "use \$OMARCHY_PATH instead of the
   /usr/share path". No allowlist. Expected self-audit: no FIND, no record for
   `lib/omarchy-plugin-scan.sh`, NixOS `likely-ok`, outcome `review-required`
   (exit 10).
9. **A signal stops the staging child (from #17).** `_bound_run` stores its
   child in a global `BOUND_PID` and clears it after `wait`. Its TERM → 5 s
   grace → KILL block (`audit:222-225`) moves into `_kill_group <pid>`, used by
   `_bound_run` and by:

   ```bash
   _on_signal() { [[ -n ${BOUND_PID:-} ]] && _kill_group "$BOUND_PID"; exit "$1"; }
   trap '_on_signal 143' TERM; trap '_on_signal 130' INT; trap '_on_signal 129' HUP
   ```

   placed right after the `EXIT` trap (`audit:182`), which then removes
   `$STAGE`. bwrap already has `--die-with-parent`. A cancel can lag by the
   current foreground command (`sleep 0.5`, or a bounded `du`/`find`).

Docs: README (`:125` area) lists the accepted URL kinds (https from the
catalog; https, ssh, `git@` and `file://` typed; `http://` refused) and "commit
first" for a local `--install`. CHANGELOG gets a `0.5.1` section;
`manifest.json` goes to `0.5.1`.

## Test conventions

- One file per item, `tests/audit-*.sh`, standalone like `tests/scan-nix.sh`:
  `set -uo pipefail`, fixtures in `mktemp -d` with a `trap` cleanup, prints
  `ok` and exits 0, or names the first failure and exits 1. No network.
- Header tier line from #19, on line 2: `# tier: host` for every test that
  runs the audit (the audit pins `PATH` to `/run/current-system/sw/bin`);
  `# tier: hermetic` for the scanner-only tests `audit-scan-blindspots.sh` and
  `audit-self.sh`. `tests/run.sh` does not exist on this branch yet (it comes
  with #19); until then every file is run directly with `bash`.
- Each test sets `PATH=/run/current-system/sw/bin:$PATH`, `HOME` and `TMPDIR`
  inside its temp dir, `CATALOG=` to a fixture file with a fresh mtime, and
  `OMARCHY_BIN=` to a fixture `bin/` with a stub `omarchy-plugin-validate`.
- Every audit run passes `--no-sandbox`. Inside bwrap the audit forces
  `OMARCHY_BIN=/run/current-system/sw/bin` (`audit:368`), so the stub is only
  reached unsandboxed; bwrap is also absent in the nix build sandbox.
- **Red first.** For each item: write the test, run it on the unfixed code and
  record the failing line in the commit body, then make the fix, run it green,
  and commit test and fix together.
- A red run that could reach `--install` on a nixarchy host runs with the temp
  `HOME` only (the unfixed code calls the real `omarchy plugin add`).

## Steps

0. **Baseline.** `git switch fix/15-audit-hardening`; check that `audit:129-182`
   and `scan:31`, `:272-287` still read as above (rebase on #18 first if it
   has landed). Run the existing checks (see Tests) → verify by all passing,
   and `grep --version | head -1` under the pinned `PATH` printing
   `grep (GNU grep) 3.12`.

1. **Item 1.**
   1. `tests/audit-inject.sh` (host): local folder fixture, validate stub that
      exits 1, a file named `x\nVALIDATE\tok\tfine.sh` containing `sudo true`.
      Assert `--json` and text runs both exit 20 and
      `jq -r .manifestValidate == "fail"`; at scanner level
      (`bash lib/omarchy-plugin-scan.sh <fixture>`) exactly one `^VALIDATE\t`
      line and every line starts with `FIND|CAP|INFO|NIX|STAT|VALIDATE|OUTCOME`.
      → verify red: exit 10 today.
   2. scan: `clean()`, used in `emit()` and the three `VALIDATE` printfs.
      audit: the one-`VALIDATE`/last-line-`STAT` check, drop `head -1`.
      → verify by the test printing `ok`, and `tests/scan-nix.sh` still `ok`.
   3. Commit `fix(scan): records cannot be forged by file names (#15)`.

2. **Item 2.**
   1. `tests/audit-ctl.sh` (host): git fixture with an https `origin`, commit
      subject containing `\e]52;c;aGk=\a`, a file whose name has an ESC and
      whose content has a hit; catalog `name` with an ESC, `repo` = the origin.
      Assert the text output, and `jq -r '..|strings'` of `--json`, contain no
      byte matched by `LC_ALL=C grep -qP '[\x00-\x08\x0b-\x1f\x7f]'`.
      → verify red.
   2. audit: `clean()` at each entry point listed in item 2, the `tr -d` pass
      over the raw output, `tr -c '[:print:]' ' '` in the three error messages.
      → verify green.
   3. Commit `fix(audit): no control characters from a plugin or the catalog (#15)`.

3. **Item 4** (before 5, 3 and 9, which use typed `file://` and the new
   `clone_hardened` arguments).
   1. `tests/audit-url.sh` (host): catalog fixture whose `plugins` starts with
      `42, "x", null`, then entries with `repo` = `file://<fx>`, `/<fx>`,
      `ssh://x/y`, `https://u@h/x`. Audited by id, each exits 2 with
      "refusing this URL" on stderr (today: "could not resolve", or a clone),
      and stdout has no report (the refusal comes before the clone). Typed `http://h/x` and `-uevil` exit 2. Typed `ssh://127.0.0.1:1/x`
      exits 3 (past `url_ok`, fails at clone). Typed `file://<fx>` exits 0 or
      10. → verify red.
   2. audit: `url_ok`; call it for the catalog URL, `$TARGET`, and (with
      `--install`) the local `origin`; `clone_hardened <url> <dest> <protocols>`
      with `GIT_ALLOW_PROTOCOL`; `catalog_entry` with `arrays`/`objects`.
      → verify green.
   3. Commit `fix(audit): clone only allowed URL kinds; skip junk catalog rows (#15)`.

4. **Item 5.**
   1. `tests/audit-symlink.sh` (host):
      - fixture repo commits `link.qml -> /usr/share/x`; typed `file://`
        audit `--json` has a NIX `fhs-path` at `link.qml:1`;
      - git folder with an https `origin`, one commit, plus an untracked
        `evil.qml -> /etc/passwd`, audited through a symlink to the folder:
        `--json` lists `evil.qml` under symlinks, `--install` prints
        "Refusing --install" and `$HOME/.config/omarchy/plugins` does not
        exist, `--export-tree <tmp>/x` exits 20;
      - non-git folder with a real symlink: listed under Symlinks.
      → verify red (today the typed clone writes a real link, and the
      untracked link is not listed).
   2. audit: `--config core.symlinks=false` on both clones; the post-staging
      `find -type l` that feeds `SYMLINKS` and deletes the links.
      → verify green.
   3. Commit `fix(audit): no real symlinks in staging (#15)`.

5. **Item 3.**
   1. `tests/audit-local-install.sh` (host): committed repo with an https
      `origin` and one uncommitted edit; `--install` exits 2 with "differs
      from HEAD" and `$HOME/.config/omarchy/plugins` does not exist. The same
      repo with `git rm --cached` of a committed file: also exit 2. A clean
      tree gets past the check (next message is "omarchy CLI not found" in CI,
      or an install into the temp `HOME` on a host).
      → verify red (temp `HOME` only).
   2. audit: the `$STAGE/head` clone and `diff -rq --no-dereference`; drop
      `|| true` at `:597` and add the `rev-parse HEAD` check.
      → verify green.
   3. Commit `fix(audit): a local --install installs exactly what was scanned (#15)`.

6. **Item 6.**
   1. `tests/audit-scan-blindspots.sh` (hermetic), scanner only: FIND
      `curl-pipe-shell` at `docs/runme:2`; FIND `dynamic-code-load` for a JS
      line `  * eval(x)` outside a block and none for one inside `/* … */`;
      FIND `curl-pipe-shell` for a shell line `//usr/bin/curl x | sh`; FIND
      `privileged-process-control-from-shared-temp` for `/tmp/a.pid` plus
      `sudo nice kill 1`. → verify red with GNU grep.
   2. scan: the `find` change, `code_lines`, the `.*` regex.
      → verify green, and `tests/scan-nix.sh` still `ok`.
   3. Commit `fix(scan): close the comment, extension and [^\n] blind spots (#15)`.

7. **Item 7.**
   1. `tests/audit-ids.sh` (host): local manifests with ids `../../x` and `-rf`
      exit 2 with "invalid plugin id"; catalog `verificationCommit: "HEAD~1"`
      gives `verifiedCommit == ""` and the malformed note; `uninstall.sh`
      copied next to a manifest with id `../../x`, with the temp `HOME` holding
      `.config/omarchy/plugins/` and a stub `omarchy` first on `PATH` that
      records its argv, never calls the stub. → verify red.
   2. audit: `id_ok`, the hex checks; `uninstall.sh`: the id test.
      → verify green.
   3. Commit `fix(audit): check plugin ids and commits before use (#15)`.

8. **Item 8.**
   1. `tests/audit-self.sh` (hermetic): the scanner on the repo root gives no
      FIND, no record with path `lib/omarchy-plugin-scan.sh`, no NIX record;
      a copy of the repo with `echo 'u ALL=(ALL) NOPASSWD: ALL'` added to a
      `.sh` still gives the FIND. → verify red.
   2. scan: reword the detector literals; `bin/nixarchy-plugin-fix:128`.
      → verify green, plus `tests/scan-nix.sh` and every earlier
      `tests/audit-*.sh` still `ok` (each detector keeps its positive test).
   3. Commit `fix(scan): the scanner no longer flags its own patterns (#15)`.

9. **Item 9.**
   1. `tests/audit-cancel.sh` (host): fixture repo whose
      `.git/objects/info/alternates` is a FIFO (`mkfifo`), so
      `git-upload-pack` blocks on it (confirmed on this machine). Run
      `omarchy-plugin-audit file://<fx> --no-sandbox --json` in the
      background; poll up to 10 s until `pgrep -f "<fx>"` finds the clone;
      `kill -TERM` the audit pid. Assert: the audit exits 143 within 5 s, no
      process matching `<fx>` is left after 1 s, and no
      `$TMPDIR/omarchy-audit.*` remains. The test's own trap runs
      `pkill -KILL -f "<fx>"` so a red run leaves nothing behind.
      → verify red: the clone and `git-upload-pack` survive today.
   2. audit: `BOUND_PID`, `_kill_group`, `_on_signal` and the three traps.
      → verify green; also SIGINT once by hand (exit 130).
   3. Commit `fix(audit): stop the staging child on TERM/INT/HUP (#15, for #17)`.
   4. Tell #17 (agent `panel`) the trap has landed on this branch, so #17
      does not add its own.

10. **Docs and version.** README URL kinds and "commit first"; CHANGELOG
    `## 0.5.1` with one short line per user-visible change; `manifest.json`
    `0.5.1`. → verify by `omarchy-plugin-validate .` passing.
    Commit `docs: 0.5.1 audit hardening (#15)`.

11. **Full check and live run** (Tests below), then open the PR linking
    `intent/`, `spec/` and `plan/2026-09-24-15-audit-hardening.md`. Hand-off
    notes in the PR: #18 owns `audit:152` and must not change `catalog_entry`;
    #17 relies on item 9; #20 keeps `STAT` records.

## Tests

Run from the repo root with `bash`, never sourced into an interactive shell:
some interactive shells here wrap `grep` as ugrep, which reads `[^\n]` as "not
newline" and would make the item 6 red run pass on today's code. Each test
pins `PATH=/run/current-system/sw/bin:$PATH`, where `grep` is GNU grep 3.12;
in `nix flake check` it is GNU grep too.

```bash
for t in tests/audit-*.sh; do printf '%s: ' "$t"; bash "$t" || echo FAILED; done
# expected: every line ends in "ok"

bash tests/scan-nix.sh         # ok
bash tests/catalog-list.sh     # ok
bash tests/preview.sh          # ok
node tests/model-check.mjs     # ok
nix flake check                # passes
omarchy-plugin-validate .      # passes

# once #19 has landed, the same files through the harness:
bash tests/run.sh hermetic     # PASS for audit-scan-blindspots, audit-self
bash tests/run.sh host         # PASS for the other audit-*.sh

# live, once, with network:
omarchy-plugin-audit crmne.hyprmoncfg   # same verdict as before this branch
omarchy-plugin-audit .                  # review-required (exit 10), NixOS likely-ok
```

## Rollback

Every item is its own commit, and nothing outside this repo changes (no state,
no config migration). To back out one item, `git revert <sha>` of its commit;
to back out all, revert the merge commit of the PR. Order matters in one case:
reverting item 4 also breaks the item 5, 3 and 9 tests, which use typed
`file://` and the new `clone_hardened` arguments, so revert those first. An
installed plugin is unaffected by a rollback; the audit only reads it.
