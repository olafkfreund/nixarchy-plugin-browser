#!/usr/bin/env bash
# tier: host
#
# tests/audit-local-install.sh — a local --install installs exactly what was
# scanned: a working tree that differs from HEAD is refused (#15 item 3).
# --install may reach `omarchy plugin add`: HOME and XDG_RUNTIME_DIR are temp
# dirs, so it can only write under the temp HOME and cannot reach a live shell.
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export PATH="/run/current-system/sw/bin:$PATH" HOME="$T/home" TMPDIR="$T/tmp"
export CATALOG="$T/catalog.json" OMARCHY_BIN="$T/bin" XDG_RUNTIME_DIR="$T/run"
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
mkdir -p "$HOME" "$TMPDIR" "$OMARCHY_BIN" "$XDG_RUNTIME_DIR"
echo '{"plugins":[]}' >"$CATALOG"
printf '#!/bin/sh\nexit 0\n' >"$OMARCHY_BIN/omarchy-plugin-validate"
chmod +x "$OMARCHY_BIN/omarchy-plugin-validate"

fail() { echo "FAIL: $*"; exit 1; }
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }
AUDIT="$ROOT/bin/omarchy-plugin-audit"
PLUGINS="$HOME/.config/omarchy/plugins"

mkrepo() {  # mkrepo <dir>: a committed plugin with an https origin
  mkdir "$1" && echo '{"id":"t.local"}' >"$1/manifest.json"
  printf 'import QtQuick\nItem {}\n' >"$1/Widget.qml"
  git -C "$1" init -q && git -C "$1" remote add origin https://example.invalid/t/local && commit "$1" init
}

# 1. An uncommitted edit: what would be installed (HEAD) is not what was scanned.
mkrepo "$T/a"
printf 'import QtQuick\nItem { Component.onCompleted: console.log(1) }\n' >"$T/a/Widget.qml"
OUT=$("$AUDIT" "$T/a" --no-sandbox --install 2>&1); rc=$?
[[ $rc == 2 ]] || fail "uncommitted edit: exit $rc, expected 2"$'\n'"$OUT"
grep -q 'differs from HEAD' <<<"$OUT" || fail "uncommitted edit: no 'differs from HEAD'"$'\n'"$OUT"
[[ ! -e $PLUGINS ]] || fail "uncommitted edit: a plugin was installed"

# 2. A file dropped from git (rm --cached, committed) but still on disk.
mkrepo "$T/b"
git -C "$T/b" rm -q --cached Widget.qml && git -C "$T/b" -c user.name=t -c user.email=t@t commit -qm drop
OUT=$("$AUDIT" "$T/b" --no-sandbox --install 2>&1); rc=$?
[[ $rc == 2 ]] || fail "rm --cached: exit $rc, expected 2"$'\n'"$OUT"
[[ ! -e $PLUGINS ]] || fail "rm --cached: a plugin was installed"

# 3. A clean tree gets past the check.
mkrepo "$T/c"
OUT=$("$AUDIT" "$T/c" --no-sandbox --install 2>&1); rc=$?
grep -q 'differs from HEAD' <<<"$OUT" && fail "clean tree: refused as dirty"$'\n'"$OUT"
grep -qE 'omarchy CLI not found|Installing the audited checkout' <<<"$OUT" \
  || fail "clean tree: did not reach the install (exit $rc)"$'\n'"$OUT"
echo ok
