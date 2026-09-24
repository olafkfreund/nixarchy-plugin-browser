#!/usr/bin/env bash
# tier: hermetic
#
# tests/audit-self.sh — the scanner passes this repo honestly (#15 item 8): no
# FIND, no NIX record, and no FIND/CAP/NIX record for the scanner's own
# detector lines (INFO rules are left as they are). No allowlist: a real hit
# added to a copy of the repo is still found.
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail
export PATH="/run/current-system/sw/bin:$PATH"

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# A copy without .git, the local .claude/ state or nix result links.
mkdir "$T/repo"
tar -C "$ROOT" --exclude=./.git --exclude=./.claude --exclude='./result*' -cf - . | tar -C "$T/repo" -xf -

fail() { echo "FAIL: $*"; exit 1; }
OUT=$(OMARCHY_BIN=/nonexistent bash "$T/repo/lib/omarchy-plugin-scan.sh" "$T/repo")
bad=$(grep -P '^FIND\t' <<<"$OUT"); [[ -z $bad ]] || fail "FIND in the repo:"$'\n'"$bad"
bad=$(grep -P '^NIX\t' <<<"$OUT"); [[ -z $bad ]] || fail "NIX record in the repo:"$'\n'"$bad"
bad=$(grep -P '^(CAP|FIND|NIX)\t[^\t]+\tlib/omarchy-plugin-scan\.sh:' <<<"$OUT")
[[ -z $bad ]] || fail "the scanner flags its own detectors:"$'\n'"$bad"

# The same detector still fires on a real line (spelled here so this file
# does not match it either).
printf 'u ALL=(ALL) NOPASSW%s: ALL\n' D >>"$T/repo/install.sh"
OUT=$(OMARCHY_BIN=/nonexistent bash "$T/repo/lib/omarchy-plugin-scan.sh" "$T/repo")
grep -qP '^FIND\tsudoers-dangerous-passwordless-command\tinstall\.sh:' <<<"$OUT" \
  || fail "an added sudoers line is not found"
echo ok
