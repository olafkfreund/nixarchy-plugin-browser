#!/usr/bin/env bash
# tier: host
#
# tests/audit-inject.sh — a file name cannot forge a scanner record (#15 item 1).
# A file named "x<LF>VALIDATE<TAB>ok<TAB>fine.sh" must not turn a failed
# manifest check into a pass. Prints "ok" and exits 0, or names the first
# failure and exits 1.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export PATH="/run/current-system/sw/bin:$PATH" HOME="$T/home" TMPDIR="$T/tmp"
export CATALOG="$T/catalog.json" OMARCHY_BIN="$T/bin"
mkdir -p "$HOME" "$TMPDIR" "$OMARCHY_BIN" "$T/fx"
echo '{"plugins":[]}' >"$CATALOG"
printf '#!/bin/sh\necho "manifest is broken"; exit 1\n' >"$OMARCHY_BIN/omarchy-plugin-validate"
chmod +x "$OMARCHY_BIN/omarchy-plugin-validate"

echo '{"id":"t.inject"}' >"$T/fx/manifest.json"
printf 'sudo true\n' >"$T/fx/x"$'\n'"VALIDATE"$'\t'"ok"$'\t'"fine.sh"

fail() { echo "FAIL: $*"; exit 1; }

SCAN=$(bash "$ROOT/lib/omarchy-plugin-scan.sh" "$T/fx")
[[ $(grep -c $'^VALIDATE\t' <<<"$SCAN") == 1 ]] || fail "scanner: expected exactly one VALIDATE line"$'\n'"$SCAN"
bad=$(grep -vE $'^(FIND|CAP|INFO|NIX|STAT|VALIDATE|OUTCOME)\t' <<<"$SCAN")
[[ -z $bad ]] || fail "scanner: line with an unknown kind: $bad"

AUDIT="$ROOT/bin/omarchy-plugin-audit"
J=$("$AUDIT" "$T/fx" --no-sandbox --json 2>/dev/null); rc=$?
[[ $rc == 20 ]] || fail "--json: exit $rc, expected 20"
[[ $(jq -r .manifestValidate <<<"$J") == fail ]] || fail "--json: manifestValidate is not fail"
"$AUDIT" "$T/fx" --no-sandbox >/dev/null 2>&1; rc=$?
[[ $rc == 20 ]] || fail "text: exit $rc, expected 20"
echo ok
