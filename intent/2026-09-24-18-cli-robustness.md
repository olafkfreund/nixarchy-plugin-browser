---
status: approved
issue: 18
author: olafkfreund
---

# Intent: Make the CLIs survive bad input

## Problem

The 2026-09-24 review (items 9-11 and 13) found five places where the bash
tools fail on input they should handle: a malformed catalog, a missing
argument, or a version number with a large part. Each failure is out of
proportion to its cause. One bad field loses everything, or the tool hangs,
or it prints a wrong message.

1. **One malformed catalog entry empties the whole list.** The catalog is
   remote data that anyone publishing to the marketplace can influence.
   Both list builders assume field types:
   - `lib/catalog.sh:143,150` passes `stars` through and sorts with
     `sort_by(-.stars)`. One entry with `"stars": "5"` makes jq stop with
     `string ("5") cannot be negated`, exit 5. The panel
     (`BrowserState.qml:55-61`) sees a non-zero exit and shows
     "catalog failed", with no rows at all. That is 3969 plugins lost to one
     field.
   - `bin/omarchy-plugin-browser:64,71` (`list_lines`) negates `.stars` in
     the same way, and runs `.tags|join(" #")`. A string `tags` value
     (`"tags": "x"`) stops jq with `Cannot iterate over string`, exit 5, so
     the terminal browser shows an empty picker.
   - `catalog_usable` (`lib/catalog.sh:34-39`) checks only the file's owner
     and size, not its shape. A catalog that is valid JSON with one wrong
     type passes, is cached, and keeps failing until the cache expires.
   Both failures reproduce with `jq -n`: exit 5 each.

2. **`audit --json` can print text before the JSON.**
   `bin/omarchy-plugin-audit:152` runs
   `fetch_catalog || say "note: could not fetch the marketplace catalog…"`.
   `say` (`:59`) writes to stdout, in every mode. Offline, with no cached
   catalog, `--json` prints a coloured note line and then the report. The
   panel's `Model.parseReport` (`Model.js:132`) cannot parse it, so the
   panel shows "audit failed", with nothing on stderr to explain why.
   Scripts that pipe `--json` to `jq` break in the same way.

3. **`omarchy-plugin-browser --category` with no value hangs forever.**
   `bin/omarchy-plugin-browser:30` does `shift 2`. With one argument left,
   `shift 2` fails and shifts nothing, so `$#` stays 1 and the `while`
   loop repeats forever at full CPU. It never prints anything and never
   exits. `--category --refresh` also takes `--refresh` as the category
   name, without a warning.

4. **After an update, the tool says no restart is needed, but one is.**
   `lib/update.sh:37` sets `UPD_KEEP_LOADED=0`. The update terminal then
   says "The bar picks up the new files by itself" (`:210`) and does not
   offer a restart. But `BrowserState.qml` is a `pragma Singleton`, and
   `omarchy plugin update` keeps its old instance. The manual already says
   so: `docs/manual/troubleshooting.md:29-36`, "Something is 'not a
   function' after an update … Restart the shell once". The tool and the
   manual disagree, and the tool is wrong.

5. **`update.sh` fetches weakly and compares versions wrongly.**
   - `fetch` (`lib/update.sh:93-95`) has no `--proto '=https'`. The base URL
     can be overridden (`OMARCHY_PLUGIN_UPDATE_RAW`, `:48`), and nothing
     stops it being `http://` or `file://`. The catalog and preview fetches
     both restrict the protocol (`lib/catalog.sh:121`).
   - `ver_key` (`:56-60`) and the awk `key()` in `changelog_notes` (`:69`)
     pad each part to five digits. A part of six or more digits makes the
     key longer, so string comparison gives wrong answers:
     `1.100000.0` sorts below `1.99999.0`. The result is a missed or
     phantom "update available", or the wrong changelog lines.
     `$((10#…))` also overflows on very long digit runs.

## Proposed outcome

- **One bad entry costs one entry, not the list.** In both the panel and the
  terminal browser, an entry with a wrong-typed `stars`, `tags` or other
  field is either coerced to a safe default or skipped. Every other plugin
  still lists, in the same order as today.
- **`--json` output is JSON, always.** Notes and warnings go to stderr in
  JSON mode. stdout is exactly one JSON document that `jq` can parse. The
  text mode looks the same as today.
- **A missing option value is an error, not a hang.**
  `omarchy-plugin-browser --category` exits at once with a usage error
  (exit 2, the same code as an unknown option).
- **The update terminal matches the manual.** After updating this plugin it
  offers the shell restart the panel needs, as `docs/update-alerts.md`
  describes for keepLoaded panels.
- **The update check is HTTPS-only and orders versions correctly** for any
  numeric version, including parts of six or more digits.
- Each fix has one runnable check that fails without it.

## Affected users and systems

- Everyone who uses the panel (Super+Alt+U / the menu) or the terminal
  browser. A single bad upstream entry currently takes both down.
- Scripts and the panel that consume `omarchy-plugin-audit --json`.
- This repo:
  - `lib/catalog.sh`, for `list`;
  - `bin/omarchy-plugin-browser`, for argument parsing and `list_lines`;
  - `bin/omarchy-plugin-audit`, **line 152 only**; the rest of the file
    belongs to #15 (teammate audit-sec);
  - `lib/update.sh`;
  - tests, and CHANGELOG.
- Other Omarchy.Fans plugins that ship the same `lib/update.sh` (see
  Constraints).
- The flake's `plugin` package and its checks. The file set is the same,
  and the behaviour changes.

## Constraints

- **The catalog is untrusted remote data.** Any fix treats every field as
  possibly missing or of the wrong type. It must never evaluate or execute
  anything from the catalog. It must never let one entry decide whether
  the others are shown. The existing guards stay: the size ceiling, owner
  and symlink checks, and the plain-data rule.
- **`lib/update.sh` is a shared file.** The header (`:4-5`) and
  `docs/update-alerts.md` say that the same file ships in every
  Omarchy.Fans plugin, and only the "this plugin" block (`:30-45`)
  differs.
  - The `UPD_KEEP_LOADED` change is inside that block. It is local, and
    safe.
  - The `--proto` and `ver_key` changes are in the shared part. They must
    keep the same interface, so other copies can take them as-is: the
    same subcommands, the same `check` JSON fields, the same cache file.
    They must also be offered upstream (the reference copy, Omarchy Help),
    or recorded as a deliberate divergence.
  - A new `ver_key` must still order every version the old one ordered
    correctly. Existing cache files (`latest`, `dismissed`) must keep
    their meaning.
- **No new dependencies.** Only bash, jq, curl, awk and coreutils, all
  already in the closure. The same fixed root-owned `PATH`.
- **No behaviour change for good input.** A well-formed catalog lists
  exactly as before, and the text-mode audit output is byte-identical.
- **Coordination with #15.** This task touches only
  `bin/omarchy-plugin-audit:152`. Any wider change to how `say` works in
  JSON mode belongs to #15, or is agreed with it first.
- The flake's `plugin` package still passes nixarchy's checks.

## Open questions

- **Skip or coerce a bad entry?** Coercing (`stars` → number or 0, `tags`
  → array of strings or `[]`) keeps the plugin visible with safe values.
  Skipping hides a plugin that may be fine apart from one field. The
  proposal is to coerce the display fields and skip only entries with no
  usable string `id`. The panel already drops unsafe ids in
  `Model.parseRows`.
- **Should the two list builders share one jq projection?** `catalog.sh
  list` and `list_lines` each type-handle the same fields. Sharing one
  projection fixes the bug once, but changes more code. This is for the
  spec.
- **Upstream the `update.sh` fixes, or let this copy diverge?** The
  proposal is to fix it here with an unchanged interface and open an
  upstream PR, recording which approach was taken in
  `docs/update-alerts.md`.
- **Where should the audit note go in JSON mode?** The options are stderr,
  or a `notes` field inside the report. Stderr is the smaller change and
  leaves the report schema alone. A field would let the panel show the
  note. The proposal is stderr, given the #15 boundary.
