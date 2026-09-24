---
status: approved
issue: 18
spec: spec/2026-09-24-18-cli-robustness.md
---

# Plan: Make the CLIs survive bad input

This plan is self-contained; it carries every approved decision (intent
`778ff26`, spec `f35aecb`). Line numbers are on `master` at `449636c`.

**Decisions**

- **One bad catalog entry costs one entry, not the list.** Display fields are
  coerced to safe values; only an entry without a usable string `id` is
  dropped. Both list builders (the panel's `catalog.sh list` and the
  terminal's list) read one jq projection, `CATALOG_ROWS_JQ`, defined once in
  `lib/catalog.sh`:
  - non-object elements of `.plugins` are skipped (`objects`);
  - `id` must be a string matching `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z`
    (`Model.js` `ID_RE`). Every regex ends in `\z`, not `$`: in jq 1.8.2 `$`
    also matches before a trailing newline;
  - `stars`: a number passes, a numeric string converts, anything else, NaN
    and infinity become 0;
  - `tags`: an array keeps only its strings; anything else is `[]`;
  - control characters (`[[:cntrl:]]`) become spaces in every string, in the
    list **and** the detail view;
  - an empty name shows the id; in the terminal an empty author or category
    shows `?`;
  - `sort_by(-.stars)` (stable, so equal stars keep catalog order).
  `catalog_usable` gets no shape check.
- **The terminal list moves into `lib/catalog.sh`** as `catalog_lines
  [category]`, so `tests/catalog-list.sh` calls the real function. The tests
  stay in `tests/catalog-list.sh`, plus a new `tests/update.sh`; the
  preview regression extends the existing `tests/preview.sh`.
- **Install command from the checked repo** (added scope, from #17). The
  terminal no longer copies the catalog's `installCommand`. The command is
  `omarchy plugin add <repo>` (no trailing slash, no `--enable`, no `--yes`)
  when `installAvailable == true` and `repo` matches
  `^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/?\z`, else `""` and
  no copy action. One jq def, `install_command`, in `CATALOG_ROWS_JQ`, serves
  the terminal detail view and the projection's `installCommand` field.
- **Preview off switch fails closed** (added scope). A config file that
  exists but that jq cannot read (malformed, unreadable, jq missing) means
  previews are off: exit 4, no network. No config file still means on.
- **`--category` without a value** (missing, empty, or starting with `-`)
  exits 2 with `browser: --category needs a category name`.
- **Audit `--json`**: only `bin/omarchy-plugin-audit:152` changes; the note
  goes to stderr in JSON mode, byte-identical to stdout in text mode. `say`
  and `catalog_entry` are #15's.
- **`lib/update.sh`**, interface unchanged (subcommands, `check` JSON fields,
  cache path and cache contents):
  - `UPD_KEEP_LOADED=1` (this-plugin block): `BrowserState.qml` is a
    `pragma Singleton` that `omarchy plugin update` does not reload, so the
    terminal offers `omarchy restart shell`;
  - `fetch` gains `--proto '=https' --tlsv1.2`. `OMARCHY_PLUGIN_UPDATE_RAW`
    no longer accepts `file://` or `http://`; `check` falls back to the
    cache;
  - `ver_key` and the awk `key()` become length-prefixed keys (two-digit
    digit count, then the digits, leading zeros dropped, each part capped at
    99 digits). No arithmetic, no overflow; every version with parts of at
    most five digits orders as before;
  - offered upstream after merge (Omarchy Help), or recorded as a
    deliberate divergence.
- **Docs**: `docs/update-alerts.md:113` (the `file://` test tip) becomes the
  cache-file method plus "HTTPS-only"; `:131` "`file://` works" becomes "an
  `https://` base URL"; "In this plugin" says the panel is keepLoaded.
  `BarWidget.qml:163` mentions the offered restart.
- **CHANGELOG** user bullets; no manifest bump (that is release).

## Steps

Tests first; each new check is run against the unchanged code and must fail
before the code step that fixes it.

1. `tests/catalog-list.sh`: extend the fixture with community rows `"junk"`,
   `null`, `7`, `{"id": 42}`, `{"id": "c.bad stars"}`, `{"id": "c.nl\n"}`,
   `"stars": "5"`, `"stars": "abc"`, `"stars": "nan"`, `"tags": "x"`,
   `"tags": ["y", 1]`, `"name": "E\u001b[31m"`, `"name": ""` with
   `"author": ""`, a row with `"installCommand": "curl x | sh"` and a GitHub
   repo, and a row with `installAvailable: true` and
   `"repo": "https://gitlab.com/a/b"`. Keep every existing check. Add:
   `list` exits 0; the bad-id rows are absent and every other community row
   present; `"5"` sorts as 5; `"abc"`/`"nan"` give 0; `"x"` gives `[]`,
   `["y", 1]` gives `["y"]`; `all(.. | strings; test("[[:cntrl:]]") | not)`;
   the `curl` row's `installCommand` is `"omarchy plugin add
   https://github.com/…"`; the GitLab row's is `""`; `a.low`'s is exactly
   `"omarchy plugin add https://github.com/a/low"`.
   Then, sourcing `lib/catalog.sh` with `CATALOG` on the fixture:
   `catalog_lines` exits 0, prints one line per usable row, the last token of
   each line is its id, the empty-author row shows `—  ?`, and
   `catalog_lines System` prints only `System` rows.
   Then `timeout 5 bash bin/omarchy-plugin-browser --category` and
   `… --category --refresh` exit 2 (not 124).
   Then the audit note: `CATALOG=$FX/none.json unshare -rn bash
   bin/omarchy-plugin-audit --json no.such.id` gives empty stdout and stderr
   containing "could not fetch the marketplace catalog"; skipped with a
   message when `unshare -rn` fails.
   → verify by `bash tests/catalog-list.sh` failing on the first new check
   (`list` exits 5).
2. `tests/preview.sh`: after the off-switch block (`:43-49`), add two cases.
   (a) Config `{` (malformed): `bash "$LIB" preview
   assets/img/plugins/5-crmne-omarchy-hyprmoncfg-card.webp` exits 4 and
   `previews/` is not created. (b) Config `{"previews": false}`, in a
   subshell that sources the library and sets `PATH` to an empty temp dir:
   `fetch_preview <same path>` returns 4. → verify by `bash tests/preview.sh`
   failing on (a) (exit 3 offline, or 0 online).
3. `tests/update.sh` (new, executable, same style: `ok` / `FAIL: …`). Copy
   `lib/update.sh` to `$T/lib/update.sh`, write `$T/manifest.json`
   `{"version": "0.5.0"}`, point `HOME`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`
   into `$T`.
   - Source the copy (its `main` runs with no arguments, prints usage and
     returns 2; send that to `/dev/null`). Assert with `ver_gt`:
     `1.100000.0 > 1.99999.0`, `0.3.10 > 0.3.9`, `1.0.0 > 0.99.99`,
     `00010.0.0 > 9.0.0`, a 30-digit middle part `> 99.0.0`; and
     `ver_key 0.5.0 == ver_key 0.5.0`, `ver_key 1.2 == ver_key 1.2.0`,
     `ver_key 0.3.10 == 000130210`.
   - `changelog_notes` over a fixture CHANGELOG with `## 1.100000.0`
     (bullet `new`) and `## 1.99999.0` (bullet `old`), installed `1.99999.0`,
     latest `1.100000.0`, prints exactly `new`. This also proves the bash
     and awk keys agree: the bounds come from bash, the headings from awk.
   - With a fixture dir holding `manifest.json` `{"version": "9.9.9"}`:
     `OMARCHY_PLUGIN_UPDATE_RAW=file://<dir> bash "$T/lib/update.sh" check
     --force` prints JSON with `.latest == null and .update_available ==
     false`.
   - `grep -qx 'UPD_KEEP_LOADED=1.*' lib/update.sh`.
   → verify by `bash tests/update.sh` failing (the `1.100000.0` pair first).
4. `lib/catalog.sh`: after `CATALOG_MAX_BYTES` (`:29`), add the commented
   `CATALOG_ROWS_JQ` (defs `_s`, `install_command`, `catalog_rows`, exactly
   as in the spec, section 1, with `\z` anchors) and `catalog_lines` (spec
   section 1). Replace `list`'s jq (`:139-150`) with
   `jq -c "$CATALOG_ROWS_JQ catalog_rows" "$CATALOG" ;;`. Replace
   `previews_enabled` (`:80-83`) with the fail-closed version (`-e` test;
   `v=$(jq …) || return 1`; `[[ $v != false ]]`) and its comment. Add
   `catalog_lines [category]` to the header list (`:5-11`).
   → verify by `bash tests/preview.sh` → `ok`; `bash tests/catalog-list.sh`
   passes the projection and `catalog_lines` checks (the `--category` and
   audit checks still fail).
5. `bin/omarchy-plugin-browser`:
   - `:30` → `--category) [[ -n ${2:-} && $2 != -* ]] || { echo "browser:
     --category needs a category name" >&2; exit 2; }` then
     `ONLY_CAT=$2; shift 2 ;;`;
   - delete `badge_jq` and `list_lines` (`:51-74`); `main` (`:153`) pipes
     `catalog_lines "$ONLY_CAT"` into `gum filter`;
   - `entry_by_id` (`:76`) → `jq -c --arg id "$1" 'first(.plugins[] |
     objects | select(.id == $id)) | walk(if type == "string" then
     gsub("[[:cntrl:]]"; " ") else . end)' "$CATALOG"`;
   - tags line (`:92`) → `jq -r '(.tags | if type == "array" then
     map(strings) else [] end) as $t | if ($t | length) > 0 then "#" + ($t |
     join("  #")) else "" end'`;
   - install line (`:88`) → `install=$(jq -r "$CATALOG_ROWS_JQ
     install_command" <<<"$e")`; `:115` and `:124` unchanged.
   → verify by `bash tests/catalog-list.sh` passing the `--category` checks.
6. `bin/omarchy-plugin-audit:152` (only this line; if #15 moved it, the
   `fetch_catalog || say` line wherever it is): append
   `>&"$(( AS_JSON ? 2 : 1 ))"`. → verify by `bash tests/catalog-list.sh` →
   `ok`; and text mode unchanged: `CATALOG=/nonexistent unshare -rn bash
   bin/omarchy-plugin-audit no.such.id` prints the note on stdout as before.
7. `lib/update.sh`:
   - `:37` → `UPD_KEEP_LOADED=1   # BrowserState.qml is a pragma Singleton;
     omarchy plugin update keeps the old one (docs/manual/troubleshooting.md)`;
   - `fetch` (`:94`) gains `--proto '=https' --tlsv1.2`;
   - `ver_key` (`:54-60`) → the length-prefixed version with its comment
     (spec section 4); `ver_gt` unchanged;
   - awk `key()` (`:69`) → `function key(s,   n, a, i, d, k) { n = split(s,
     a, "."); k = ""; for (i = 1; i <= 3; i++) { d = a[i]; sub(/^0+/, "", d);
     d = substr(d, 1, 99); k = k sprintf("%02d", length(d)) d }; return k }`.
   → verify by `bash tests/update.sh` → `ok`.
8. `BarWidget.qml:163`: the update text ends "…, then install.sh relinks the
   commands (asks first), then offers a shell restart." → verify by
   `grep -n 'offers a shell restart' BarWidget.qml`, and the popup read once
   in the manual check (step 11).
9. `docs/update-alerts.md`:
   - `:113` → "To test without the network, write the cache file as above;
     the fetch is HTTPS-only, so `OMARCHY_PLUGIN_UPDATE_RAW` must be an
     `https://` base URL.";
   - `:131` → "`OMARCHY_PLUGIN_UPDATE_RAW` (an `https://` base URL)";
   - "In this plugin" Kind line: the keepLoaded panel needs the shell
     restart the update terminal offers.
   → verify by `grep -n 'file://' docs/update-alerts.md` returning nothing.
10. `CHANGELOG.md`: a `## Unreleased` section at the top (release renames it;
    the banner ignores non-numeric headings) with: one bad marketplace entry
    no longer empties the list; the update terminal offers the shell
    restart; the update check is HTTPS-only; the terminal browser copies an
    install command built from the plugin's GitHub repo. → verify by
    `grep -n '^## ' CHANGELOG.md | head -2` showing `Unreleased` then
    `0.5.0`, and `tests/update.sh` still `ok`.
11. Full check (see Tests), then one manual run of `omarchy-plugin-browser`
    and the panel against the live catalog: row count equal to before (the
    `total` header and the panel list), `c`/copy on a plugin shows
    `omarchy plugin add https://github.com/…`.
12. After merge: open the upstream PR against Omarchy Help with the `fetch`,
    `ver_key`/`key()` changes and the doc sentence; add one line naming it to
    "In this plugin" in `docs/update-alerts.md`. If declined, that line says
    this copy deliberately diverges. → verify by the PR link in the doc.

## Tests

Run from the repo root; each prints `ok` and exits 0.

```bash
bash tests/catalog-list.sh
bash tests/preview.sh
bash tests/update.sh
bash -n lib/catalog.sh lib/update.sh bin/omarchy-plugin-browser bin/omarchy-plugin-audit tests/*.sh
command -v shellcheck && shellcheck lib/catalog.sh lib/update.sh bin/omarchy-plugin-browser tests/catalog-list.sh tests/preview.sh tests/update.sh
node tests/model-check.mjs <(bash lib/catalog.sh list)     # passes, within its time budget
nix flake check                                             # passes
```

Before any code step, `bash tests/catalog-list.sh`, `bash tests/preview.sh`
and `bash tests/update.sh` each fail (steps 1-3). #19 wires them into CI.

## Rollback

Revert the implementation commits (`git revert <range>`); the tests revert
with them. Nothing is migrated: the update cache stores raw version strings,
so old and new `ver_key` read the same files, and no config or cache format
changes. If already released, a revert plus a patch release restores the old
behaviour; users who set a `file://` `OMARCHY_PLUGIN_UPDATE_RAW` get it back.
