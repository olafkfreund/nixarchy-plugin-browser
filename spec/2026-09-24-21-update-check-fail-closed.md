---
status: draft
issue: 21
intent: intent/2026-09-24-21-update-check-fail-closed.md
---

# Spec: The update-check opt-out fails closed

Approved in the intent: fix `enabled()` here now, in the shape of #18's
`previews_enabled`; fold the change into the #18 plan step 12 upstream PR
against Omarchy Help; no stderr message.

## Design

`lib/update.sh`, `enabled()` only, rewritten to match `previews_enabled` in
`lib/catalog.sh:132-137` line for line:

```bash
enabled() {
  [[ -e $UPD_CONFIG ]] || return 0
  local v
  v=$(jq -r '.update_check' "$UPD_CONFIG" 2>/dev/null) || return 1
  [[ $v != false ]]
}
```

- `-e`, not `-f`: a directory, FIFO or other non-regular path at the config
  location counts as a config, and jq then fails on it, so the check is off.
- `local v` on its own line, so `v=$(…) || return 1` sees jq's exit status
  (a `local v=$(…)` would mask it with `local`'s 0).
- jq fails, so `enabled` returns 1, for: malformed JSON, an unreadable file,
  a non-regular path, and jq missing from the fixed `PATH` (exit 127).
- Readable JSON is unchanged: `false` turns the check off; any other value,
  `null`, or no key leaves it on. No config file still means on.

`cmd_check` already turns `enabled` returning 1 into `enabled: false`, skips
the whole fetch branch, and leaves the cache alone. The subcommands, the
`check` JSON fields and the cache file do not change, so another plugin can
take the function as-is.

No stderr message (approved): `previews_enabled` is silent too, and the JSON
already says `enabled: false`.

Other files:

- `tests/update.sh`: one new case, below.
- `CHANGELOG.md`, `Unreleased`: one line, "A config file that exists but
  cannot be read turns the update check off, as `"update_check": false`
  does (#21)."
- `docs/update-alerts.md`: the **Opt-out** sentence (line 60) gains "A config
  file that exists but cannot be read also turns it off." That is the shared
  part of the doc, so it travels upstream with the code.
- Upstream: this `enabled()` and the doc sentence go into the #18 step 12 PR
  against Omarchy Help. If that PR is already open when #21 merges, add a
  commit to it; if it has not been opened yet, it carries both. The "In this
  plugin" line that step 12 adds names #21 too. If upstream declines, that
  line records the divergence, as step 12 already provides.

## Alternatives rejected

- **Keep `-f` and only add `|| return 1`.** Leaves a directory or FIFO at the
  config path counting as "no config", so still on. The intent asks for the
  same rule as #18, which uses `-e`.
- **`jq -e '.update_check != false'`.** Folds the parse error and the value
  into one exit status, but `jq -e` maps `null`/`false` output and errors to
  different codes (1 vs 5), so reading it right needs a `case`; longer and
  different from `previews_enabled`.
- **A stderr line when the config cannot be read.** Declined at the intent;
  the panel does not show stderr, and both switches would need it together.
- **Wait for upstream to fix `enabled()` first.** Declined at the intent: it
  leaves a known privacy fail-open shipped.

## Risks

- **A user with a broken config silently loses update alerts.** Accepted at
  the intent; `check` reports `enabled: false`, which is visible to anyone who
  runs it.
- **Divergence from the other Omarchy.Fans copies** until upstream takes it.
  Bounded by the step 12 PR and the "In this plugin" line.
- **Any host:** none beyond the plugin; no Nix, service or network change. The
  flake's `plugin` package copies `lib/update.sh`; its checks run
  `tests/update.sh`.

## Verification

Red first: add the case to `tests/update.sh`, run it on today's `enabled()`,
see it fail; then change `enabled()` and see `ok`.

The case goes in part 1, right after the existing `"update_check": false`
case and before `rm -f -- "$CONFIG" "$CACHE"`:

```bash
# The switch fails closed (#21): a config jq cannot read means off, not on.
echo '{' >"$CONFIG"
jq -n '{checked: 0, latest: "0.2.0"}' >"$CACHE"; before=$(sha256sum <"$CACHE")
out=$(bash "$T/plugin/lib/update.sh" check 0.1.0)
jq -e '.enabled == false and .latest == null' >/dev/null <<<"$out" \
  || fail "malformed config: check is not off: $out"
[[ $(sha256sum <"$CACHE") == "$before" ]] || fail "malformed config: the cache file changed"
```

Why this proves "no fetch": the cache is stale (`checked: 0`), so on today's
code the check is on and goes down the fetch branch; `OMARCHY_PLUGIN_UPDATE_RAW`
is `file://…/nowhere`, which `fetch` refuses, so it then falls back to the
cached `latest: "0.2.0"` and the case fails on `.latest == null`. Off, the
fetch branch is never entered, `latest` is null and the cache is untouched.
The network is never reached either way.

Then, from the repo root, each prints `ok`:

```bash
bash tests/update.sh
bash tests/preview.sh                 # the twin switch still fails closed
bash -n lib/update.sh tests/update.sh
command -v shellcheck && shellcheck lib/update.sh tests/update.sh
nix flake check                       # passes
```

A dry run of this case against a scratch copy of `lib/update.sh` (done while
writing this spec) gave `{"enabled":true,"latest":"0.2.0"}` on today's code
and `{"enabled":false,"latest":null}` with the new `enabled()`, the cache
unchanged in both.

`git diff` on `lib/update.sh` touches only `enabled()`.
