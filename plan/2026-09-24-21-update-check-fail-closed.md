---
status: approved
issue: 21
spec: spec/2026-09-24-21-update-check-fail-closed.md
---

# Plan: The update-check opt-out fails closed

This plan is self-contained; it carries every approved decision (intent
`7f3db79`, spec `e019c12`). Line numbers are on `master` at `d0e4dfc`.

**Decisions**

- **Fail closed, now, in this plugin.** A config file that exists but that jq
  cannot read (malformed JSON, unreadable, not a regular file, jq missing from
  the fixed `PATH`) turns the update check **off**, as `"update_check": false`
  does. No config file still means **on**. A readable config is unchanged:
  `false` is off; any other value, `null` or no key is on.
- **Same rule and shape as #18's `previews_enabled`** (`lib/catalog.sh`):
  `[[ -e ]]`, not `-f`; `local v` on its own line so `v=$(jq …) || return 1`
  sees jq's exit status.
- **Only `enabled()` in `lib/update.sh` changes.** Subcommands, the `check`
  JSON fields, the cache path and contents stay the same, so another
  Omarchy.Fans plugin can take the function as-is.
- **No stderr message.** `previews_enabled` is silent too; `check` already
  reports `enabled: false`.
- **Upstream:** the new `enabled()` and the doc sentence go into the #18
  plan step 12 PR against Omarchy Help. If that PR is already open when #21
  merges, add a commit to it; if not, it carries both. The "In this plugin"
  line that step 12 adds names #21 too; if upstream declines, that line
  records the divergence.
- **Accepted risk:** a user with a broken config silently loses update alerts
  (visible as `enabled: false` from `check`).

## Steps

1. `tests/update.sh`: in part 1, directly after the existing
   `"update_check": false` case (the block ending
   `|| fail "off: the cache file changed"`, line 51) and before the
   `# Part 2 needs the check switched on…` comment, add:

   ```bash
   # The switch fails closed (#21): a config jq cannot read means off, not on.
   echo '{' >"$CONFIG"
   jq -n '{checked: 0, latest: "0.2.0"}' >"$CACHE"; before=$(sha256sum <"$CACHE")
   out=$(bash "$T/plugin/lib/update.sh" check 0.1.0)
   jq -e '.enabled == false and .latest == null' >/dev/null <<<"$out" \
     || fail "malformed config: check is not off: $out"
   [[ $(sha256sum <"$CACHE") == "$before" ]] || fail "malformed config: the cache file changed"
   ```

   → verify **red** by `bash tests/update.sh` failing with
   `malformed config: check is not off: {"enabled":true,…"latest":"0.2.0"…}`
   (today's code goes down the fetch branch, `fetch` refuses the
   `file://…/nowhere` raw URL, and `check` falls back to the cached
   `latest`). Commit the red test on its own only if the branch is
   squash-merged; otherwise keep it with step 2.

2. `lib/update.sh`: replace `enabled()` (lines 106-109) with

   ```bash
   enabled() {
     [[ -e $UPD_CONFIG ]] || return 0
     local v
     v=$(jq -r '.update_check' "$UPD_CONFIG" 2>/dev/null) || return 1
     [[ $v != false ]]
   }
   ```

   → verify by `bash tests/update.sh` printing `ok`, and
   `git diff master -- lib/update.sh` touching only `enabled()`.

3. `docs/update-alerts.md`: the **Opt-out** paragraph (line 60) gains the
   sentence "A config file that exists but cannot be read also turns it off."
   after "turns the check off." → verify by
   `grep -n 'cannot be read also turns it off' docs/update-alerts.md`.

4. `CHANGELOG.md`: if there is no `## Unreleased` section at the top, add one
   above `## 0.5.1` (the release renames it; `changelog_notes` skips a
   non-version heading). Add the bullet
   `- A config file that exists but cannot be read turns the update check off, as "update_check": false does (#21)`
   → verify by `grep -n '^## ' CHANGELOG.md | head -2` showing `Unreleased`
   then `0.5.1`, and the bullet under it.

5. Run the full test list below → verify every command prints `ok` / passes.

6. After merge (outside this repo): fold `enabled()` and the step 3 sentence
   into the #18 step 12 PR against Omarchy Help (add a commit if it is open;
   include them if it is not yet opened). The "In this plugin" line in
   `docs/update-alerts.md` that step 12 adds names #21 as well. → verify by
   the PR link in that line.

## Tests

From the repo root:

```bash
bash tests/update.sh                  # ok (red before step 2, see step 1)
bash tests/preview.sh                 # ok: the twin switch still fails closed
bash -n lib/update.sh tests/update.sh # no output, exit 0
command -v shellcheck && shellcheck lib/update.sh tests/update.sh   # no findings
nix flake check                       # passes (the plugin checks run tests/update.sh)
git diff master --stat                # lib/update.sh, tests/update.sh,
                                      # docs/update-alerts.md, CHANGELOG.md only
```

Spot checks by hand (scratch dir, never the real config):

```bash
d=$(mktemp -d); export XDG_CONFIG_HOME=$d/cfg XDG_CACHE_HOME=$d/cache
export OMARCHY_PLUGIN_UPDATE_RAW=file:///nowhere   # fetch refuses it: no network
mkdir -p "$d/cfg/nixarchy-plugin-browser"
# no config -> on
bash lib/update.sh check 0.1.0 | jq .enabled          # true
# directory at the config path -> off
mkdir "$d/cfg/nixarchy-plugin-browser/config.json"
bash lib/update.sh check 0.1.0 | jq .enabled          # false
rm -r "$d"
```

## Rollback

`git revert` the implementation commit(s): `enabled()` returns to `-f` and
the fail-open read; the test case, the doc sentence and the changelog line go
with it. No cache, config or Nix state changes, so nothing else to undo. If
the upstream PR already carries the change, drop that commit from it or leave
the "In this plugin" line saying this copy diverges.
