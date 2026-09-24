#!/usr/bin/env bash
#
# tests/preview.sh — self-check for catalog.sh's preview checks, without the
# network: the path allowlist, the file check (size and magic bytes), and the
# off switch. Prints "ok" and exits 0, or names the first failure and exits 1.
# tier: host
set -uo pipefail

LIB="$(cd -- "$(dirname -- "$0")/.." && pwd)/lib/catalog.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export XDG_CACHE_HOME="$T/cache" XDG_CONFIG_HOME="$T/config"
# shellcheck source=../lib/catalog.sh
source "$LIB"

fail() { echo "FAIL: $*"; exit 1; }

# --- paths: only the marketplace's own image folder ---------------------------
preview_path_ok "assets/img/plugins/5-crmne-omarchy-hyprmoncfg-card.webp" || fail "real path refused"
preview_path_ok "assets/img/plugins/x.png" || fail "png path refused"
for bad in "../x.webp" "https://evil/x.webp" "assets/img/plugins/x.webp?y" \
           "assets/img/other/x.webp" "assets/img/plugins/x.svg" \
           "assets/img/plugins/../../x.webp" "assets/img/plugins/.x.webp" ""; do
  preview_path_ok "$bad" && fail "bad path accepted: '$bad'"
done

# --- files: magic bytes must match the extension ------------------------------
printf 'RIFF\x10\x00\x00\x00WEBPVP8 ' >"$T/ok.webp"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR' >"$T/ok.png"
printf 'hello, not an image' >"$T/text.webp"
printf 'RIFF\x10\x00\x00\x00WAVEfmt ' >"$T/wave.webp"   # RIFF, but audio, not WebP
: >"$T/empty.webp"
{ printf 'RIFF\x10\x00\x00\x00WEBP'; head -c $((PREVIEW_MAX_BYTES + 1)) /dev/zero; } >"$T/big.webp"

preview_file_ok "$T/ok.webp" webp || fail "valid webp refused"
preview_file_ok "$T/ok.png" png   || fail "valid png refused"
preview_file_ok "$T/text.webp" webp && fail "text named .webp accepted"
preview_file_ok "$T/wave.webp" webp && fail "RIFF WAVE named .webp accepted"
preview_file_ok "$T/empty.webp" webp && fail "empty file accepted"
preview_file_ok "$T/big.webp" webp && fail "file over the ceiling accepted"
preview_file_ok "$T/ok.png" webp && fail "png accepted as webp"
ln -s "$T/ok.webp" "$T/link.webp"
preview_file_ok "$T/link.webp" webp && fail "symlink accepted"

# --- off switch: refuses before any path, cache or network work ---------------
mkdir -p "$XDG_CONFIG_HOME/nixarchy-plugin-browser"
echo '{"previews": false}' >"$XDG_CONFIG_HOME/nixarchy-plugin-browser/config.json"
out=$(bash "$LIB" preview assets/img/plugins/5-crmne-omarchy-hyprmoncfg-card.webp 2>&1); rc=$?
[[ $rc == 4 ]] || fail "off switch: expected exit 4, got $rc ($out)"
[[ $out == *"previews are off"* ]] || fail "off switch: message was '$out'"
[[ ! -e $XDG_CACHE_HOME/omarchy-plugin-audit/previews ]] || fail "off switch: previews/ was created"

# The switch fails closed (#18): a config jq cannot read means off, not on.
echo '{' >"$XDG_CONFIG_HOME/nixarchy-plugin-browser/config.json"
out=$(bash "$LIB" preview assets/img/plugins/5-crmne-omarchy-hyprmoncfg-card.webp 2>&1); rc=$?
[[ $rc == 4 ]] || fail "malformed config: expected exit 4, got $rc ($out)"
[[ ! -e $XDG_CACHE_HOME/omarchy-plugin-audit/previews ]] || fail "malformed config: previews/ was created"
echo '{"previews": false}' >"$XDG_CONFIG_HOME/nixarchy-plugin-browser/config.json"
mkdir "$T/nobin"
( PATH="$T/nobin"; fetch_preview assets/img/plugins/5-crmne-omarchy-hyprmoncfg-card.webp >/dev/null 2>&1 ); rc=$?
[[ $rc == 4 ]] || fail "jq missing: expected exit 4, got $rc"

# A bad path is refused (exit 2) before the network, with previews on.
rm -f "$XDG_CONFIG_HOME/nixarchy-plugin-browser/config.json"
bash "$LIB" preview "../../etc/passwd" >/dev/null 2>&1; rc=$?
[[ $rc == 2 ]] || fail "bad path: expected exit 2, got $rc"
[[ ! -e $XDG_CACHE_HOME/omarchy-plugin-audit/previews ]] || fail "bad path: previews/ was created"

echo ok
