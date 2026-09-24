#!/usr/bin/env bash
# tier: host
#
# tests/audit-ids.sh — plugin ids and catalog commits are checked before use
# (#15 item 7), in the audit and in uninstall.sh.
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export PATH="/run/current-system/sw/bin:$PATH" HOME="$T/home" TMPDIR="$T/tmp"
export CATALOG="$T/catalog.json" OMARCHY_BIN="$T/bin" XDG_RUNTIME_DIR="$T/run"
mkdir -p "$HOME" "$TMPDIR" "$OMARCHY_BIN" "$XDG_RUNTIME_DIR"
echo '{"plugins":[]}' >"$CATALOG"
printf '#!/bin/sh\nexit 0\n' >"$OMARCHY_BIN/omarchy-plugin-validate"
chmod +x "$OMARCHY_BIN/omarchy-plugin-validate"

fail() { echo "FAIL: $*"; exit 1; }
AUDIT="$ROOT/bin/omarchy-plugin-audit"

# 1. A local manifest with a path-like or option-like id.
for id in ../../x -rf; do
  d="$T/id$RANDOM"; mkdir "$d"
  jq -n --arg id "$id" '{id:$id}' >"$d/manifest.json"
  "$AUDIT" "$d" --no-sandbox >/dev/null 2>"$T/err"; rc=$?
  [[ $rc == 2 ]] || fail "id $id: exit $rc, expected 2"
  grep -q 'invalid plugin id' "$T/err" || fail "id $id: no 'invalid plugin id': $(cat "$T/err")"
done

# 2. A catalog verification commit that is not a 40-hex sha.
mkdir "$T/r" && echo '{"id":"t.ids"}' >"$T/r/manifest.json"
git -C "$T/r" init -q && git -C "$T/r" add -A && git -C "$T/r" -c user.name=t -c user.email=t@t commit -qm init
jq -n --arg url "file://$T/r" '{plugins:[{id:"t.ids", repo:$url, verificationCommit:"HEAD~1"}]}' >"$CATALOG"
J=$("$AUDIT" "file://$T/r" --no-sandbox --json 2>"$T/err")
[[ $(jq -r .verifiedCommit <<<"$J" 2>/dev/null) == "" && -n $J ]] || fail "HEAD~1: verifiedCommit not \"\" ($(cat "$T/err"))"
grep -q 'verification commit is malformed' "$T/err" || fail "HEAD~1: no malformed note: $(cat "$T/err")"

# 3. uninstall.sh must not act on an invalid id.
mkdir -p "$T/u" "$HOME/.config/omarchy/plugins" "$HOME/.config/x" "$T/stub"
cp "$ROOT/uninstall.sh" "$T/u/"
echo '{"id":"../../x"}' >"$T/u/manifest.json"
printf '#!/bin/sh\necho "$@" >>"%s/omarchy.called"\n' "$T" >"$T/stub/omarchy"
chmod +x "$T/stub/omarchy"
PATH="$T/stub:$PATH" bash "$T/u/uninstall.sh" >/dev/null 2>&1
[[ ! -e $T/omarchy.called ]] || fail "uninstall.sh called: omarchy $(cat "$T/omarchy.called")"
echo ok
