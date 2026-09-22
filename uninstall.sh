#!/usr/bin/env bash
# Reverses install.sh. Removes the CLI symlinks and, if present, the registered
# bar widget. Leaves the cloned repo and the catalog cache in place.
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"

for tool in omarchy-plugin-audit omarchy-plugin-browser nixarchy-plugin-fix; do
  if [[ -L "$BIN_DIR/$tool" ]]; then rm -f "$BIN_DIR/$tool"; echo "  removed $BIN_DIR/$tool"; fi
done

id=$(jq -r '.id' "$REPO/manifest.json" 2>/dev/null || echo "")
if [[ -n $id && -d "$HOME/.config/omarchy/plugins/$id" ]] && command -v omarchy >/dev/null; then
  echo "  removing bar widget '$id'…"
  omarchy plugin remove "$id" --yes || true
fi

echo "Done. (Catalog cache left at ${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-plugin-audit; delete it manually if you want.)"
