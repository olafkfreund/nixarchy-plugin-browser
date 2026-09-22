#!/usr/bin/env bash
#
# Installs the Omarchy plugin browser + auditor.
#
# By default it only symlinks the two CLI tools into ~/.local/bin — no system
# files touched, nothing enabled, fully reversible with ./uninstall.sh:
#
#   omarchy-plugin-browser   the searchable marketplace TUI
#   omarchy-plugin-audit     the sandboxed, commit-pinned static scanner
#
# With --plugin it also registers the bar widget through `omarchy plugin add`,
# which lands it DISABLED (Omarchy's review-first flow). You enable it yourself.
#
# Safe to re-run — every step is idempotent.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
WITH_PLUGIN=0
QUIET=0

for arg in "$@"; do
  case "$arg" in
    --plugin) WITH_PLUGIN=1 ;;
    --quiet)  QUIET=1 ;;
    -h|--help)
      echo "Usage: ./install.sh [--plugin] [--quiet]"
      echo "  --plugin  Also register the bar widget (installed disabled; enable it yourself)."
      echo "  --quiet   Suppress the closing summary."
      exit 0 ;;
    *) echo "install.sh: unknown option: $arg" >&2; exit 1 ;;
  esac
done

say()  { ((QUIET)) || echo "$@"; }
fail() { echo "install.sh: $*" >&2; exit 1; }

# --- prerequisites -----------------------------------------------------------
missing=()
for c in git jq curl file gum; do command -v "$c" >/dev/null || missing+=("$c"); done
command -v bwrap >/dev/null || say "install.sh: note — bwrap not found; the auditor will fall back to --no-sandbox (less isolation). Install it with: omarchy pkg add bubblewrap"
(( ${#missing[@]} == 0 )) || fail "missing required tools: ${missing[*]}"

# --- 1. CLI tools ------------------------------------------------------------
mkdir -p "$BIN_DIR"
for tool in omarchy-plugin-audit omarchy-plugin-browser; do
  src="$REPO/bin/$tool"
  [[ -f $src ]] || fail "$src not found"
  chmod +x "$src"
  ln -sfn "$src" "$BIN_DIR/$tool"
  say "  linked $BIN_DIR/$tool -> $src"
done
chmod +x "$REPO/lib/omarchy-plugin-scan.sh" 2>/dev/null || true

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) say "  ⚠ $BIN_DIR is not on your PATH. Add it to your shell profile." ;;
esac

# --- 2. Bar widget (optional) ------------------------------------------------
if (( WITH_PLUGIN )); then
  command -v omarchy >/dev/null || fail "omarchy CLI not found; cannot register the bar widget"
  [[ -d $REPO/.git ]] || fail "the bar widget is installed via git; run 'git init && git add -A && git commit' in $REPO first, or add it from its GitHub URL"
  id=$(jq -r '.id' "$REPO/manifest.json")
  if [[ -d "$HOME/.config/omarchy/plugins/$id" ]]; then
    say "  bar widget '$id' already registered."
  else
    say "  registering the bar widget (installs DISABLED)…"
    omarchy plugin add "$REPO" --yes
  fi
  say ""
  say "  Enable it when ready (it will appear in the right bar section):"
  say "      omarchy plugin enable $id"
fi

# --- summary -----------------------------------------------------------------
((QUIET)) && exit 0
cat <<SUMMARY

Installed.

  Browse the marketplace:   omarchy-plugin-browser
  Audit one plugin:         omarchy-plugin-audit <git-url | plugin-id | dir>

The browser never runs marketplace code; every install routes through the
auditor, which clones into a bwrap sandbox, pins to the marketplace's verified
commit, and scans before anything reaches your shell.
SUMMARY
(( WITH_PLUGIN )) || say "  Add the bar button too:   ./install.sh --plugin"
