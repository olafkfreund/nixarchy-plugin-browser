---
status: approved
issue: 22
intent: intent/2026-09-24-22-detail-view-empty-fields.md
---

# Spec: The terminal detail view shows what the list shows

Approved in the intent: normalise every field the detail card prints; one
per-entry jq def shared by `catalog_rows` and `show_detail`; test the jq
against the existing hostile fixture in `tests/catalog-list.sh`. Kept from
the constraints: `catalog.sh list` output stays byte-identical, and the
detail card stays one `jq --raw-output0` call.

Decided at spec review (olafkfreund):

- **Fixture:** extend the existing `c.tagmix` entry with the non-string cases
  (`"name": 7`, `"author": {}`, `"category": [1]`, `"version": {…}`,
  `"installNote": [...]`) rather than adding a new entry. `GOOD`, the row
  count and every existing assertion stay unchanged.
- **`installAvailable` as a string:** the behaviour change is accepted. A
  string `"installAvailable": "true"` no longer shows the copy action in the
  card, matching the list.

## Design

### `lib/catalog.sh`, `CATALOG_ROWS_JQ`

1. **Split out `catalog_row`.** The object built inside `catalog_rows` today
   (`{ id, name, author, … preview }`, lines 52-63) moves, unchanged and in
   the same key order, into `def catalog_row:`. `catalog_rows` becomes:

   ```jq
   def catalog_rows:
     [ (.plugins // [])[] | objects
       | select(.sourceType == "community")
       | select(.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z"))
       | catalog_row ]
     | sort_by(-.stars);
   ```

   The community filter and the id check stay in `catalog_rows`; `catalog_row`
   is the per-field coercion only. Same expressions, same key order, so the
   `list` JSON is byte-identical.

2. **One display default, `_or`.** `def _or($d): if . == "" then $d else . end;`
   next to `_s`. `catalog_lines` uses `.author | _or("?")` and
   `.category | _or("?")` in place of its two inline `if … end`, so the "empty
   shows `?`" rule is written once and both views use it. Same output.

3. **`catalog_detail <id>`**, a new bash function next to `catalog_lines`,
   replaces `entry_by_id` plus the inline jq in `show_detail`. One jq over
   `$CATALOG`, `--raw-output0`, fifteen fields in the order `show_detail`
   reads them:

   ```jq
   first(.plugins[]? | objects | select(.id == $id))
   | . as $e | catalog_row as $r
   | $r.name, ($r.author | _or("?")), $r.repo, ($r.category | _or("?")), ($r.stars | tostring),
     (.version | _s | _or("?")),
     (.verificationStatus | _s | _or("unverified")), (.verificationCoverage | _s | _or("none")),
     (.verificationCommit | _s | _or($e.listingValidatedCommit | _s)), (.upstreamObservedCommit | _s),
     $r.installCommand, ($r.installAvailable | tostring), (.installNote | _s), $r.description,
     ($r.tags | if length > 0 then "#" + join("  #") else "" end)
   ```

   - Name, author, category and stars come from `catalog_row`, so they match
     the list line by construction.
   - The fields `catalog_row` does not carry (`version`, the two verification
     fields, the two commits, `installNote`) go through the same `_s`, then
     `_or` with today's default. `$e` is needed for the commit fallback:
     `_or`'s argument is evaluated against the empty string, not the entry.
   - `installAvailable` is now `true` only for JSON `true`, as in the list;
     today a string `"true"` reached the card's `[[ $avail == true ]]`.
   - Tags keep the card's `#a  #b` format, now from `catalog_row`'s cleaned
     string list.
   - Every field has passed `_s` (or is a number turned into a string by
     `tostring`), so no control character and no NUL can appear; an object,
     array or number never prints where text is expected.
   - An unknown id gives no output.

   A comment above it names the field order.

### `bin/omarchy-plugin-browser`

- `entry_by_id` is deleted (its only caller was `show_detail`; its
  control-character `walk` is replaced by `_s` on every field).
- `show_detail` keeps its `for v in name author … tags; do IFS= read -r -d ''`
  loop, now reading `< <(catalog_detail "$1")`. The first `read` failing (no
  output: unknown id) returns, which replaces the `[[ -n $e ]] || return`
  guard. The rest of the function (the `vline` case, the `gum` card, the
  actions) is unchanged.

Still one jq for the whole card; one fewer process than today (the separate
`entry_by_id` jq goes).

### Other files

- `tests/catalog-list.sh`: the fixture change and the new check, below.
- `CHANGELOG.md`, `Unreleased`: "The terminal detail view shows the same
  name, author, category and stars as the list, and a bad catalog field
  shows its default, not raw JSON (#22)."
- `lib/catalog.sh` header comment (line 10): the defs list names
  `catalog_row`, and `catalog_detail <id>` joins the function list.

## Alternatives rejected

- **Call `catalog_rows` and pick the entry by id.** It projects and sorts all
  ~3,100 entries to show one card, and it drops the fields the card needs
  (`version`, `installNote`, the verification fields).
- **Add the extra fields to `catalog_row`.** They would then appear in every
  row of `catalog.sh list`, which must stay byte-identical, and the panel does
  not use them.
- **Keep the jq inline in `show_detail`, only swapping `//` for `_s`.**
  Leaves the "bad field" rules written twice and the jq untestable without
  `gum`, which the intent asks to avoid.
- **A `detail_fields` jq def only, with `entry_by_id` kept.** Works, but keeps
  two jq processes and a bash function whose `walk` the `_s` calls make
  redundant. `catalog_detail` next to `catalog_lines` is the testable unit
  the intent suggests.
- **Normalise only name, author, category.** Declined at the intent.

## Risks

- **`list` output drifts.** Guarded by the byte-for-byte comparison below,
  on both fixtures and the real cached catalog.
- **Field order between `catalog_detail` and `show_detail`'s `read` loop**
  lives in two files. A mismatch shows the wrong text in the wrong place, not
  an injection (every field is clean). Guarded by the comment and by the test
  checking fields by position.
- **Card for a well-formed entry changes.** For good input every expression
  yields what `//` did, with two deliberate exceptions: a string
  `"installAvailable": "true"` no longer shows the copy action (it matches
  the list; accepted at spec review), and a non-string `version`, note or commit (for example
  `"version": 2`) now shows its default instead of the value.
  Checked by the `a.low` assertion below and one manual card.
- **Hosts:** none. No Nix, service or network change; the flake's `plugin`
  package copies both files and its checks run `tests/catalog-list.sh`.

## Verification

Red first: add the fixture fields and the check, run `tests/catalog-list.sh`
on today's code and see it fail (`catalog_detail` does not exist yet); then
implement and see `ok`.

**Fixture.** The hostile fixture has `c.empty` (`"name": ""`, `"author": ""`)
but no non-string text field. Give the existing `c.tagmix` entry non-string
values, so no new entry is added and `GOOD`, the row count and every existing
assertion stay as they are:

```json
{ "id": "c.tagmix", "name": 7, "author": {}, "category": [1], "version": {"a": [1, 2]},
  "installNote": ["n"], "tags": ["y", 1], "sourceType": "community" }
```

(Its list row then shows the id as name and `?` for author and category; no
current assertion reads those, and it stays out of the `System` filter.)

**Check**, after the `catalog_lines` block, calling the real function:

```bash
detail() {  # detail ID -> the fields, one per line, as show_detail reads them
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

A prototype of the jq, run while writing this spec on a copy of these
entries, gave `c.empty|?||System|0|?|…` and `c.tagmix|?||?|0|?|…|#y`.

**Byte-identical `list` and `catalog_lines`.** Before the change, save
`catalog.sh list` and `catalog_lines` for `tests/`' two fixtures and for the
cached real catalog (`~/.cache/omarchy-plugin-audit/catalog.json`) to the
scratchpad; after it, rerun and `cmp` each pair. All must be identical. The
real catalog is read from a copy under a temporary `XDG_CACHE_HOME` in the
scratchpad, never from (or written to) the user's own cache.

**Suite**, from the repo root, each prints `ok` or passes:

```bash
bash tests/catalog-list.sh
bash tests/preview.sh
bash -n lib/catalog.sh bin/omarchy-plugin-browser tests/catalog-list.sh
command -v shellcheck && shellcheck lib/catalog.sh bin/omarchy-plugin-browser tests/catalog-list.sh
node tests/model-check.mjs <(bash lib/catalog.sh list)
nix flake check
```

**Manual**, once: `omarchy-plugin-browser`, open one well-formed plugin's
card; it looks as before (name, `v…`, `by … · … · ★…`, tags, verification
line, repo, the same actions).
