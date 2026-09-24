---
status: draft
issue: 22
author: olafkfreund
---

# Intent: The terminal detail view shows what the list shows

## Problem

#18 made the catalog projection safe: `CATALOG_ROWS_JQ` in `lib/catalog.sh`
turns every field into a clean string (`_s`), and `catalog_lines` shows an
empty `name` as the id and an empty `author` or `category` as `?`.
`tests/catalog-list.sh:88` checks that the list does this.

The detail view does not. `show_detail` in `bin/omarchy-plugin-browser`
(`:58-109`, one `jq --raw-output0` since #20 phase B) loads
`CATALOG_ROWS_JQ` but reads the raw entry from `entry_by_id` with its own
fallbacks:

```jq
.name//.id, .author//"?", .repo//"", .category//"?", .stars//0, .version//"?", …
```

`//` replaces only `null` and `false`. So for a plugin whose list line looks
right, the detail view shows:

- `"name": ""` → an empty bold title and an empty `gum choose` header;
- `"author": ""` or `"category": ""` → `by    ·    ·   ★3`;
- a non-string value, such as `"name": 7` or `"author": {}` → the number,
  or the value printed as JSON (`{}`, or several lines for a larger
  object) inside the card.

The same pattern covers the other fields that line reads: `repo`, `stars`,
`version`, `description`, `installNote` and the verification fields. Only
`tags` and the install command already go through a type check. The list
and the details can disagree about the same plugin, and a crafted catalog
entry can control what the detail card looks like, within the limits of
`entry_by_id`'s control-character scrub.

## Proposed outcome

- For any catalog entry, the detail view shows the same name, author,
  category and stars as that plugin's list line: an empty or non-string
  name shows the id, an empty or non-string author or category shows `?`,
  and stars is the same number.
- No field in the detail card ever prints a JSON object, an array or a
  number where text is expected. A bad field shows its safe default.
- The rule for "what a bad field becomes" is written once, in the shared
  catalog projection from #18, and not again in `show_detail`, as far as
  that is possible.
- One runnable check fails on today's code: an entry with `"name": ""` and
  `"author": {}` gives the id and `?` in the detail fields.

## Affected users and systems

- People using the terminal browser (`omarchy-plugin-browser`). The panel
  is not affected: it reads `catalog.sh list`, which already goes through
  `catalog_rows`.
- `bin/omarchy-plugin-browser`, `show_detail` (and maybe `entry_by_id`).
- `lib/catalog.sh`, `CATALOG_ROWS_JQ`, if the per-entry projection is made
  reusable there.
- `tests/catalog-list.sh` (it has the hostile fixture), or a new small test;
  CHANGELOG.

## Constraints

- **The catalog is untrusted remote data.** Every field may be missing or of
  any type. Nothing from it is evaluated or executed, and control
  characters never reach the terminal.
- **One projection.** #18 made `CATALOG_ROWS_JQ` the single projection for
  both the panel and the terminal. This fix reuses it, not a third copy of
  the coercion rules. Any change to it must leave `catalog.sh list` output
  byte-identical for every entry (the panel reads it), and
  `tests/catalog-list.sh` must still pass unchanged.
- **Keep #20 phase B's shape**: one jq call for the whole detail card,
  NUL-separated (`--raw-output0`), no return to one jq per field.
- **No behaviour change for good input**: a well-formed entry's detail card
  looks exactly as today.
- No new dependencies. The flake's `plugin` package and its checks still
  pass.

## Open questions

- **How far does "match the list" go?** The issue names `name`, `author`
  and `category`. The same `//` gap covers `repo`, `stars`, `version`,
  `description`, `installNote` and the verification fields.
  *Recommendation:* every field the detail card prints. The fix is the same
  per field, and leaving some raw keeps the "JSON in the card" problem.
- **Reuse `catalog_rows` as it is, or split out a one-entry def?**
  `catalog_rows` works on a whole catalog: it filters to community entries
  and sorts. The detail view needs one entry, plus fields `catalog_rows`
  does not carry (`version`, `installNote`, `verificationCoverage`, the two
  commits). *Recommendation:* the spec should look at splitting
  `catalog_rows` into a per-entry def (for example `catalog_row`) that
  `catalog_rows` maps over, with `show_detail` calling the same def and
  coercing its few extra fields with the existing `_s`. The exact shape is a
  spec decision.
- **How is it tested?** `show_detail` draws with `gum` and is not callable
  on its own today. *Recommendation:* test the jq that produces the fields,
  run on the hostile fixture in `tests/catalog-list.sh`, not the gum
  output. If the jq stays inline in `show_detail`, moving it into a named
  function or variable next to `catalog_lines` makes it testable.
