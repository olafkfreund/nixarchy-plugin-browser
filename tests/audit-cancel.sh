#!/usr/bin/env bash
# tier: host
#
# tests/audit-cancel.sh — a TERM to the audit stops the staging clone too
# (#15 item 9, for #17's Cancel). The fixture repo's objects/info/alternates is
# a FIFO, so git-upload-pack blocks on it and the clone hangs until killed.
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T=$(mktemp -d)
FX="$T/fx-cancel-$$"
cleanup() { pkill -KILL -f "$FX" 2>/dev/null; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
export PATH="/run/current-system/sw/bin:$PATH" HOME="$T/home" TMPDIR="$T/tmp"
export CATALOG="$T/catalog.json" OMARCHY_BIN="$T/bin"
mkdir -p "$HOME" "$TMPDIR" "$OMARCHY_BIN"
echo '{"plugins":[]}' >"$CATALOG"

fail() { echo "FAIL: $*"; exit 1; }
mkdir "$FX" && echo '{"id":"t.cancel"}' >"$FX/manifest.json"
git -C "$FX" init -q && git -C "$FX" add -A && git -C "$FX" -c user.name=t -c user.email=t@t commit -qm init
mkfifo "$FX/.git/objects/info/alternates"

"$ROOT/bin/omarchy-plugin-audit" "file://$FX" --no-sandbox --json >/dev/null 2>&1 &
apid=$!
for _ in $(seq 100); do pgrep -f "clone.*$FX" >/dev/null && break; sleep 0.1; done
pgrep -f "clone.*$FX" >/dev/null || fail "the clone never started"

kill -TERM "$apid"
start=$SECONDS
for _ in $(seq 50); do kill -0 "$apid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$apid" 2>/dev/null && fail "the audit is still running 5 s after TERM"
wait "$apid"; rc=$?
[[ $rc == 143 ]] || fail "exit $rc after TERM, expected 143"
sleep 1
left=$(pgrep -af "$FX") && fail "processes left after the audit exited ($((SECONDS - start)) s):"$'\n'"$left"
compgen -G "$TMPDIR/omarchy-audit.*" >/dev/null && fail "staging dir left in \$TMPDIR"
echo ok
