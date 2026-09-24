#!/usr/bin/env bash
# tier: host
#
# tests/audit-url.sh — only allowed URL kinds are cloned, and junk catalog rows
# do not break lookups (#15 item 4). No network: every refusal comes before a
# clone, and the one ssh URL points at a closed local port.
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export PATH="/run/current-system/sw/bin:$PATH" HOME="$T/home" TMPDIR="$T/tmp"
export CATALOG="$T/catalog.json" OMARCHY_BIN="$T/bin"
mkdir -p "$HOME" "$TMPDIR" "$OMARCHY_BIN" "$T/fx"
printf '#!/bin/sh\nexit 0\n' >"$OMARCHY_BIN/omarchy-plugin-validate"
chmod +x "$OMARCHY_BIN/omarchy-plugin-validate"

FX="$T/fx"
echo '{"id":"t.url"}' >"$FX/manifest.json"
git -C "$FX" init -q && git -C "$FX" add -A \
  && git -C "$FX" -c user.name=t -c user.email=t@t commit -qm init

jq -n --arg fx "$FX" '{plugins:[42, "x", null, {id:5, repo:7},
  {id:"t.file", repo:("file://" + $fx)}, {id:"t.abs", repo:$fx},
  {id:"t.ssh", repo:"ssh://x/y"}, {id:"t.cred", repo:"https://u@h/x"}]}' >"$CATALOG"

fail() { echo "FAIL: $*"; exit 1; }
AUDIT="$ROOT/bin/omarchy-plugin-audit"

for id in t.file t.abs t.ssh t.cred; do
  out=$("$AUDIT" "$id" --no-sandbox 2>"$T/err"); rc=$?
  [[ $rc == 2 ]] || fail "catalog $id: exit $rc, expected 2 ($(cat "$T/err"))"
  grep -q 'refusing this URL' "$T/err" || fail "catalog $id: no refusal: $(cat "$T/err")"
  [[ -z $out ]] || fail "catalog $id: a report was printed"
done
for u in http://h/x -uevil; do
  "$AUDIT" "$u" --no-sandbox >/dev/null 2>&1; rc=$?
  [[ $rc == 2 ]] || fail "typed $u: exit $rc, expected 2"
done
"$AUDIT" ssh://127.0.0.1:1/x --no-sandbox >/dev/null 2>&1; rc=$?
[[ $rc == 3 ]] || fail "typed ssh://127.0.0.1:1/x: exit $rc, expected 3 (allowed, then the clone fails)"
"$AUDIT" "file://$FX" --no-sandbox >/dev/null 2>"$T/err"; rc=$?
[[ $rc == 0 || $rc == 10 ]] || fail "typed file://: exit $rc, expected 0 or 10 ($(cat "$T/err"))"
echo ok
