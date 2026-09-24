#!/usr/bin/env bash
#
# tests/run.sh [hermetic|host|all] — runs every tests/*.sh and tests/*.mjs
# whose tier line (`# tier: …` or `// tier: …`) matches. Prints PASS or FAIL
# per test, with a failing test's output, and exits 1 if any failed. A test
# with no tier line fails the run.
set -uo pipefail
want=${1:-all}; dir=$(cd -- "$(dirname -- "$0")" && pwd); rc=0
for t in "$dir"/*.sh "$dir"/*.mjs; do
  n=$(basename "$t"); [ "$n" = run.sh ] && continue
  tier=$(grep -m1 -oE '^(#|//) tier: (hermetic|host)' "$t" | sed 's/.* //')
  [ -n "$tier" ] || { echo "FAIL $n (no tier line)"; rc=1; continue; }
  [ "$want" = all ] || [ "$want" = "$tier" ] || continue
  case $n in *.mjs) run=node ;; *) run=bash ;; esac
  if out=$("$run" "$t" 2>&1); then echo "PASS $n"; else echo "FAIL $n"; echo "$out"; rc=1; fi
done
exit $rc
