#!/usr/bin/env bash
# tier: host
#
# tests/audit-ctl.sh — no control characters reach the terminal from a plugin
# or the catalog (#15 item 2): commit subject, file names, catalog fields.
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export PATH="/run/current-system/sw/bin:$PATH" HOME="$T/home" TMPDIR="$T/tmp"
export CATALOG="$T/catalog.json" OMARCHY_BIN="$T/bin"
mkdir -p "$HOME" "$TMPDIR" "$OMARCHY_BIN" "$T/fx"
printf '#!/bin/sh\nexit 0\n' >"$OMARCHY_BIN/omarchy-plugin-validate"
chmod +x "$OMARCHY_BIN/omarchy-plugin-validate"
ESC=$'\e'
URL=https://example.invalid/t/ctl
jq -n --arg e "$ESC" --arg url "$URL" '{plugins:[{id:"t.ctl", name:("Evil" + $e + "]0;pwned\u0007"),
  repo:$url, verificationSnapshotStatus:("x" + $e + "[2J"), stars:1}]}' >"$CATALOG"

cd "$T/fx"
echo '{"id":"t.ctl"}' >manifest.json
printf 'sudo true\n' >"a${ESC}[31mb.sh"
git init -q . && git remote add origin "$URL"
git add -A && git -c user.name=t -c user.email=t@t commit -qm "hi${ESC}]52;c;aGk=$(printf '\a')"
cd "$ROOT"

fail() { echo "FAIL: $*"; exit 1; }
ctl() { LC_ALL=C grep -qP '[\x00-\x08\x0b-\x1f\x7f]'; }

AUDIT="$ROOT/bin/omarchy-plugin-audit"
TXT=$("$AUDIT" "$T/fx" --no-sandbox 2>&1)
ctl <<<"$TXT" && fail "text output has a control character:"$'\n'"$(cat -v <<<"$TXT")"
J=$("$AUDIT" "$T/fx" --no-sandbox --json 2>/dev/null)
jq -e . >/dev/null <<<"$J" || fail "--json is not JSON"
jq -r '..|strings' <<<"$J" | ctl && fail "--json string has a control character"
echo ok
