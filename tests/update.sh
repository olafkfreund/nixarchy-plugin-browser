#!/usr/bin/env bash
#
# tests/update.sh — self-check for `lib/update.sh check` and `dismiss`, without
# the network: the cache is seeded as checked just now, so fetch is never
# reached. Runs a copy of update.sh inside a fixture plugin, so the version
# next to it is the fixture's, not this repository's.
# Prints "ok" and exits 0, or names the first failure and exits 1.
# tier: host
set -uo pipefail

LIB="$(cd -- "$(dirname -- "$0")/.." && pwd)/lib/update.sh"
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

export XDG_CACHE_HOME="$T/cache" XDG_CONFIG_HOME="$T/config"
export OMARCHY_PLUGIN_UPDATE_RAW="file://$T/nowhere"   # belt and braces: never the network
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

echo ok
