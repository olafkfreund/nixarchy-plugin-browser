#!/usr/bin/env bash
#
# tests/audit-gates.sh — self-check for omarchy-plugin-audit's gates: a FIND
# and a failed manifest validation give 20, a clean plugin gives 0, the staging
# file, byte and deadline limits give 3, and --export-tree refuses a plugin with
# a symlink. Fixtures only (local folders and a file:// repository), no
# network. Prints "ok" and exits 0, or names the first failure and exits 1.
# tier: host
set -uo pipefail

AUDIT="$(cd -- "$(dirname -- "$0")/.." && pwd)/bin/omarchy-plugin-audit"
T=$(mktemp -d); trap 'chmod -R u+w -- "$T" 2>/dev/null; rm -rf -- "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# Nothing is fetched: a fresh, empty catalog, and a throwaway cache and config.
export XDG_CACHE_HOME="$T/cache" XDG_CONFIG_HOME="$T/config" CATALOG="$T/catalog.json"
echo '{"plugins":[]}' >"$CATALOG"

# Validators the unsandboxed scan reaches through OMARCHY_BIN.
mkdir -p "$T/ok-bin" "$T/bad-bin"
printf '#!/bin/sh\nexit 0\n' >"$T/ok-bin/omarchy-plugin-validate"
printf '#!/bin/sh\necho "bad manifest"; exit 1\n' >"$T/bad-bin/omarchy-plugin-validate"
chmod +x "$T/ok-bin/omarchy-plugin-validate" "$T/bad-bin/omarchy-plugin-validate"

plugin() {  # plugin <dir>: a clean plugin the real validator accepts (3 files)
  mkdir -p "$1"
  printf '{"schemaVersion":1,"id":"t.fixture","name":"Fixture","version":"0.1.0","kinds":["menu"],"entryPoints":{"menu":"Menu.qml"}}\n' >"$1/manifest.json"
  printf 'import QtQuick\nItem {}\n' >"$1/Menu.qml"
  printf '# fixture\n' >"$1/README.md"
}

run() {  # run <args...>: sets rc, out (stdout) and err (stderr)
  out=$(bash "$AUDIT" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err")
}

# FIND -> 20, in the sandbox.
plugin "$T/find"; printf 'import QtQuick\nItem { Component.onCompleted: eval(x) }\n' >"$T/find/Menu.qml"
OMARCHY_BIN="$T/ok-bin" run "$T/find" --json
[[ $rc == 20 ]] || fail "FIND: exit $rc, want 20: $err"
[[ $(jq -r .outcome <<<"$out") == needs-fixes ]] || fail "FIND: outcome is not needs-fixes: $out"

# VALIDATE fail -> 20, unsandboxed so the fixture validator is the one run.
plugin "$T/clean"
OMARCHY_BIN="$T/bad-bin" run "$T/clean" --no-sandbox --json
[[ $rc == 20 ]] || fail "VALIDATE: exit $rc, want 20: $err"
[[ $(jq -r .manifestValidate <<<"$out") == fail ]] || fail "VALIDATE: manifestValidate is not fail: $out"

# clean -> 0, in the sandbox. The sandbox fixes OMARCHY_BIN to
# /run/current-system/sw/bin, so the validator is the real one when the host
# has it (ok) and absent on the CI runner (skip); never a fixture.
OMARCHY_BIN="$T/ok-bin" run "$T/clean" --json
[[ $rc == 0 ]] || fail "clean: exit $rc, want 0: $err $out"
[[ $(jq -r .manifestValidate <<<"$out") =~ ^(ok|skip)$ ]] || fail "clean: manifestValidate: $out"

# Staging limits -> 3, before anything is scanned.
AUDIT_STAGE_MAX_FILES=2 OMARCHY_BIN="$T/ok-bin" run "$T/clean" --no-sandbox --json
[[ $rc == 3 ]] || fail "file limit: exit $rc, want 3: $err"
[[ $err == *"file count 3 exceeds 2"* ]] || fail "file limit: message: $err"

AUDIT_STAGE_MAX_BYTES=10 OMARCHY_BIN="$T/ok-bin" run "$T/clean" --no-sandbox --json
[[ $rc == 3 ]] || fail "byte limit: exit $rc, want 3: $err"
[[ $err =~ size\ [0-9]+\ bytes\ exceeds\ 10 ]] || fail "byte limit: message: $err"

git -c init.defaultBranch=main init -q "$T/repo" && cp -a "$T/clean/." "$T/repo/" \
  && git -C "$T/repo" add -A \
  && git -C "$T/repo" -c user.name=t -c user.email=t@localhost commit -qm fixture \
  || fail "deadline: could not build the fixture repository"
AUDIT_STAGE_DEADLINE_SEC=0 OMARCHY_BIN="$T/ok-bin" run "file://$T/repo" --no-sandbox --json
[[ $rc == 3 ]] || fail "deadline: exit $rc, want 3: $err"
[[ $err == *deadline* ]] || fail "deadline: message: $err"

# --export-tree refuses a plugin with a symlink, and leaves nothing behind.
plugin "$T/link"; ln -s Menu.qml "$T/link/Other.qml"
OMARCHY_BIN="$T/ok-bin" run "$T/link" --no-sandbox --json --export-tree "$T/export"
[[ $rc == 20 ]] || fail "symlink export: exit $rc, want 20: $err"
[[ ! -e $T/export && ! -L $T/export ]] || fail "symlink export: $T/export was left behind"

echo ok
