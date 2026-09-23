#!/usr/bin/env bash
#
# tests/catalog-list.sh — self-check for `lib/catalog.sh list`, the projection
# the shell panel reads. Uses a fresh fixture catalog (so nothing is fetched)
# and asserts the fields, the star order and the community-only filter.
# Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail

LIB="$(cd -- "$(dirname -- "$0")/.." && pwd)/lib/catalog.sh"
FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
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
echo ok
