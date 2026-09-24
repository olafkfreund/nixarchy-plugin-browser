#!/usr/bin/env bash
# tier: hermetic
#
# tests/no-text-multiplier.sh [dir] — every text size in a QML file is a bare
# Style.font.* token (#26): no factor, no uiScale/textScale/px() helper.
# Prints "ok" and exits 0, or the offending lines and exits 1.
set -uo pipefail
ROOT=${1:-"$(cd -- "$(dirname -- "$0")/.." && pwd)"}
# Hidden dirs below ROOT (.git, .claude/worktrees) are skipped; ROOT itself
# may sit under one.
mapfile -d '' qml < <(find "$ROOT" -mindepth 1 -name '.*' -prune -o -name '*.qml' -print0)
[ ${#qml[@]} -gt 0 ] || { echo "no qml under $ROOT"; exit 1; }
# Each pixelSize:/fontSize: binding, cut at ; or } so BarWidget.qml:148's
# "...: Style.font.body; font.bold: true" is judged on its first binding.
bad=$(grep -noHE '(pixelSize|fontSize):[^;}]*' "${qml[@]}" |
  grep -vE ':(pixelSize|fontSize):[[:space:]]*Style\.font\.[A-Za-z]+[[:space:]]*$')
words=$(grep -nHE '\b(textScale|uiScale)\b|\bpx\(' "${qml[@]}")
[ -z "$bad$words" ] || { printf '%s\n' "$bad" "$words" | sed '/^$/d'; exit 1; }
echo ok
