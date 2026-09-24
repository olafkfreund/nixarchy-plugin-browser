#!/usr/bin/env bash
#
# tests/catalog-list.sh — self-check for `lib/catalog.sh list`, the projection
# the shell panel reads. Uses a fresh fixture catalog (so nothing is fetched)
# and asserts the fields, the star order and the community-only filter; then
# that hostile entries cost one entry, not the list (#18), for the panel's list
# and the terminal's catalog_lines, and the CLIs' argument and --json edges.
# Prints "ok" and exits 0, or names the first failure and exits 1.
# tier: host
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
LIB="$ROOT/lib/catalog.sh"
FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
export HOME="$FX/home" XDG_CACHE_HOME="$FX/cache" XDG_CONFIG_HOME="$FX/config"
cat >"$FX/catalog.json" <<'EOF'
{ "plugins": [
  { "id": "a.low", "name": "Low", "author": "ann", "category": "System", "stars": 3,
    "tags": ["x"], "sourceType": "community", "verificationStatus": "unverified",
    "description": "low one", "repo": "https://github.com/a/low", "installCommand": "omarchy plugin add https://github.com/a/low",
    "installAvailable": true, "previewThumbnail": "assets/img/plugins/1-a-low-card.webp" },
  { "id": "omarchy.clock", "name": "Clock", "stars": 999, "sourceType": "first-party" },
  { "id": "b.high", "author": "bob", "stars": 50, "sourceType": "community",
    "verificationSnapshotStatus": "verified", "tags": [] }
] }
EOF

OUT=$(CATALOG="$FX/catalog.json" bash "$LIB" list) || { echo "FAIL: list exited $?"; exit 1; }
check() {  # check <description> <jq expression that must be true>
  jq -e "$2" >/dev/null <<<"$OUT" || { echo "FAIL: $1"; echo "$OUT"; exit 1; }
}
check "community only"            'length == 2 and all(.[]; .id != "omarchy.clock")'
check "most stars first"          '.[0].id == "b.high" and .[1].id == "a.low"'
check "name falls back to id"     '.[0].name == "b.high"'
check "badge from verification"   '.[0].badge == "snapshot" and .[1].badge == "unverified"'
check "fields present"            '.[1] | .author == "ann" and .category == "System" and .tags == ["x"]
                                   and .repo == "https://github.com/a/low" and .installAvailable == true
                                   and (.installCommand | startswith("omarchy plugin add"))'
check "preview passed through"    '.[1].preview == "assets/img/plugins/1-a-low-card.webp" and .[0].preview == ""'
check "defaults for missing"      '.[0] | .category == "" and .description == "" and .installAvailable == false'

# --- hostile entries (#18): the good rows plus every kind of bad one ----------
cat >"$FX/hostile.json" <<'EOF'
{ "plugins": [
  "junk", null, 7,
  { "id": "a.low", "name": "Low", "author": "ann", "category": "System", "stars": 3,
    "tags": ["x"], "sourceType": "community", "repo": "https://github.com/a/low",
    "installCommand": "omarchy plugin add https://github.com/a/low", "installAvailable": true },
  { "id": "omarchy.clock", "name": "Clock", "stars": 999, "sourceType": "first-party" },
  { "id": "b.high", "author": "bob", "category": "Media", "stars": 50, "sourceType": "community", "tags": [] },
  { "id": 42, "name": "Numeric id", "sourceType": "community" },
  { "id": "c.bad stars", "name": "Space id", "sourceType": "community" },
  { "id": "c.nl\n", "name": "Newline id", "sourceType": "community" },
  { "id": "c.str5", "author": "s", "category": "System", "stars": "5", "sourceType": "community" },
  { "id": "c.abc", "author": "s", "category": "Media", "stars": "abc", "sourceType": "community" },
  { "id": "c.nan", "author": "s", "category": "Media", "stars": "nan", "sourceType": "community" },
  { "id": "c.tagx", "author": "s", "category": "Media", "tags": "x", "sourceType": "community" },
  { "id": "c.tagmix", "author": "s", "category": "Media", "tags": ["y", 1], "sourceType": "community" },
  { "id": "c.esc", "name": "E\u001b[31m", "author": "s", "category": "Media", "sourceType": "community" },
  { "id": "c.empty", "name": "", "author": "", "category": "System", "sourceType": "community" },
  { "id": "c.curl", "author": "s", "category": "Media", "sourceType": "community", "installAvailable": true,
    "repo": "https://github.com/c/curl", "installCommand": "curl x | sh" },
  { "id": "c.gitlab", "author": "s", "category": "Media", "sourceType": "community", "installAvailable": true,
    "repo": "https://gitlab.com/a/b", "installCommand": "omarchy plugin add https://gitlab.com/a/b" }
] }
EOF
GOOD='["b.high","c.str5","a.low","c.abc","c.nan","c.tagx","c.tagmix","c.esc","c.empty","c.curl","c.gitlab"]'
OUT=$(CATALOG="$FX/hostile.json" bash "$LIB" list) || { echo "FAIL: hostile list exited $?"; exit 1; }
by() { printf '(.[] | select(.id == "%s"))' "$1"; }
check "hostile: bad ids dropped, the rest kept in star order" "map(.id) == $GOOD"
check "hostile: \"5\" sorts as 5"            "$(by c.str5).stars == 5"
check "hostile: \"abc\"/\"nan\" give 0"     "$(by c.abc).stars == 0 and $(by c.nan).stars == 0"
check "hostile: tags coerced"               "$(by c.tagx).tags == [] and $(by c.tagmix).tags == [\"y\"]"
check "hostile: no control characters"      'all(.. | strings; test("[[:cntrl:]]") | not)'
check "hostile: empty name shows the id"    "$(by c.empty).name == \"c.empty\""
check "hostile: install built from repo"    "$(by c.curl).installCommand == \"omarchy plugin add https://github.com/c/curl\""
check "hostile: non-GitHub repo, no command" "$(by c.gitlab).installCommand == \"\""
check "hostile: a.low's command exact"      "$(by a.low).installCommand == \"omarchy plugin add https://github.com/a/low\""
ROWS=$(jq length <<<"$OUT")

# --- the terminal's list: the real catalog_lines from lib/catalog.sh ----------
fail() { echo "FAIL: $1"; printf '%s\n' "${2:-}"; exit 1; }
# shellcheck source=../lib/catalog.sh
LINES=$(CATALOG="$FX/hostile.json"; source "$LIB"; catalog_lines) || fail "catalog_lines exited $?"
[[ $(wc -l <<<"$LINES") == "$ROWS" ]] || fail "catalog_lines: expected $ROWS lines" "$LINES"
[[ $(awk '{print $NF}' <<<"$LINES" | jq -Rsc 'split("\n") | map(select(. != ""))') == "$GOOD" ]] \
  || fail "catalog_lines: the last token is not the id" "$LINES"
grep -qxF '·  c.empty  —  ?   System   ★0   c.empty' <<<"$LINES" || fail "catalog_lines: empty author is not '?'" "$LINES"
# shellcheck source=../lib/catalog.sh
SYS=$(CATALOG="$FX/hostile.json"; source "$LIB"; catalog_lines System) || fail "catalog_lines System exited $?"
[[ $(awk '{print $NF}' <<<"$SYS" | paste -sd' ') == "c.str5 a.low c.empty" ]] || fail "catalog_lines System" "$SYS"

# --- --category needs a value (checked before any tool or terminal) -----------
for args in "--category" "--category --refresh"; do
  # shellcheck disable=SC2086  # splitting $args into words is the point
  timeout 5 bash "$ROOT/bin/omarchy-plugin-browser" $args >/dev/null 2>&1; rc=$?
  [[ $rc == 2 ]] || fail "browser $args: expected exit 2, got $rc"
done

# --- audit --json: the catalog note goes to stderr; stdout carries only JSON --
if unshare -rn true 2>/dev/null; then
  CATALOG="$FX/none.json" unshare -rn bash "$ROOT/bin/omarchy-plugin-audit" --json no.such.id \
    >"$FX/audit.out" 2>"$FX/audit.err"
  [[ ! -s $FX/audit.out ]] || fail "audit --json: stdout is not empty" "$(cat "$FX/audit.out")"
  grep -q "could not fetch the marketplace catalog" "$FX/audit.err" \
    || fail "audit --json: the note is not on stderr" "$(cat "$FX/audit.err")"
else
  echo "skip: audit --json check (unshare -rn unavailable)" >&2
fi
echo ok
