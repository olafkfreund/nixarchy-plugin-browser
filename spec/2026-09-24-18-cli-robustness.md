---
status: draft
issue: 18
intent: intent/2026-09-24-18-cli-robustness.md
---

# Spec: Make the CLIs survive bad input

Approved in the intent: coerce the display fields and skip only entries that
have no usable string `id`. In `--json` mode, the catalog note goes to stderr.
Fix `lib/update.sh` here, keep its interface, and offer the fix upstream.

## Design

### 1. One shared catalog projection (`lib/catalog.sh`)

Both list builders will read one jq filter. It is defined once in
`lib/catalog.sh`, next to `CATALOG_MAX_BYTES` (`:29`), as a shell variable
that holds jq definitions. `bin/omarchy-plugin-browser` already sources this
file (`:42`), so it needs no new plumbing.

```bash
# The one projection of the untrusted catalog, shared by `catalog.sh list` (the
# panel) and the terminal browser. Every field may be missing or of any type:
# a bad field is coerced to a safe value; only an entry without a usable id is
# dropped. Control characters never reach a terminal or the panel.
CATALOG_ROWS_JQ='
  def _s: if type == "string" then gsub("[[:cntrl:]]"; " ") else "" end;
  def catalog_rows:
    [ (.plugins // [])[]
      | objects
      | select(.sourceType == "community")
      | select(.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"))
      | { id,
          name: ((.name | _s) as $n | if $n == "" then .id else $n end),
          author: (.author | _s), category: (.category | _s),
          stars: (.stars | if type == "number" then . elif type == "string" then (tonumber? // 0) else 0 end
                  | if isinfinite or isnan then 0 else . end),
          tags: (.tags | if type == "array" then map(select(type == "string") | _s) else [] end),
          badge: (if .verificationStatus == "verified" then "verified"
                  elif .verificationSnapshotStatus == "verified" then "snapshot"
                  else "unverified" end),
          description: (.description | _s), repo: (.repo | _s),
          installCommand: (.installCommand | _s), installAvailable: (.installAvailable == true),
          preview: (.previewThumbnail | _s) } ]
    | sort_by(-.stars);'
```

Why each piece is there:

- `objects` drops array elements that are not objects (`"junk"`, `7`, `null`).
  Without it, `.sourceType` on a string stops jq, the same way `-.stars` does
  today.
- The id regex is `ID_RE` from `Model.js:42`, the one `parseRows` (`:83`)
  already applies. This makes "usable string id" mean the same thing in the
  panel and the terminal. The terminal needs this too: `list_lines` takes the
  id as the last whitespace token (`bin/omarchy-plugin-browser:59`), so an id
  with a space would break the picker.
- `stars`: a number passes through. A numeric string (`"5"`) becomes the
  number. Anything else becomes 0, and so do NaN and infinity. `"nan"`
  converts to NaN and serialises as `null`, and `1e400` is infinite, so
  neither would sort or print sanely.
- `tags`: an array keeps only its string elements, and anything else becomes
  `[]`.
- `_s` replaces control characters (ESC, newline and the rest of
  `[[:cntrl:]]`) with spaces. `list_lines` prints with `jq -r` straight into
  `gum filter`, so an ESC sequence in a name would reach the terminal. A
  newline would also split one row into two lines. `Model.clean` already does
  this for the panel (`Model.js:56`), so the panel shows the same text.
- `sort_by` is stable, so plugins with equal stars keep catalog order, as
  they do today.

This filter was run against a hostile fixture (non-object entries, `"stars":
"5" | "abc" | "nan" | "1e400"`, `"tags": "x"`, mixed-type tag arrays, id `42`,
id `"c.bad stars"`, an ESC in a name, `"name": 7`, `"author": {}`). jq exits
0, the bad-id rows are dropped, and every other row is listed with coerced
values.

`lib/catalog.sh:139-150` (`list`) becomes:

```bash
jq -c "$CATALOG_ROWS_JQ catalog_rows" "$CATALOG" ;;
```

`bin/omarchy-plugin-browser:51-74`: `badge_jq` is deleted. The badge glyph
now comes from the projected `badge` word, and `list_lines` becomes:

```bash
list_lines() {  # one selectable line per plugin; id is the final token
  jq -r "$CATALOG_ROWS_JQ"'
    catalog_rows[]
    | select($cat == "" or .category == $cat)
    | [ ({verified: "✔", snapshot: "◐"}[.badge] // "·"), "  ", .name,
        "  —  ", (if .author == "" then "?" else .author end),
        "   ", (if .category == "" then "?" else .category end),
        "   ★", (.stars | tostring),
        (if (.tags | length) > 0 then "   #" + (.tags | join(" #")) else "" end),
        "   ", .id ] | join("")
  ' --arg cat "$ONLY_CAT" "$CATALOG"
}
```

The badge comment (`:51-52`) moves above `list_lines`.

The detail view reads the raw entry, not the projection, because it needs
fields the projection drops (version, commits, installNote). Two lines there
fail on the same kinds of input, so both are hardened:

- `entry_by_id` (`:76`) becomes
  `jq -c --arg id "$1" 'first(.plugins[] | objects | select(.id == $id)) | walk(if type == "string" then gsub("[[:cntrl:]]"; " ") else . end)' "$CATALOG"`.
  A non-object element no longer stops the search. Control characters are
  stripped from every field that `show_detail` prints. `first(...)` replaces
  `| head -1`.
- The tags line (`:92`) becomes
  `jq -r '(.tags | if type == "array" then map(strings) else [] end) as $t | if ($t | length) > 0 then "#" + ($t | join("  #")) else "" end'`.

`catalog_usable` (`lib/catalog.sh:34-39`) is **not** given a shape check.
`download_catalog` already requires `.plugins` to be an array (`:51`), so the
only remaining problem was per-entry types, and the projection now handles
those. A cached catalog with one bad entry no longer fails, so there is
nothing to evict.

### 2. `--category` without a value (`bin/omarchy-plugin-browser:30`)

```bash
--category) [[ -n ${2:-} && $2 != -* ]] || { echo "browser: --category needs a category name" >&2; exit 2; }
            ONLY_CAT=$2; shift 2 ;;
```

Exit 2 is the code for an unknown option (`:32`). A missing value, an empty
value, or an option in the value's place (`--category --refresh`) is
refused. No real category begins with `-`.

### 3. Audit note in `--json` mode (`bin/omarchy-plugin-audit:152`, only this line)

```bash
fetch_catalog || say "${YEL}note: could not fetch the marketplace catalog; continuing without verification metadata.${RST}" >&"$(( AS_JSON ? 2 : 1 ))"
```

`AS_JSON` is set during option parsing (`:83,90`), before this line. Text
mode still writes to fd 1 with the same bytes. `say` itself does not change,
so #15's ownership of the rest of the file is respected.

### 4. `lib/update.sh`

- **keepLoaded** (this-plugin block, `:37`): `UPD_KEEP_LOADED=1`, and the
  comment says why: `BrowserState.qml` is a `pragma Singleton` that `omarchy
  plugin update` does not reload (`docs/manual/troubleshooting.md:29-36`).
  The terminal then counts three steps and offers `omarchy restart shell`
  (`:206-208`). The "picks up the new files by itself" branch stays in the
  shared code for other plugins. `BarWidget.qml:163` gets
  "…, then install.sh relinks the commands (asks first), then offers a shell
  restart." so the banner says the same as the terminal.
- **HTTPS only** (shared part, `fetch`, `:93-95`): add `--proto '=https'
  --tlsv1.2`, the same flags as `lib/catalog.sh:48,121`. A non-HTTPS
  `OMARCHY_PLUGIN_UPDATE_RAW` then fails the fetch. `check` falls back to
  the cache, as it does offline. `docs/update-alerts.md:113` currently says
  to "Point `OMARCHY_PLUGIN_UPDATE_RAW` at a `file://` folder to test the
  fetch offline". That sentence is replaced with the cache-file method from
  the same bullet (`:110-112`), plus a note that the fetch is HTTPS-only.
- **`ver_key`** (shared part, `:54-60`): each of the first three numeric
  parts becomes a two-digit length followed by its digits, with leading
  zeros stripped. Comparing two keys then compares the lengths first and the
  digits second, for any part up to 99 digits. There is no arithmetic, so
  nothing can overflow.

  ```bash
  # A version as a string key that orders numerically under plain string
  # comparison, in bash and in awk alike: each of the first three parts is its
  # digit count (two digits) then its digits, leading zeros dropped
  # ("0.3.10" -> "000130210"). Parts are capped at 99 digits.
  ver_key() {
    local a b c p out=""
    read -r a b c _ <<<"$(printf '%s' "${1:-0}" | tr -c '0-9' ' ')"
    for p in "${a:-0}" "${b:-0}" "${c:-0}"; do
      while [[ $p == 0* ]]; do p=${p#0}; done
      p=${p:0:99}
      printf -v out '%s%02d%s' "$out" "${#p}" "$p"
    done
    printf '%s' "$out"
  }
  ```

  The awk `key()` in `changelog_notes` (`:69`) is changed to match:

  ```awk
  function key(s,   n, a, i, d, k) { n = split(s, a, "."); k = ""
    for (i = 1; i <= 3; i++) { d = a[i]; sub(/^0+/, "", d); d = substr(d, 1, 99); k = k sprintf("%02d", length(d)) d }
    return k }
  ```

  Prototyped: `1.100000.0 > 1.99999.0`, `0.3.10 > 0.3.9`, `1.0.0 > 0.99.99`,
  `00010.0.0 > 9.0.0`, a 30-digit part `> 99.0.0`, `0.5.0 = 0.5.0`, and
  `1.2 = 1.2.0`. For `1.100000.0`, the bash and awk keys are the same string.
  Any two versions whose parts all have at most five digits are ordered
  exactly as before. Key strings are never stored: `latest`, `dismissed` and
  `notes_for` in the cache hold raw version strings (`:125,138,158`), so
  existing cache files keep their meaning. The subcommands, the `check` JSON
  fields and the cache path do not change.
- **Upstream:** after merge, open a PR against the reference copy (Omarchy
  Help, `docs/update-alerts.md:10`) with the `fetch` and `ver_key`/`key()`
  changes and the doc sentence. Add one line to the "This plugin's copy"
  section of `docs/update-alerts.md` that names the PR. If upstream declines
  it, change that line to call this a deliberate divergence.

### 5. CHANGELOG

Add bullets for users under the next version: one bad marketplace entry no
longer empties the list, the update terminal now offers the shell restart,
and the update check is HTTPS-only. The manifest version bump belongs to
release, not to this spec.

## Alternatives rejected

- **Two separate fixes, one per list builder.** Both would repeat the same
  type handling, and the two would drift apart again. That drift is how
  `list_lines` ended up with a `tags` bug that `list` does not have. The
  shared filter removes more code than it adds.
- **Having the terminal browser call `catalog.sh list` and format its JSON.**
  That is a second jq pass and a subprocess for the same result. The variable
  is shared through `source`, which already happens.
- **Skipping any entry with a bad field.** The approver chose coercion. One
  odd `stars` value should not hide an otherwise fine plugin.
- **A shape check in `catalog_usable`, or evicting the cache.** This is not
  needed once the reader tolerates bad entries. It would also add a full jq
  parse to every cache hit.
- **A `notes` field in the audit report.** The approver chose stderr. A new
  field changes the report schema and reaches into #15's code.
- **Changing `say` to write to stderr in JSON mode.** That is #15's file and
  #15's decision. Redirecting at line 152 alone is enough.
- **`ver_key` with wider fixed-width padding (for example `%020d`).** This
  still overflows `$((10#…))` past 18 digits and still has a ceiling. The
  length prefix needs no arithmetic.
- **`sort -V` for comparison.** It does not help the awk side, which needs a
  key per section heading, and it would split the logic between two tools.
- **Allowing `file://` as well as `https`** to keep the documented test hook.
  The intent requires HTTPS only, and the cache-file method already tests the
  banner without a fetch.
- **Accepting `--category=<name>`.** Nobody has asked for it.

## Risks

- **Small display changes for odd but valid input.** An explicitly empty
  `name` now shows the id in the terminal as well (the panel already does
  this: `r.name || r.id`). An explicitly empty `author` or `category` shows
  `?`, where it showed an empty string before. Control characters in any
  field show as spaces. A well-formed catalog lists the same rows in the same
  order.
- **Stricter ids in the terminal.** An entry whose id fails `ID_RE` no longer
  shows in the terminal browser. The panel already hid these entries. None of
  the live ids fail it: the cached catalog of 2026-09-24 has 4049 community
  entries, and 0 of them fail.
- **The `[[:cntrl:]]` class under jq's Oniguruma** was checked with jq 1.8.2
  (the version in the closure). A different jq in nixpkgs could behave
  differently. The test fixture covers this.
- **`walk` in `entry_by_id`** costs one pass over a single entry, which is
  negligible.
- **The update terminal now asks for a restart after every update.**
  Answering "n" skips it. This is what the manual already says.
- **HTTPS-only breaks anyone who points `OMARCHY_PLUGIN_UPDATE_RAW` at
  `file://` or `http://`.** They get the cached answer instead of a fresh one.
  This affects only developers, and the doc changes with the code.
- **Other Omarchy.Fans plugins keep the old `ver_key` until they take the
  upstream fix.** Nothing is shared between plugins at run time, so the copies
  cannot conflict.
- **Merge overlap with #15** on `bin/omarchy-plugin-audit`. The change is
  confined to line 152. If #15 lands first and moves the line, the plan
  re-applies it to wherever `fetch_catalog || say` ends up.
- Nothing here touches the flake package's file set, the Nix checks, or any
  host.

## Verification

Each check fails on the current `master` and passes with the fix. #19 owns the
CI workflow and the shared test harness. These are standalone scripts in the
existing style (print `ok`, exit 0, or name the first failure and exit 1), and
#19 wires them in.

- **`tests/catalog-list.sh`**: the fixture gains hostile rows: `"junk"`,
  `null`, `{"id": 42}`, `{"id": "c.bad stars"}`, `"stars": "5"`, `"stars":
  "abc"`, `"stars": "nan"`, `"tags": "x"`, `"tags": ["y", 1]`, and `"name":
  "E\u001b[31m"`, all marked `"sourceType": "community"`. New checks:
  - `list` exits 0 (today it exits 5).
  - The bad-id rows are absent, and every other community row is present.
  - `"5"` sorts as 5.
  - `"abc"` and `"nan"` give 0.
  - `"tags": "x"` gives `[]`, and `["y", 1]` gives `["y"]`.
  - No output string contains a control character:
    `all(.. | strings; test("[[:cntrl:]]") | not)`.

  The existing checks are unchanged, which covers "a good catalog lists as
  before".
- **Terminal list**: the same script checks `list_lines` output. It sources
  `lib/catalog.sh` and runs the same `jq -r "$CATALOG_ROWS_JQ"…` pipeline
  against the fixture. The check: exit 0, one line per usable row, and the
  last token of each line is its id. Alternatively, `list_lines` moves into
  `lib/catalog.sh` so the test can call it directly (see the questions below).
- **`--category`**, in the same script:
  `timeout 5 bash bin/omarchy-plugin-browser --category` must exit 2, not
  124. The same goes for `--category --refresh`. Argument parsing runs before
  the gum check (`:27-36`), so no terminal is needed.
- **Audit `--json` note**: `CATALOG=$FX/none.json unshare -rn bash
  bin/omarchy-plugin-audit --json no.such.id` has no network and no cache.
  stdout must be empty, and stderr must contain "could not fetch the
  marketplace catalog". Checking stderr proves that line 152 was reached.
  Today the note is on stdout. The check is skipped with a message if
  `unshare -rn` is unavailable.
- **New `tests/update.sh`**, run against a copy of `lib/update.sh` in a temp
  dir with `HOME` and `XDG_CACHE_HOME` pointed at the fixture:
  - `ver_key`: the script sources a copy of `lib/update.sh`. `main` runs on
    source with no arguments, prints usage and returns 2, which is harmless;
    or the plan extracts the functions with `sed`. It asserts every pair
    listed above, and that the bash key and the awk key are equal for the
    same versions. It also asserts that `changelog_notes` over a fixture
    CHANGELOG with `## 1.99999.0` and `## 1.100000.0` sections returns only
    the newer section's bullets for installed `1.99999.0`.
  - `--proto`: `OMARCHY_PLUGIN_UPDATE_RAW=file://$FX` with a `manifest.json`
    of `9.9.9`, and `check --force` with an empty cache. `latest` must be
    `null` and `update_available` must be `false`. Today curl reads the file
    and reports 9.9.9.
  - keepLoaded: `grep -qx 'UPD_KEEP_LOADED=1.*' lib/update.sh`. The terminal
    is interactive, so asserting the setting is the smallest honest check.
- **The rest**:
  - `bash -n` on every changed script.
  - `shellcheck`, if it is present.
  - `node tests/model-check.mjs <(bash lib/catalog.sh list)` still passes on
    the new projection output, and within its time budget.
  - `nix flake check` passes.
  - One manual run of the terminal browser and the panel against the live
    catalog, with the row count the same as before the change.
