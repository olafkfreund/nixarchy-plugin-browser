---
status: draft
issue: 22
spec: spec/2026-09-24-22-detail-view-empty-fields.md
---

# Plan: The terminal detail view shows what the list shows

This plan is self-contained; it carries every approved decision (intent
`e296c51`, spec `3cdc44e`). Line numbers are on `master` at `d0e4dfc`.

**Decisions**

- **Every field the detail card prints is normalised**, not only name, author
  and category.
- **One per-entry jq def, `catalog_row`,** split out of `catalog_rows` in
  `CATALOG_ROWS_JQ` (`lib/catalog.sh`): the object `catalog_rows` builds
  today, moved unchanged and in the same key order. `catalog_rows` keeps the
  `objects`, community and id filters and the sort, and maps `catalog_row`.
- **One display default, `_or($d)`** (`if . == "" then $d else . end`), next
  to `_s`; `catalog_lines` uses it for its two `?` defaults. Same output.
- **`catalog_detail <id>`**, a new bash function in `lib/catalog.sh` next to
  `catalog_lines`: one `jq --raw-output0` over `$CATALOG`, fifteen
  NUL-terminated fields in `show_detail`'s read order. Name, author, category,
  stars, repo, install command, `installAvailable`, description and tags come
  from `catalog_row`; `version`, the verification fields, the two commits and
  `installNote` pass `_s` then `_or` with today's default. Unknown id: no
  output.
- **`bin/omarchy-plugin-browser`:** `entry_by_id` is deleted; `show_detail`
  keeps its `read` loop, fed by `catalog_detail`, and returns when a read
  fails (unknown id). Still one jq for the card (one process fewer).
- **`catalog.sh list` and `catalog_lines` stay byte-identical**, proven by
  `cmp` on both test fixtures and a copy of the cached real catalog.
- **Fixture (spec review):** extend the existing `c.tagmix` entry with the
  non-string cases (`"name": 7`, `"author": {}`, `"category": [1]`,
  `"version": {…}`, `"installNote": [...]`); no new entry. `GOOD`, the row
  count and every existing assertion stay unchanged.
- **Accepted behaviour change (spec review):** a string
  `"installAvailable": "true"` no longer shows the copy action in the card,
  matching the list. A non-string `version`, note or commit shows its default
  instead of the value.
- **Tests exercise the jq, not `gum`.**

## Steps

Scratch directory for the byte-identical check (never the user's cache):
`S=<scratchpad>/22` below. The before-snapshots use `master`'s
`lib/catalog.sh` against the *new* fixtures, so the fixture change in step 2
does not move the baseline.

1. Harness for the byte-identical check. Save as `$S/snap.sh`; it runs
   once with `old` (master's `lib/catalog.sh`) at the end of step 2, so the
   fixtures are the new ones, and once with `new` in step 6:

   ```bash
   #!/usr/bin/env bash
   # snap.sh TAG LIB  (run from the repo root)
   set -u; S=${S:?}; tag=$1 lib=$2
   mkdir -p "$S/cache/omarchy-plugin-audit"
   awk '/^cat >"\$FX\/catalog.json" <</{f=1;next} f&&/^EOF$/{exit} f' tests/catalog-list.sh >"$S/fixture.json"
   awk '/^cat >"\$FX\/hostile.json" <</{f=1;next} f&&/^EOF$/{exit} f' tests/catalog-list.sh >"$S/hostile.json"
   # A plain cp (no -p): the copy is fresh, so fetch_catalog does not refetch for CACHE_TTL (1 h).
   [[ -f $S/cache/omarchy-plugin-audit/catalog.json ]] \
     || cp -- "$HOME/.cache/omarchy-plugin-audit/catalog.json" "$S/cache/omarchy-plugin-audit/catalog.json"
   for c in fixture hostile cached; do
     f=$S/$c.json; [[ $c == cached ]] && f=$S/cache/omarchy-plugin-audit/catalog.json
     XDG_CACHE_HOME=$S/cache CATALOG=$f bash "$lib" list >"$S/$tag.$c.list" || echo "list failed: $c"
     (export XDG_CACHE_HOME=$S/cache CATALOG=$f; source "$lib"; catalog_lines) >"$S/$tag.$c.lines" || echo "lines failed: $c"
   done
   sha256sum "$S/cache/omarchy-plugin-audit/catalog.json" >>"$S/cached.sha"
   ```

   `git show master:lib/catalog.sh >"$S/catalog.old.sh"`. Run the whole
   pair (old and new) inside one hour, or delete `$S/cache` and redo both, so
   the copy is never refetched between them.
   → verify (after the `old` run in step 2) by six `$S/old.*` files, all
   non-empty, no "failed" line. (A dry run
   of this harness on `master` while writing the plan gave six non-empty
   files, all `cmp`-equal old vs old, and the cache copy untouched.)

2. `tests/catalog-list.sh`: replace the `c.tagmix` fixture line (line 58)
   with

   ```json
     { "id": "c.tagmix", "name": 7, "author": {}, "category": [1], "version": {"a": [1, 2]},
       "installNote": ["n"], "tags": ["y", 1], "sourceType": "community" },
   ```

   → verify by `bash tests/catalog-list.sh` still printing `ok` on today's
   code (`GOOD`, row count, `tags coerced`, the `System` filter unchanged).
   Then run `S=… bash "$S/snap.sh" old "$S/catalog.old.sh"`.

3. `tests/catalog-list.sh`: after the `catalog_lines System` check (line 91),
   add the detail check:

   ```bash
   # --- the terminal's detail card: the real catalog_detail (#22) -------------
   detail() {  # detail ID -> the fields, one per line, as show_detail reads them
     # shellcheck disable=SC2034 source=../lib/catalog.sh  # CATALOG is read by catalog_detail
     (CATALOG="$FX/hostile.json"; source "$LIB"; catalog_detail "$1") | tr '\0' '\n'
   }
   mapfile -t d < <(detail c.empty)
   [[ ${d[0]} == c.empty && ${d[1]} == '?' && ${d[3]} == System && ${d[4]} == 0 ]] \
     || fail "detail: c.empty" "$(detail c.empty)"
   mapfile -t d < <(detail c.tagmix)
   [[ ${d[0]} == c.tagmix && ${d[1]} == '?' && ${d[3]} == '?' && ${d[5]} == '?' \
      && ${d[12]} == '' && ${d[14]} == '#y' ]] || fail "detail: c.tagmix" "$(detail c.tagmix)"
   mapfile -t d < <(detail a.low)
   [[ ${d[0]} == Low && ${d[1]} == ann && ${d[4]} == 3 && ${d[11]} == true \
      && ${d[10]} == 'omarchy plugin add https://github.com/a/low' ]] || fail "detail: a.low" "$(detail a.low)"
   [[ ${#d[@]} == 15 ]] || fail "detail: expected 15 fields, got ${#d[@]}"
   [[ -z $(detail no.such.id) ]] || fail "detail: an unknown id gave output"
   ```

   Also add "and the terminal's detail card" to the header comment.
   → verify **red**: `bash tests/catalog-list.sh` fails at `detail: c.empty`
   (`catalog_detail: command not found`).

4. `lib/catalog.sh`, `CATALOG_ROWS_JQ`:
   - add `def _or($d): if . == "" then $d else . end;` after `_s`;
   - add `def catalog_row:` holding the object from `catalog_rows` (lines
     52-63, `{ id, … preview: (.previewThumbnail | _s) }`) verbatim, same key
     order;
   - `catalog_rows` becomes

     ```jq
     def catalog_rows:
       [ (.plugins // [])[] | objects
         | select(.sourceType == "community")
         | select(.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z"))
         | catalog_row ]
       | sort_by(-.stars);
     ```
   - `catalog_lines`: `(if .author == "" then "?" else .author end)` →
     `(.author | _or("?"))`, and the same for `.category`;
   - add after `catalog_lines`:

     ```bash
     # The terminal browser's detail card for one id: fifteen NUL-terminated
     # fields in this order (show_detail reads them so): name author repo
     # category stars version vstatus vcoverage vcommit upstream installCommand
     # installAvailable installNote description tags. Unknown id: no output.
     catalog_detail() {  # catalog_detail <id>
       jq --raw-output0 --arg id "$1" "$CATALOG_ROWS_JQ"'
         first(.plugins[]? | objects | select(.id == $id))
         | . as $e | catalog_row as $r
         | $r.name, ($r.author | _or("?")), $r.repo, ($r.category | _or("?")), ($r.stars | tostring),
           (.version | _s | _or("?")),
           (.verificationStatus | _s | _or("unverified")), (.verificationCoverage | _s | _or("none")),
           (.verificationCommit | _s | _or($e.listingValidatedCommit | _s)), (.upstreamObservedCommit | _s),
           $r.installCommand, ($r.installAvailable | tostring), (.installNote | _s), $r.description,
           ($r.tags | if length > 0 then "#" + join("  #") else "" end)
       ' "$CATALOG"
     }
     ```
   - header comment (lines 10-11): `CATALOG_ROWS_JQ  jq defs: catalog_row,
     catalog_rows, install_command`, and a line
     `catalog_detail <id>  the terminal browser's detail card fields`.

   → verify by `bash tests/catalog-list.sh` printing `ok` (green).

5. `bin/omarchy-plugin-browser`: delete `entry_by_id` and its comment
   (lines 52-56). In `show_detail` drop the `local e; e=$(entry_by_id …)`
   line, update the comment to "catalog_detail passes every field through
   _s, so no field holds a NUL or a control character", make the loop body
   `IFS= read -r -d '' "$v" || return` (unknown id: no output, so the first
   read fails and the card is not drawn), and feed it with
   `done < <(catalog_detail "$1")`. Nothing else in the function changes.
   → verify by `grep -n entry_by_id bin/ lib/ tests/` finding nothing and
   `bash -n bin/omarchy-plugin-browser`.

6. Byte-identical: `S=… bash "$S/snap.sh" new lib/catalog.sh`, then

   ```bash
   for f in "$S"/old.*; do cmp -- "$f" "${f/\/old./\/new.}" || echo "DIFF $f"; done
   uniq -c "$S/cached.sha"
   ```

   → verify by six silent `cmp`s (no `DIFF`) and `uniq -c` showing one hash
   with count 2 (the cache copy was not refetched between the runs). The
   user's `~/.cache/omarchy-plugin-audit/catalog.json` is only read, once, by
   `cp`.

7. `CHANGELOG.md`: if there is no `## Unreleased` section at the top, add one
   above `## 0.5.1`; add the bullet
   `- The terminal detail view shows the same name, author, category and stars as the list, and a bad catalog field shows its default, not raw JSON (#22)`
   → verify by `grep -n '^## ' CHANGELOG.md | head -2` (`Unreleased`, then
   `0.5.1`) and the bullet under it.

8. Manual, once (the owner): run `omarchy-plugin-browser`, open one
   well-formed plugin's card → verify it looks as before: name, `v…`,
   `by … · … · ★…`, tags, verification line, commits, repo, the same actions.

## Tests

From the repo root; each prints `ok` or passes:

```bash
bash tests/catalog-list.sh      # ok (red at step 3, green after step 4)
bash tests/preview.sh           # ok
bash -n lib/catalog.sh bin/omarchy-plugin-browser tests/catalog-list.sh
command -v shellcheck && shellcheck lib/catalog.sh bin/omarchy-plugin-browser tests/catalog-list.sh
node tests/model-check.mjs <(bash lib/catalog.sh list)   # passes
nix flake check                 # passes (plugin checks run tests/catalog-list.sh)
```

Plus step 6: six `cmp`-identical pairs (`fixture`, `hostile`, `cached` ×
`list`, `lines`). `git diff master --stat` lists only `lib/catalog.sh`,
`bin/omarchy-plugin-browser`, `tests/catalog-list.sh`, `CHANGELOG.md`.

Note: `node tests/model-check.mjs <(bash lib/catalog.sh list)` uses the
user's cache as today's suite does; run it with
`XDG_CACHE_HOME=$S/cache` to keep it on the scratch copy.

## Rollback

`git revert` the implementation commit(s). `entry_by_id` and the inline jq
come back; `catalog_row`, `_or` and `catalog_detail` go; the fixture line and
the detail check go with the test file. No cache, config or Nix state
changes; `rm -rf "$S"` removes the scratch copies.
