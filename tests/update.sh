#!/usr/bin/env bash
#
# tests/update.sh — self-check for lib/update.sh, without the network.
# Part 1 (#19): `check` and `dismiss`, the cache seeded as checked just now so
# fetch is never reached; runs a copy of update.sh inside a fixture plugin, so
# the version next to it is the fixture's, not this repository's.
# Part 2 (#18): version ordering in bash and in awk, the HTTPS-only fetch, and
# the keepLoaded setting; HOME and the XDG dirs point into the temp dir.
# Prints "ok" and exits 0, or names the first failure and exits 1.
# tier: host
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
LIB="$ROOT/lib/update.sh"
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

export HOME="$T/home" XDG_CACHE_HOME="$T/cache" XDG_CONFIG_HOME="$T/config"
export OMARCHY_PLUGIN_UPDATE_RAW="file://$T/nowhere"   # belt and braces: never the network
mkdir -p "$HOME"

# === part 1: check and dismiss (#19) ===========================================
CACHE="$T/cache/nixarchy-plugin-browser/update-check.json"
CONFIG="$T/config/nixarchy-plugin-browser/config.json"
mkdir -p "$T/plugin/lib" "$(dirname "$CACHE")" "$(dirname "$CONFIG")"
cp "$LIB" "$T/plugin/lib/update.sh"
echo '{"version":"0.1.0"}' >"$T/plugin/manifest.json"

seed() {  # seed INSTALLED LATEST: a cache fresh enough that check never fetches
  jq -n --arg latest "$2" --arg key "$1>$2" --argjson now "$(date +%s)" \
    '{checked: $now, latest: $latest, notes: [], notes_for: $key}' >"$CACHE"
}
available() {  # available INSTALLED LATEST -> prints update_available
  seed "$1" "$2"
  bash "$T/plugin/lib/update.sh" check "$1" | jq -r .update_available
}

[[ $(available 0.1.0 0.2.0) == true ]]   || fail "check: 0.2.0 over 0.1.0 is not available"
[[ $(available 0.1.0 0.1.0) == false ]]  || fail "check: an equal version is available"
[[ $(available 0.2.0 0.1.0) == false ]]  || fail "check: an older version is available"
[[ $(available 0.9.0 0.10.0) == true ]]  || fail "ver_gt: 0.10.0 does not order above 0.9.0"
[[ $(available 0.10.0 0.9.0) == false ]] || fail "ver_gt: 0.9.0 orders above 0.10.0"

bash "$T/plugin/lib/update.sh" dismiss 1.2.3 || fail "dismiss: exit $?"
[[ $(jq -r .dismissed "$CACHE") == 1.2.3 ]] || fail "dismiss: dismissed is not 1.2.3"

echo '{"update_check": false}' >"$CONFIG"
seed 0.1.0 0.2.0; before=$(sha256sum <"$CACHE")
out=$(bash "$T/plugin/lib/update.sh" check 0.1.0)
[[ $(jq -r .enabled <<<"$out") == false ]] || fail "off: enabled is not false: $out"
[[ $(sha256sum <"$CACHE") == "$before" ]] || fail "off: the cache file changed"

# Part 2 needs the check switched on and a cold cache.
rm -f -- "$CONFIG" "$CACHE"

# === part 2: version keys, HTTPS-only fetch, keepLoaded (#18) ==================
mkdir -p "$T/lib"
cp "$LIB" "$T/lib/update.sh"
echo '{"version": "0.5.0"}' >"$T/manifest.json"

# Sourcing runs main with no arguments: it prints usage and returns 2.
# shellcheck source=../lib/update.sh
source "$T/lib/update.sh" >/dev/null 2>&1

# --- ordering ------------------------------------------------------------------
gt() { ver_gt "$1" "$2" || fail "expected $1 > $2"; ver_gt "$2" "$1" && fail "expected not $2 > $1"; }
gt 1.100000.0 1.99999.0
gt 0.3.10 0.3.9
gt 1.0.0 0.99.99
gt 00010.0.0 9.0.0
nines=$(printf '9%.0s' {1..30})             # a 30-digit part: past any integer width
gt "$nines.0.0" 99.0.0
gt "1.$nines.0" 1.99.0
[[ $(ver_key 0.5.0) == "$(ver_key 0.5.0)" ]] || fail "ver_key 0.5.0 is not stable"
[[ $(ver_key 1.2) == "$(ver_key 1.2.0)" ]]   || fail "ver_key 1.2 != ver_key 1.2.0"
[[ $(ver_key 0.3.10) == 000130210 ]]         || fail "ver_key 0.3.10 is $(ver_key 0.3.10)"

# --- changelog_notes: the bounds come from bash, the headings from awk --------
printf '## 1.100000.0\n- new\n\n## 1.99999.0\n- old\n' >"$T/CHANGELOG.md"
notes=$(changelog_notes "$T/CHANGELOG.md" 1.99999.0 1.100000.0)
[[ $notes == new ]] || fail "changelog_notes gave '$notes', expected 'new'"

# --- the fetch is HTTPS-only: a file:// base is refused ----------------------
mkdir -p "$T/fx"
echo '{"version": "9.9.9"}' >"$T/fx/manifest.json"
out=$(OMARCHY_PLUGIN_UPDATE_RAW="file://$T/fx" bash "$T/lib/update.sh" check --force)
jq -e '.latest == null and .update_available == false' >/dev/null <<<"$out" \
  || fail "file:// fetch was not refused: $out"

# --- this plugin has a keepLoaded panel ----------------------------------------
grep -qx 'UPD_KEEP_LOADED=1.*' "$ROOT/lib/update.sh" || fail "UPD_KEEP_LOADED is not 1"
echo ok
