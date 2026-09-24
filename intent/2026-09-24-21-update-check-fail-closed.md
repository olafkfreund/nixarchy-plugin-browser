---
status: draft
issue: 21
author: olafkfreund
---

# Intent: The update-check opt-out fails closed

## Problem

A user who writes `"update_check": false` in
`~/.config/nixarchy-plugin-browser/config.json` has said: no network fetch.
`enabled()` in `lib/update.sh` does not always honour that:

```bash
enabled() {
  [[ -f $UPD_CONFIG ]] || return 0
  [[ $(jq -r '.update_check' "$UPD_CONFIG" 2>/dev/null) != false ]]
}
```

When the config exists but jq cannot read it, the command substitution is
empty, `"" != false` is true, and the check runs. That happens when:

- the file is malformed JSON (a half-saved edit, a trailing comma);
- the file is unreadable (permissions);
- jq is missing from the fixed `PATH`.

`[[ -f ]]` also lets a config path that exists but is not a regular file (a
directory, a FIFO) count as "no config", so the check runs then as well.

In every case the opt-out fails open: `cmd_check` fetches `manifest.json`
(and `CHANGELOG.md`) from GitHub, which the user asked not to happen.

The bar widget has its own guard (`BarWidget.qml:79`,
`setting("update_check", true)`), but that reads the widget's `shell.json`
entry, not this config file. Anyone who calls `update.sh check` directly,
or who opted out through the config file only, gets no protection from it.

#18 fixed the same shape for the preview switch: `previews_enabled` in
`lib/catalog.sh` uses `[[ -e ]]` and `v=$(jq …) || return 1`, so a config
that exists but cannot be read counts as off. `tests/preview.sh:52-56`
checks it. The update switch was left as it was.

## Proposed outcome

- A config file that exists but cannot be read as JSON turns the update
  check **off**, the same as `"update_check": false`. `check` then reports
  `enabled: false` and fetches nothing.
- No config file at all still means **on**, as today and as
  `docs/update-alerts.md` says.
- A readable config behaves exactly as today: `false` turns it off; any
  other value, or no key, leaves it on.
- The two switches in this plugin (`previews` and `update_check`) follow
  the same rule, written the same way.
- `tests/update.sh` has one case that fails on today's code: a malformed
  config makes `check` report `enabled: false` without a fetch.

## Affected users and systems

- Users who opted out of the update check through the config file.
- `lib/update.sh`, `enabled()` only. This is in the **shared** part of the
  file (outside the "this plugin" block), which every Omarchy.Fans plugin
  ships.
- `tests/update.sh`; CHANGELOG.
- `docs/update-alerts.md`, if the opt-out sentence or the "In this plugin"
  upstream line needs a word about the fail-closed rule.
- Other Omarchy.Fans plugins that carry the same `lib/update.sh`, and the
  reference copy (Omarchy Help).

## Constraints

- **Shared file, same interface.** The change stays inside `enabled()`. The
  subcommands, the `check` JSON fields, the cache file and its meaning stay
  the same, so another plugin can take the new `enabled()` as-is.
- **Consistent with #18.** The rule and the code shape match
  `previews_enabled` in `lib/catalog.sh`: `-e`, not `-f`; a jq failure
  means off.
- **No new dependencies**: bash and jq, on the existing fixed root-owned
  `PATH`.
- **No behaviour change for good input**: no config, or a readable config,
  gives the same answer as today.
- The test never touches the network (`tests/update.sh` already points
  `OMARCHY_PLUGIN_UPDATE_RAW` at `file://…/nowhere` and seeds the cache).
- The flake's `plugin` package and its checks still pass.

## Open questions

- **Fix here now and send it upstream with #18's changes, or wait for
  upstream?** #18 plan step 12 opens one upstream PR against Omarchy Help
  with the `fetch` and `ver_key` changes, after merge. Either this fix goes
  into that same PR, or this copy waits for upstream to fix `enabled()`
  first. *Recommendation:* fix here now and add it to the #18 step 12 PR.
  It is a four-line change inside the same function family. Waiting leaves a
  known privacy fail-open in a shipped plugin, and one upstream PR is less
  review load than two. If step 12's PR is already open by then, add a
  commit to it; if upstream declines, the "In this plugin" line in
  `docs/update-alerts.md` records the divergence, as step 12 already
  provides.
- **Should a fail-closed switch say why?** Silently off could puzzle a
  user whose config has a typo: the update dot never shows. `check` could
  write one line to stderr. *Recommendation:* no, not in this task. The
  panel does not show stderr, `previews_enabled` is silent too, and
  `enabled: false` is already in the JSON. Change both switches together
  later if it proves confusing.
