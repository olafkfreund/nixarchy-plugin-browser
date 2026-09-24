#!/usr/bin/env bash
# tier: host
#
# tests/audit-symlink.sh — no real symlinks in staging, and every link is
# reported and blocks --install / --export-tree (#15 item 5).
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

# 1. A committed link, cloned from a typed file:// URL, is scanned as the file
#    git stores (its target text), not followed and not skipped.
mkdir "$T/a" && echo '{"id":"t.link"}' >"$T/a/manifest.json"
ln -s /usr/share/x "$T/a/link.qml"
git -C "$T/a" init -q && commit "$T/a" init
J=$("$AUDIT" "file://$T/a" --no-sandbox --json 2>"$T/err")
jq -e '.nixosCompatibility.findings | any(.id == "fhs-path" and .at == "link.qml:1")' >/dev/null <<<"$J" \
  || fail "committed link: no NIX fhs-path at link.qml:1 ($(cat "$T/err"))"

# 2. An untracked link in a git folder with an https origin, audited through a
#    symlink to the folder.
mkdir "$T/b" && echo '{"id":"t.untracked"}' >"$T/b/manifest.json"
git -C "$T/b" init -q && git -C "$T/b" remote add origin https://example.invalid/t/b && commit "$T/b" init
ln -s /etc/passwd "$T/b/evil.qml"
ln -s "$T/b" "$T/b-link"
J=$("$AUDIT" "$T/b-link" --no-sandbox --json 2>/dev/null)
jq -e '.symlinks | index("evil.qml")' >/dev/null <<<"$J" || fail "untracked link: not listed under symlinks"
OUT=$("$AUDIT" "$T/b-link" --no-sandbox --install 2>&1)
grep -q 'Refusing --install' <<<"$OUT" || fail "untracked link: --install not refused"$'\n'"$OUT"
[[ ! -e $HOME/.config/omarchy/plugins ]] || fail "untracked link: a plugin was installed"
"$AUDIT" "$T/b-link" --no-sandbox --export-tree "$T/x" >/dev/null 2>&1; rc=$?
[[ $rc == 20 ]] || fail "untracked link: --export-tree exit $rc, expected 20"

# 3. A plain folder (no git) with a link: listed in the text report.
mkdir "$T/c" && echo '{"id":"t.plain"}' >"$T/c/manifest.json"
ln -s /etc/passwd "$T/c/p.qml"
OUT=$("$AUDIT" "$T/c" --no-sandbox 2>&1)
grep -A3 '^Symlinks' <<<"$OUT" | grep -q 'p\.qml' || fail "plain folder: link not listed under Symlinks"$'\n'"$OUT"
echo ok
