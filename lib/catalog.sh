#!/usr/bin/env bash
#
# catalog.sh — the one place the Omarchy marketplace catalog is fetched.
#
# Sourced by omarchy-plugin-audit and omarchy-plugin-browser for:
#   CATALOG                    path of the cached catalog.json
#   catalog_usable <file>      a regular, own, non-empty file within the ceiling
#   fetch_catalog [--force]    0: a usable catalog is in place (fresh, or stale
#                              with a note on stderr); 1: none
# A caller may set CATALOG_RUNNER=(argv...) first to wrap the download (the
# TUI's gum spinner); the download stays one bounded curl argv either way.
#
# Run directly by the shell panel:
#   catalog.sh list [--refresh]    community plugins as one compact JSON array,
#                                  most-starred first, so the shell never parses
#                                  the full ~8 MB catalog itself
#
# The catalog is read as data only; nothing in it is ever executed.

CATALOG_URL="https://plugins.omarchy.org/catalog.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-plugin-audit"
CATALOG="${CATALOG:-$CACHE_DIR/catalog.json}"   # overridable for tests
CACHE_TTL=3600
# About 8 MB for ~3,100 plugins. Anything past this ceiling is refused before
# it is parsed, so a broken or hostile endpoint can neither fill the disk during
# the download nor hand jq an unbounded document.
CATALOG_MAX_BYTES=$((32 * 1024 * 1024))
declare -p CATALOG_RUNNER >/dev/null 2>&1 || CATALOG_RUNNER=()

# A cached catalog is only read if it is a regular file (not a symlink) owned by
# this user and within the ceiling.
catalog_usable() {
  local f="$1" size
  [[ -f $f && ! -L $f && -O $f ]] || return 1
  size=$(stat -c %s -- "$f" 2>/dev/null) || return 1
  (( size > 0 && size <= CATALOG_MAX_BYTES ))
}

# Download into a private temp file next to the cache (mktemp creates it
# exclusively, mode 600), check it, then rename it into place atomically.
download_catalog() {
  local dest="$1" dir tmp
  dir=$(dirname -- "$dest")
  mkdir -p -- "$dir" && chmod 700 -- "$dir" || return 1
  tmp=$(mktemp -p "$dir" .catalog.XXXXXX) || return 1
  if ! "${CATALOG_RUNNER[@]}" curl -fsS --proto '=https' --tlsv1.2 --max-time 30 \
       --max-filesize "$CATALOG_MAX_BYTES" -o "$tmp" -- "$CATALOG_URL" 2>/dev/null \
     || ! catalog_usable "$tmp" \
     || ! jq -e '(.plugins | type) == "array"' "$tmp" >/dev/null 2>&1; then
    rm -f -- "$tmp"
    return 1
  fi
  mv -f -- "$tmp" "$dest"
}

fetch_catalog() {
  if [[ ${1:-} != --force ]] && catalog_usable "$CATALOG" \
     && (( $(date +%s) - $(stat -c %Y -- "$CATALOG" 2>/dev/null || echo 0) < CACHE_TTL )); then
    return 0
  fi
  download_catalog "$CATALOG" && return 0
  catalog_usable "$CATALOG" || return 1
  echo "catalog: could not refresh; using the cached copy." >&2
}

# ---- run directly -----------------------------------------------------------
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -uo pipefail
  export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-}/bin"
  case "${1:-}" in
    list)
      force=""; [[ ${2:-} == --refresh ]] && force=--force
      fetch_catalog $force || { echo "catalog: no usable catalog (at most $((CATALOG_MAX_BYTES / 1048576)) MiB)" >&2; exit 3; }
      jq -c '
        [ .plugins[]
          | select(.sourceType == "community")
          | { id, name: (.name // .id), author: (.author // ""), category: (.category // ""),
              stars: (.stars // 0), tags: (.tags // []),
              badge: (if .verificationStatus == "verified" then "verified"
                      elif .verificationSnapshotStatus == "verified" then "snapshot"
                      else "unverified" end),
              description: (.description // ""), repo: (.repo // ""),
              installCommand: (.installCommand // ""), installAvailable: (.installAvailable == true) } ]
        | sort_by(-.stars)' "$CATALOG" ;;
    *) echo "usage: catalog.sh list [--refresh]" >&2; exit 2 ;;
  esac
fi
