---
status: draft
issue: 15
intent: intent/2026-09-24-15-audit-hardening.md
---

# Spec: Harden the audit and the scanner

## Design

### Decisions carried from the intent approval

- Catalog-derived repo URLs must be `https://`. A URL the user typed may also be
  `ssh://` or `git@host:path`.
- A local `--install` whose working tree differs from `HEAD` is refused.
- The self-audit false positive is fixed by rewording the detector patterns.
  There is no allowlist.
- A bad plugin id refuses the audit (exit 2). A bad `verificationCommit` falls
  back to "unverified" and prints a warning.
- One spec and one plan, with one commit per item.

### Facts (checked 2026-09-24)

- **The catalog.** The cached catalog has 4085 entries. Every `.repo` matches
  `^https://github\.com/[A-Za-z0-9._~/-]+$`. All 4049
  `verificationCommit`/`listingValidatedCommit` values are 40 lowercase hex
  characters, and every `.id` passes the shell's id rule. The strict checks below
  therefore reject no real entry.
- **The id rule.** `omarchy-plugin-validate` accepts an id that matches
  `^[A-Za-z0-9][A-Za-z0-9._-]*$` and does not contain `..`. This spec reuses that
  rule exactly.
- **`[^\n]` in grep.** Under GNU grep 3.12 (`/run/current-system/sw/bin/grep`,
  and the grep inside bwrap), `printf 'sudo nice kill 1\n' | grep -cE
  '(sudo|pkexec)[^\n]*\b(kill|…)'` prints `0`. The same line without an `n` prints
  `1`. ugrep reads `[^\n]` as "not newline", so it would hide this bug.
- **Self-audit today.** `bash lib/omarchy-plugin-scan.sh .` gives:
  - FIND `sudoers-dangerous-passwordless-command` at `scan.sh:125`;
  - FIND `credential-path-access` at `scan.sh:147`;
  - NIX `fhs-path` at `scan.sh:212` and `bin/nixarchy-plugin-fix:128`;
  - NIX `imperative-pkg` at `scan.sh:167` and `:232`;
  - CAP records on the detector lines 93, 115, 131, 163, 167–171 and 176.
- **Git's own protocol gate.** `GIT_ALLOW_PROTOCOL` (colon-separated) limits
  every transport git uses, including redirects and submodules. Local paths
  count as `file`.

### 1. Records cannot be forged (`lib/omarchy-plugin-scan.sh`, `bin/omarchy-plugin-audit`)

- **Scanner.** One sanitiser, `clean() { local s=${1//[[:cntrl:]]/ }; printf '%s' "$s"; }`,
  is applied to every field after the kind:
  - `emit()` (`scan.sh:31`) cleans `$2`, `$3` and `$4`. That covers the path
    (`$rel:$ln`) in every caller, including the `emit` lines at `:106`, `:119`,
    `:134`, `:180`, `:224`, `:244`, `:258` and `:263`.
  - The three `VALIDATE` `printf`s (`:272-277`) clean their message the same
    way. The line format stays `VALIDATE<TAB>ok|fail|skip<TAB>message`.
  - A newline or tab in a file name therefore becomes a space. A record is
    always exactly one line.
- **Audit (defence in depth, `audit:379-382`).**
  - The raw output must have exactly one `^VALIDATE\t` line, and its last line
    must be `STAT\tscan\tcomplete`. Otherwise the audit exits 3 with "scanner
    output is malformed".
  - `head -1` is dropped.

### 2. No control characters reach the terminal or `--json` (`bin/omarchy-plugin-audit`)

- **Scanner evidence.** Covered by item 1 (`clean` in `emit`). This includes
  `cargo-git-unpinned` at `:106`.
- **Audit.** It gets the same one-line `clean()`. It is applied where each value
  enters the script, so the text report and `--json` both get clean values:
  - the commit subject, at `audit:286`, `:318` and `:331`;
  - every string read from the catalog entry, at `audit:170-176` (`CAT_NAME`,
    `VSTATUS`, `VCOVER`, `VMETHOD`, `CAT_STARS`). `VERIFIED_COMMIT` and
    `UPSTREAM_OBSERVED` are validated as hex instead (item 7);
  - symlink names shown at `audit:555`.
- **Defence in depth.** The raw scanner output goes through
  `tr -d '\000-\010\013-\037\177'` once, before the tally. That removes every C0
  control character except tab and newline, and DEL. It also covers the
  `--no-sandbox` path.
- **Error text.** Messages built from git's or cp's stderr (`audit:234`, `:292`,
  `:325`) change `tr '\n' ' '` to `tr -c '[:print:]' ' '`. Git relays text from
  the remote on stderr.
- `$TARGET` is what the user typed. It is not treated as hostile.

### 3. A local `--install` installs exactly what was scanned (`bin/omarchy-plugin-audit`)

- When `LOCAL_DIR` is set and `--install` is given, the audit checks the tree
  right after `copy_hardened` (`audit:283`), before the scan:
  1. It makes a hardened clone of `LOCAL_DIR` (the same `clone_hardened` path as
     item 5, bounded by `_bound_run`) into `$STAGE/head`.
  2. It checks out `SCAN_COMMIT` there.
  3. It runs `diff -rq --no-dereference -x .git "$CHECKOUT" "$STAGE/head"`.
     `diff` is in `/run/current-system/sw/bin`.
- Any difference exits 2 with "the working tree differs from HEAD (N paths,
  e.g. …); commit or stash, then re-run". The difference can be a modified,
  added, untracked or deleted file. Paths are cleaned.
- Checking bytes instead of running `git status` means the audit never runs a
  worktree command (status, diff, add) inside the user-named repo. That repo's
  `.git/config` could name a `core.fsmonitor` program, and a worktree command
  would run it.
- The install checkout (`audit:597`) loses its `|| true`. After it, `rev-parse
  HEAD` must equal `SCAN_COMMIT`, or the install is refused with exit 3. This
  covers remote and local targets alike.

### 4. Only allowed URL kinds are cloned (`bin/omarchy-plugin-audit`)

- A new function, `url_ok <url> <strict>`, replaces the guard at `audit:159-167`.
  - **Strict** is used for a URL from the catalog (`audit:155`). It accepts only
    `^https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/-]+$`, which rules out
    userinfo, query strings and fragments.
  - **Hand-typed** is used for `$TARGET` (`audit:147`). It accepts the https form
    above, `ssh://…` and `git@host:path`, and it refuses a leading `-`. See
    question 1 about `file://`.
  - A local folder's `origin` is used only as the catalog key, so it is not
    checked for a plain audit. With `--install` it becomes the installed
    plugin's origin (`audit:598`, `:607`), so the hand-typed rule applies there.
- A failure exits 2 with "refusing this URL: <kind> not allowed for a
  <catalog|typed> source".
- The bare-path gap closes: a `/path` or `file://` value from the catalog fails
  the strict rule.
- `omarchy-git-url-check` still runs after `url_ok` when it is present.
- **Belt and braces.** `clone_hardened` sets `GIT_ALLOW_PROTOCOL`: `https` for a
  catalog URL, and `https:ssh` (plus `file`, if question 1 is approved) for a
  typed URL. Git itself then refuses a redirect or rewrite to another transport.
- The two local clones (the install source at `audit:596` and the item 3 check)
  clone our own staging dir or the folder the user named. They set
  `GIT_ALLOW_PROTOCOL=file`.

### 5. No real symlinks in staging (`bin/omarchy-plugin-audit`)

- The clone at `audit:254-255` gains `--config core.symlinks=false`, which
  persists into the new repo, so the checkout at `audit:313-314` honours it. The
  global `-c` stays for the clone itself. The install clone at `audit:596` gets
  the same flag, so `audit:597` honours it too.
- **Local folders.** `cp -a` copies real symlinks. After staging, and before the
  scan, one `find "$CHECKOUT" -path "$CHECKOUT/.git" -prune -o -type l -print`
  runs for every mode:
  - the paths it finds are added to `SYMLINKS`, so the existing warning,
    `--install` refusal and `--export-tree` refusal apply;
  - the links are deleted from the staging copy.
  - For a clone, the list should always be empty. It is a check that costs
    nothing.
- **Why today's scan is less exposed than the intent says.** The scanner lists
  files with `find -type f` without `-L`, so it neither follows nor reads a
  symlink today. The problem is that staging holds real links, and the next
  tool that touches that tree may follow them. The fix makes the tree
  link-free.

### 6. Scanner blind spots (`lib/omarchy-plugin-scan.sh`)

- **Extensionless files in pruned directories (`:50-51`).** The second `find`
  adds `-o ! -name '*.*'`. It also adds `-o -name '*.py'`, the one code
  extension that `NIX_CODE` and the `scan()` filters already treat as code. The
  `file` check (`:57-64`) still decides whether each file is text.
- **Comments, by file type.** One awk filter, `code_lines <file>`, prints
  `NR:line` for each non-comment line. It replaces the `grep -n … | grep -vE
  comment` pairs at `:83`, `:108`, `:245` and `:249`, and `scan()` greps its
  output. The regex is unchanged and the output format stays `n:line`.
  - **`.qml`, `.js`, `.mjs`:** a comment is a `//` line, or a line inside a
    `/* … */` block. The block opens on a line whose first non-blank characters
    are `/*` and closes at the first `*/`. A closing line with code after `*/`
    is code. A `*` line outside a block is code.
  - **Every other file:** a `#` line or a `<!--` line. `//` is not a comment
    there, because `//usr/bin/curl … | sh` is a valid shell command.

  This fixes the root cause behind the `*` item. The comment filter guessed one
  syntax for every file, and in each file type it hid code the other syntaxes
  treat as comments (`*` in JS, `//` in shell, and a JS private field `#x`).
- **`[^\n]` (`:131`).** It becomes `(sudo|pkexec).*\b(kill|systemctl|renice)`.
  grep matches line by line, so `.*` never crosses a newline. The redundant
  `kill -` alternative goes.

### 7. Identifiers are checked before use (`bin/omarchy-plugin-audit`, `uninstall.sh`)

- **Plugin id.** `id_ok()` is the shell's rule:
  `[[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $1 != *..* ]]`.
  - The audit applies it to the final `PLUGIN_ID`, after `audit:337-338`. That
    covers the three places it comes from: the local manifest (`:144`), the
    target when it is used as an id (`:149`), and the manifest of the clone
    (`:338`).
  - A bad id exits 2 with "invalid plugin id". An empty id stays allowed for a
    plain audit, because some folders have none. `--install` already needs one
    (`audit:606`).
  - A catalog lookup by a hand-typed bad id (`:154`) is harmless: jq `--arg` is
    data. The id is checked before any path or argv uses it.
- **`uninstall.sh:12-15`.** The same test runs before the `-d` check and before
  `omarchy plugin remove`. A bad id prints "skipping widget removal: invalid id"
  and does not call `omarchy`.
- **Commits.** `VERIFIED_COMMIT` and `UPSTREAM_OBSERVED` (`audit:170-171`) must
  match `^[0-9a-f]{40}$`.
  - A value that fails is dropped, and the audit prints "note: the catalog's
    verification commit is malformed; treating this plugin as unverified".
  - In `--json` the key stays and holds `""`, as it does for any unverified
    plugin.
  - With `VERIFIED_COMMIT` empty, the existing fallback (`audit:298`) scans
    `origin/<default>`.

### 8. The audit passes its own plugin honestly

- Every literal keyword in a detector regex in `scan.sh` is spelled so the
  source line does not match itself. The repo already uses this for `pac[m]an`
  and `y[a]y` (`:164-166`), and that comment becomes the general rule. The
  lines are 93, 115, 125, 131, 147, 163, 167–171, 176, 212 and 232. Some
  examples:
  - `NOPASS[W]D`;
  - `\.ss[h]/`, `id_rs[a]`, …;
  - `par[u]`, `makepk[g]`;
  - `(^|[^A-Za-z0-9_.~])/op[t]/`;
  - `(sud[o]|pkexe[c])`;
  - `makefil[e]`.
- The INFO rules stay as they are, because INFO never counts toward a verdict.
- **`bin/nixarchy-plugin-fix:128`.** The prompt text becomes "use
  \$OMARCHY_PATH instead of the /usr/share path", with no slash and letter after
  `share`. The agent reads the same guidance.
- **Expected self-audit:**
  - no FIND anywhere;
  - no record at all for `lib/omarchy-plugin-scan.sh`;
  - NixOS `likely-ok`;
  - outcome `review-required` (exit 10), from real capabilities: `install.sh`
    and `lib/update.sh` install things, and `nixarchy-plugin-fix` builds.

  That is honest. A tool that installs things should ask for review.

### Unchanged

- Exit codes stay `0`/`10`/`20`/`2`/`3`. New refusals (URL, id, dirty local
  install) use 2. A malformed scan and a failed install-HEAD check use 3.
- The scanner line format stays the same.
- The `--json` keys stay the same.
- `audit:152`, the catalog note, belongs to #18. This work does not touch it.
  The plan's line numbers must be rechecked if #18 lands first.
- **Docs.**
  - README (`:125` area): the accepted URL kinds, and "commit first" for a
    local `--install`.
  - CHANGELOG: a 0.5.1 section.
  - `manifest.json`: 0.5.1.

## Alternatives rejected

- **Take the last `VALIDATE` line instead of the first.** Plugin text could
  still reorder or split records. The sanitised fields plus the one-line count
  close the class. Picking a different line only moves the race.
- **NUL-delimited scanner output.** It would change the line format that
  `--json`, the text report and the tests read. Cleaning the fields gets the
  same guarantee without the change.
- **`git status --porcelain` in the local folder.** The folder's `.git/config`
  can run `core.fsmonitor`, and `--assume-unchanged` or `--skip-worktree` can
  hide edits. A byte diff against a fresh clone trusts neither.
- **Install the working tree as scanned.** It was decided at approval to
  refuse instead.
- **Only the regex allowlist, or only `GIT_ALLOW_PROTOCOL`.** The regex gives a
  clean exit 2 and message, and git's gate covers redirects and URL rewrites
  from `insteadOf`. Each alone leaves a gap.
- **Allowlisting this plugin's own scanner file.** An attacker would copy an
  allowlist keyed on an id or a path. Rejected at approval.
- **Sanitising a bad id or commit instead of refusing it.** A cleaned id names
  a different folder than the one the plugin declared. Rejected at approval.
- **A real JS/QML comment parser.** The intent keeps this grep-grade. One awk
  state flag covers block comments.
- **`find -L` or `cp -L` for local folders.** That would copy the target's bytes,
  from outside the plugin, into staging. It is the exfiltration the fix exists
  to stop.

## Risks

- **Stricter URLs break a user who typed `http://…` or `file://…`.** An
  `http://` URL is refused now, because it is plaintext and can be tampered
  with in transit. `file://` depends on question 1. The README says so.
- **The comment filter now flags more.** Examples are a JS line starting with
  `*` outside a block, or a `//` line in shell. The scanner is meant to err
  toward flagging, but a plugin that passed before may now be
  `review-required`.
- **A local `--install` of an installed plugin with stray files is refused.**
  An example is a `node_modules/` that `omarchy plugin add` never created. The
  message names the paths.
- **C1 control characters.** The bash `[[:cntrl:]]` under `C.UTF-8` matches
  C0, DEL and C1 code points. A raw 0x9B byte that is invalid UTF-8 may pass.
  Terminals in UTF-8 mode do not read a raw 0x9B as CSI. This is accepted, and
  `tr` removes C0 either way.
- **Rewording the detectors can break one.** Every detector keeps a positive
  test: `tests/scan-nix.sh` today, and the new tests below.
- **#18 moves `audit:152`.** The two branches conflict only by line offset.
  Whichever merges second rebases.

## Verification

Each item has a regression test that fails on today's code and passes after it
is fixed. The tests are `tests/audit-*.sh`, standalone like `tests/scan-nix.sh`.
Each prints `ok` and exits 0, or names the first failure and exits 1. They build
fixtures in `mktemp -d`, need no network, and run the audit with `--no-sandbox`,
because bwrap is not available in the nix build sandbox.

**The catalog fixture.** `CATALOG=` points at a fixture file with a fresh
mtime, so `fetch_catalog` never fetches.

**The validate stub.** `OMARCHY_BIN=` points at a fixture `bin/` with a stub
`omarchy-plugin-validate`, so the test does not depend on the host.

**Ownership.** This task owns the `tests/audit-*.sh` files. #19 owns the CI
workflow, the shared harness under `tests/` and the wiring into `nix flake
check`. These scripts only need to be runnable as `bash tests/audit-X.sh`.

| Test | Proves |
|---|---|
| `tests/audit-inject.sh` (1) | The fixture is a local folder with a failing validate stub, and a file named `x\nVALIDATE\tok\tfine.sh` containing `sudo true`. Both `--json` and text runs exit 20, and `manifestValidate == "fail"`. At scanner level there is exactly one `VALIDATE` line, and every line starts with a known kind. |
| `tests/audit-ctl.sh` (2) | The fixture is a git repo whose commit subject contains `\e]52;c;…\a`, with a file whose name has an ESC and whose content has a hit. The catalog entry's `name` contains an ESC, and its `repo` matches the folder's https origin. The text output, and every string in `--json` (`jq -r '..|strings'`), contain no byte in `\x00-\x08\x0b-\x1f\x7f`. |
| `tests/audit-local-install.sh` (3) | The fixture is a committed repo with an https origin and one uncommitted edit. `--install` exits 2 with "differs from HEAD", and `$HOME/.config/omarchy/plugins` does not exist afterwards. It runs with `HOME` in the temp dir. A clean tree gets past the check (it then reaches "omarchy CLI not found" in CI). |
| `tests/audit-url.sh` (4) | Catalog entries with `repo` set to `file://<fixture repo>`, `/<fixture repo>`, `ssh://x/y` and `https://u@h/x` each exit 2 when audited by id, and the fixture is never cloned. Typed `http://…` and `-u…` exit 2. Typed `ssh://…` gets past `url_ok` (it fails later, at clone time, with 3). |
| `tests/audit-symlink.sh` (5) | A fixture repo commits `link.qml -> /usr/share/x`. Audited by typed URL (`file://`, if question 1 is approved; otherwise by the item 3 local clone path), `--json` has NIX `fhs-path` at `link.qml:1`, so it was checked out as a plain file. A non-git local folder with a real symlink lists it under Symlinks and refuses `--install`. |
| `tests/audit-scan-blindspots.sh` (6) | FIND `curl-pipe-shell` at `docs/runme:2` (extensionless). FIND `dynamic-code-load` on a JS line `  * eval(x)` outside a block, and none inside `/* … */`. FIND `curl-pipe-shell` on a shell line `//usr/bin/curl x \| sh`. FIND `privileged-process-control-from-shared-temp` for `/tmp/a.pid` plus `sudo nice kill`. |
| `tests/audit-ids.sh` (7) | Local manifests with ids `../../x` and `-rf` exit 2. A catalog `verificationCommit: "HEAD~1"` gives `verifiedCommit == ""` and the malformed note. `uninstall.sh`, copied next to a bad manifest with a stub `omarchy` on `PATH` that records its argv, never calls the stub. |
| `tests/audit-self.sh` (8) | The scanner, run on the repo root, gives no FIND, no record whose path is `lib/omarchy-plugin-scan.sh`, and no NIX record. For the mutation, a copy of the repo with one real `echo 'u ALL=(ALL) NOPASSWD: ALL'` line added to a `.sh` still gives the FIND. |

- **GNU grep, not ugrep.** Run the tests as `bash tests/audit-X.sh`, never
  sourced into an interactive shell. The scanner resolves `grep` from `PATH`,
  and here that is GNU grep 3.12. Some interactive shells on this machine wrap
  `grep` as ugrep, which reads `[^\n]` correctly and would make the item 6 test
  pass on today's code. Each test pins `PATH=/run/current-system/sw/bin:$PATH`,
  and in the nix check the grep is GNU.
- **Red first.** In the plan, each test is committed and run against the
  unfixed code to show it fails, then the fix follows in the same commit. On a
  nixarchy host the item 3 red run happens with a temp `HOME`, because the
  unfixed code would call the real `omarchy plugin add`.
- **Existing checks still pass:** `tests/scan-nix.sh`, `tests/catalog-list.sh`,
  `tests/preview.sh`, `node tests/model-check.mjs`, `nix flake check`, and
  `omarchy-plugin-validate .`.
- **Live, once:** `omarchy-plugin-audit crmne.hyprmoncfg` gives the same
  verdict as before, and `omarchy-plugin-audit .` on this repo gives
  `review-required` / `likely-ok`.

## Open question for the approver

1. **Typed `file://` URLs.** The intent says "`file://` and bare paths are
   refused unless they are the local folder the user named". A typed `file://`
   URL for a local bare repo is arguably exactly that. Allowing it is also the
   only no-network way to test the clone path (item 5). The proposal is to allow
   `file://` for typed URLs only, and never from the catalog or an `origin`.
