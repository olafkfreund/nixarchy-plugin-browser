#!/usr/bin/env bash
#
# catalog.sh — the one place the Omarchy marketplace catalog is fetched.
#
# Sourced by omarchy-plugin-audit and omarchy-plugin-browser for:
#   CATALOG                    path of the cached catalog.json
#   catalog_usable <file>      a regular, own, non-empty file within the ceiling
#   fetch_catalog [--force]    0: a usable catalog is in place (fresh, or stale
#                              with a note on stderr); 1: none
#   CATALOG_ROWS_JQ            jq defs: catalog_row, catalog_rows, install_command
#   catalog_lines [category]   the terminal browser's list, one line per plugin
#   catalog_detail <id>        the terminal browser's detail card fields
# A caller may set CATALOG_RUNNER=(argv...) first to wrap the download (the
# TUI's gum spinner); the download stays one bounded curl argv either way.
#
# Run directly by the shell panel:
#   catalog.sh preview <relpath>   one plugin's preview thumbnail as a verified
#                                  local file path (see "previews" below)
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

# The one projection of the untrusted catalog, shared by `catalog.sh list` (the
# panel) and the terminal browser. Every field may be missing or of any type:
# a bad field is coerced to a safe value; only an entry without a usable id is
# dropped. Control characters never reach a terminal or the panel. Regexes end
# in \z, not $: in jq, $ also matches before a trailing newline.
# The install command is built from the checked GitHub repo, never copied from
# the catalog's installCommand.
# shellcheck disable=SC2016  # jq source: $n is a jq variable
CATALOG_ROWS_JQ='
  def _s: if type == "string" then gsub("[[:cntrl:]]"; " ") else "" end;
  def _or($d): if . == "" then $d else . end;
  def install_command:
    if .installAvailable == true
       and (.repo | type == "string" and test("^https://github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/?\\z"))
    then "omarchy plugin add " + (.repo | sub("/\\z"; "")) else "" end;
  def catalog_row:
    { id,
      name: ((.name | _s) as $n | if $n == "" then .id else $n end),
      author: (.author | _s), category: (.category | _s),
      stars: (.stars | if type == "number" then . elif type == "string" then (tonumber? // 0) else 0 end
              | if isinfinite or isnan then 0 else . end),
      tags: (.tags | if type == "array" then map(select(type == "string") | _s) else [] end),
      badge: (if .verificationStatus == "verified" then "verified"
              elif .verificationSnapshotStatus == "verified" then "snapshot"
              else "unverified" end),
      description: (.description | _s), repo: (.repo | _s),
      installCommand: install_command, installAvailable: (.installAvailable == true),
      preview: (.previewThumbnail | _s) };
  def catalog_rows:
    [ (.plugins // [])[] | objects
      | select(.sourceType == "community")
      | select(.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z"))
      | catalog_row ]
    | sort_by(-.stars);'

# The terminal browser's list: one selectable line per plugin, id the final
# token. Badge: ✔ verified snapshot & upstream matches · ◐ snapshot verified
# but upstream moved (update unverified) · · unverified.
catalog_lines() {  # catalog_lines [category]
  jq -r "$CATALOG_ROWS_JQ"'
    catalog_rows[]
    | select($cat == "" or .category == $cat)
    | [ ({verified: "✔", snapshot: "◐"}[.badge] // "·"), "  ", .name,
        "  —  ", (.author | _or("?")),
        "   ", (.category | _or("?")),
        "   ★", (.stars | tostring),
        (if (.tags | length) > 0 then "   #" + (.tags | join(" #")) else "" end),
        "   ", .id ] | join("")
  ' --arg cat "${1:-}" "$CATALOG"
}

# The terminal browser's detail card for one id: fifteen NUL-terminated
# fields in this order (show_detail reads them so): name author repo
# category stars version vstatus vcoverage vcommit upstream installCommand
# installAvailable installNote description tags. Unknown id: no output.
catalog_detail() {  # catalog_detail <id>
  jq --raw-output0 --arg id "$1" "$CATALOG_ROWS_JQ"'
    first(.plugins[]? | objects | select(.id == $id))
    | . as $e | catalog_row as $r
    | $r.name, ($r.author | _or("?")), $r.repo, ($r.category | _or("?")), ($r.stars | tostring),
      (.version | _s | _or("?")),
      (.verificationStatus | _s | _or("unverified")), (.verificationCoverage | _s | _or("none")),
      (.verificationCommit | _s | _or($e.listingValidatedCommit | _s)), (.upstreamObservedCommit | _s),
      $r.installCommand, ($r.installAvailable | tostring), (.installNote | _s), $r.description,
      ($r.tags | if length > 0 then "#" + join("  #") else "" end)
  ' "$CATALOG"
}
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

# ---- previews ----------------------------------------------------------------
# A plugin's preview thumbnail, fetched only when its details are opened, and
# handed to the shell only as a local file that has passed every check below:
# the shell never decodes bytes straight from the network.
PREVIEW_HOST="https://plugins.omarchy.org"
PREVIEW_DIR="$CACHE_DIR/previews"
PREVIEW_MAX_BYTES=$((2 * 1024 * 1024))     # the real thumbnails are ~20-100 KB
PREVIEW_CACHE_MAX=$((50 * 1024 * 1024))
PREVIEW_RE='^assets/img/plugins/[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.(webp|png)$'
PREVIEW_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy-plugin-browser/config.json"

# "previews": false in the plugin's config turns fetching off entirely. A
# config that exists but cannot be read counts as off: the switch fails closed.
previews_enabled() {
  [[ -e $PREVIEW_CONFIG ]] || return 0
  local v
  v=$(jq -r '.previews' "$PREVIEW_CONFIG" 2>/dev/null) || return 1
  [[ $v != false ]]
}

# Only the marketplace's own image folder; the host is never taken from input.
preview_path_ok() { [[ $1 =~ $PREVIEW_RE ]]; }

# A regular, own, non-empty file within the ceiling, whose first bytes are what
# its extension says: RIFF....WEBP for .webp, the PNG signature for .png.
preview_file_ok() {  # preview_file_ok <file> <webp|png>
  local f="$1" ext="$2" size magic
  [[ -f $f && ! -L $f && -O $f ]] || return 1
  size=$(stat -c %s -- "$f" 2>/dev/null) || return 1
  (( size > 0 && size <= PREVIEW_MAX_BYTES )) || return 1
  magic=$(head -c 12 -- "$f" | od -An -v -tx1 | tr -d ' \n')
  case "$ext" in
    webp) [[ ${magic:0:8} == 52494646 && ${magic:16:8} == 57454250 ]] ;;
    png)  [[ ${magic:0:16} == 89504e470d0a1a0a ]] ;;
    *)    return 1 ;;
  esac
}

# Keep the cache under its cap, oldest files first.
prune_previews() {
  local oldest
  while (( $(du -sb -- "$PREVIEW_DIR" 2>/dev/null | cut -f1) > PREVIEW_CACHE_MAX )); do
    oldest=$(ls -tr -- "$PREVIEW_DIR" | head -n1)
    [[ -n $oldest ]] || break
    rm -f -- "$PREVIEW_DIR/$oldest"
  done
}

fetch_preview() {  # fetch_preview <relpath>; prints the verified local path
  local rel="$1" name ext dest tmp
  previews_enabled || { echo "catalog: previews are off" >&2; return 4; }
  preview_path_ok "$rel" || { echo "catalog: not a marketplace preview path: $rel" >&2; return 2; }
  name=${rel##*/}; ext=${name##*.}; dest="$PREVIEW_DIR/$name"
  if preview_file_ok "$dest" "$ext"; then printf '%s\n' "$dest"; return 0; fi
  mkdir -p -- "$PREVIEW_DIR" && chmod 700 -- "$PREVIEW_DIR" || return 3
  tmp=$(mktemp -p "$PREVIEW_DIR" .preview.XXXXXX) || return 3
  if ! curl -fsS --proto '=https' --tlsv1.2 --max-time 15 \
         --max-filesize "$PREVIEW_MAX_BYTES" -o "$tmp" -- "$PREVIEW_HOST/$rel" 2>/dev/null \
     || ! preview_file_ok "$tmp" "$ext"; then
    rm -f -- "$tmp"; echo "catalog: preview fetch or check failed: $rel" >&2; return 3
  fi
  mv -f -- "$tmp" "$dest"
  prune_previews
  printf '%s\n' "$dest"
}

# ---- run directly -----------------------------------------------------------
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -uo pipefail
  export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-}/bin"
  case "${1:-}" in
    list)
      force=""; [[ ${2:-} == --refresh ]] && force=--force
      fetch_catalog $force || { echo "catalog: no usable catalog (at most $((CATALOG_MAX_BYTES / 1048576)) MiB)" >&2; exit 3; }
      jq -c "$CATALOG_ROWS_JQ catalog_rows" "$CATALOG" ;;
    preview) fetch_preview "${2:-}"; exit $? ;;
    *) echo "usage: catalog.sh list [--refresh] | catalog.sh preview <relpath>" >&2; exit 2 ;;
  esac
fi
