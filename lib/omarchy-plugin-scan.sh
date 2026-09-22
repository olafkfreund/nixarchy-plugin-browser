#!/usr/bin/env bash
#
# omarchy-plugin-scan.sh — static heuristic scanner for an Omarchy plugin tree.
#
# Runs INSIDE the bwrap sandbox that omarchy-plugin-audit builds around a
# checked-out plugin. It has no network, an empty throwaway home, and a
# read-only view of the plugin at $1. It never executes plugin code — it reads
# the files as text and greps for patterns.
#
# It emits tab-separated records on stdout and nothing else:
#   FIND<TAB>id<TAB>file:line<TAB>snippet     a documented finding
#   CAP <TAB>id<TAB>file:line<TAB>snippet     a review-worthy capability
#   INFO<TAB>id<TAB>file:line<TAB>snippet     informational evidence
#   NIX <TAB>id<TAB>file:line<TAB>snippet     a NixOS-compatibility hazard
#   STAT<TAB>key<TAB>value                     a scan statistic
#   VALIDATE<TAB>ok|fail<TAB>message           omarchy-plugin-validate result
#   OUTCOME<TAB>passed|review-required|needs-fixes|error
#
# Finding and capability ids mirror the Omarchy marketplace Automated Security
# Baseline (SECURITY.md in omacom/omarchy-plugin-marketplace) so results are
# comparable, plus a few Omarchy-shell-specific findings the marketplace's
# command-aware analyzer covers structurally but a grep cannot: reads of
# credential paths and dynamic QML/code loading. This is grep-grade triage, not
# that analyzer. It errs toward flagging.

set -o pipefail

TARGET="${1:-/audit}"
OMARCHY_BIN="${OMARCHY_BIN:-/run/current-system/sw/bin}"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4//$'\t'/ }"; }
stat() { printf 'STAT\t%s\t%s\n' "$1" "$2"; }

[[ -d $TARGET ]] || { emit OUTCOME error - "target not a directory: $TARGET"; exit 3; }

# --- File inventory ----------------------------------------------------------
# Text files we treat as runtime source. .git is never loaded by the shell;
# skip it and the usual non-runtime directories, matching the marketplace scope.
mapfile -d '' ALL < <(find "$TARGET" \
  \( -name .git -o -name node_modules -o -name .github \
     -o -name test -o -name tests -o -name spec -o -name specs \
     -o -name fixtures -o -name coverage -o -name docs \) -prune -o \
  -type f -print0 2>/dev/null)
# Code the shell can still load (QML can `import "docs"`) is scanned wherever
# it sits; only .git and node_modules are never looked into.
declare -A SEEN=()
for f in "${ALL[@]}"; do SEEN[$f]=1; done
while IFS= read -r -d '' f; do
  [[ -n ${SEEN[$f]:-} ]] || ALL+=("$f")
done < <(find "$TARGET" \( -name .git -o -name node_modules \) -prune -o \
  -type f \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' -o -name '*.sh' \) -print0 2>/dev/null)

TEXT=()
BIN_EXEC=()
for f in "${ALL[@]}"; do
  # `file` comes from /run/current-system/sw, which the sandbox binds.
  desc=$(file -b -- "$f" 2>/dev/null)
  case "$desc" in
    *ELF*|*"PE32"*|*"Mach-O"*|*"executable"*binary*)
      BIN_EXEC+=("$f") ;;
  esac
  case "$desc" in
    *text*|*"script"*|*JSON*|*"very short file"*|*empty*) TEXT+=("$f") ;;
  esac
done

stat files_total "${#ALL[@]}"
stat files_text "${#TEXT[@]}"

scan() {  # scan <kind> <id> <regex> [file-filter-regex] [ignore-regex]
  # ignore-regex: text removed from a line before <regex> is tried again, so
  # an allowed form (e.g. /usr/bin/env) does not count as a hit on its own.
  local kind="$1" id="$2" re="$3" filt="${4:-}" ign="${5:-}"
  local hit
  for f in "${TEXT[@]}"; do
    [[ -n $filt && ! $f =~ $filt ]] && continue
    while IFS= read -r hit; do
      [[ -z $hit ]] && continue
      local ln="${hit%%:*}" rest="${hit#*:}"
      [[ -n $ign ]] && ! sed -E "s#$ign##g" <<<"$rest" | grep -qE -- "$re" && continue
      local rel="${f#"$TARGET"/}"
      emit "$kind" "$id" "$rel:$ln" "$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//; s/[[:cntrl:]]/ /g' | cut -c1-200)"
    done < <(grep -nE "$re" -- "$f" 2>/dev/null | grep -vE '^\s*[0-9]+:\s*(#|//|\*|<!--)' )
  done
}

# =============================================================================
# FINDINGS  (a match here means "needs fixes" — the marketplace would block it)
# =============================================================================

# curl-pipe-shell: content fetched then handed straight to a shell.
scan FIND curl-pipe-shell \
  '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh\b'
scan FIND curl-pipe-shell \
  '(eval|source|\.)[[:space:]]*[("<`$]+[^)]*(curl|wget)\b'
scan FIND curl-pipe-shell \
  'bash[[:space:]]+-c[[:space:]]+["'\''`][^"'\'']*\$\((curl|wget)'

# cargo-git-unpinned: cargo install --git without a 40-char --rev.
for f in "${TEXT[@]}"; do
  while IFS= read -r hit; do
    [[ -z $hit ]] && continue
    line="${hit#*:}"
    if ! grep -qE -- '--rev[= ][0-9a-f]{40}' <<<"$line"; then
      rel="${f#"$TARGET"/}"; ln="${hit%%:*}"
      emit FIND cargo-git-unpinned "$rel:$ln" "$(sed -E 's/^\s+//' <<<"$line" | cut -c1-200)"
    fi
  done < <(grep -nE 'cargo[[:space:]]+install[^|&;]*--git' -- "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|//|\*)')
done

# remote-git-execution-unpinned: clone an external repo then build/run it,
# with no detached checkout of a pinned commit anywhere in the same file.
for f in "${TEXT[@]}"; do
  grep -qE 'git[[:space:]]+clone[[:space:]]+(--[a-z=0-9]+[[:space:]]+)*https?://' -- "$f" 2>/dev/null || continue
  grep -qE '(cargo[[:space:]]+build|make\b|npm[[:space:]]+(ci|install|run)|pnpm|yarn|python[0-9]?[[:space:]]+setup\.py|\./configure|ninja\b|go[[:space:]]+build|\./[A-Za-z0-9_./-]+\.sh)' -- "$f" 2>/dev/null || continue
  if ! grep -qE 'git[[:space:]]+(-C[[:space:]]+\S+[[:space:]]+)?checkout[[:space:]]+([0-9a-f]{40}|--detach)' -- "$f" 2>/dev/null; then
    ln=$(grep -nE 'git[[:space:]]+clone' -- "$f" | head -1 | cut -d: -f1)
    rel="${f#"$TARGET"/}"
    emit FIND remote-git-execution-unpinned "$rel:${ln:-1}" "clones an external repo and builds/runs it without checking out a pinned commit"
  fi
done

# sudoers-dangerous-passwordless-command: NOPASSWD granting a broad surface.
scan FIND sudoers-dangerous-passwordless-command \
  'NOPASSWD:[[:space:]]*(ALL|/bin/(ba|z)?sh|/usr/bin/(ba|z)?sh|/usr/bin/env|.*\*)'

# privileged-process-control-from-shared-temp: PID read from a predictable
# /tmp file then fed to privileged process control.
for f in "${TEXT[@]}"; do
  grep -qE '/tmp/[A-Za-z0-9._-]*(pid|PID)' -- "$f" 2>/dev/null || continue
  if grep -qE '(sudo|pkexec)[^\n]*\b(kill|systemctl|renice|kill -)' -- "$f" 2>/dev/null; then
    ln=$(grep -nE '/tmp/[A-Za-z0-9._-]*(pid|PID)' -- "$f" | head -1 | cut -d: -f1)
    rel="${f#"$TARGET"/}"
    emit FIND privileged-process-control-from-shared-temp "$rel:${ln:-1}" "reads a PID from a shared /tmp path used near privileged process control"
  fi
done

# --- Omarchy-shell-specific findings (not in the marketplace grep set) -------

# credential-path-access: the plugin names a private credential/secret *file
# path*. A shell plugin almost never has business reading these; it is the
# closest grep gets to "exfiltrates your keys", so it is a FIND. Only concrete
# paths — NOT the word "password", which is a legitimate field name on any auth
# UI (the first-party wifiqr panel assigns `root.password`), and NOT bare env
# var names, which are handled as a capability below.
scan FIND credential-path-access \
  '(\.ssh/|id_rsa|id_ed25519|id_ecdsa|\.aws/credentials|\.config/gh/hosts|\.netrc|\.gnupg|/keyrings?/|cookies\.sqlite|Login Data|login\.keychain|\.mozilla/[^"'\'' ]*key|wallet\.dat|password-store)'

# dynamic-code-load: code assembled or fetched at runtime and executed. This is
# the shell-plugin analogue of curl|sh — the whole reason the manual says
# plugins are unsandboxed code. Requires an actual execution sink: eval, the
# Function constructor, QML built from a string, or a component from a remote
# URL. Bare base64 decode (atob) is NOT flagged on its own — decoding a display
# string is benign, and the marketplace baseline treats it the same way; if the
# decoded bytes are then eval'd, the eval sink below catches it.
scan FIND dynamic-code-load \
  '(Qt\.createQmlObject[[:space:]]*\(|Qt\.createComponent[[:space:]]*\([[:space:]]*["'\'']https?:|(^|[^A-Za-z0-9_.])eval[[:space:]]*\(|new[[:space:]]+Function[[:space:]]*\(|(^|[^A-Za-z0-9_.])Function[[:space:]]*\([[:space:]]*["'\''])' \
  '\.(qml|js|mjs)$'

# =============================================================================
# CAPABILITIES  (review-worthy on their own, not a block)
# =============================================================================
scan CAP installer               '(^|/)(install|installer|setup|uninstall)([-_.]|$)|makefile|Makefile' '(\.sh|\.mjs|\.js|\.py|akefile)$'
scan CAP package-manager         '\b(pacman|yay|paru|apt-get|apt|dnf|zypper|pip[0-9]?[[:space:]]+install|npm[[:space:]]+install|cargo[[:space:]]+install|flatpak[[:space:]]+install|brew[[:space:]]+install)\b'
scan CAP privilege               '(^|[^A-Za-z_-])(sudo|pkexec)([^A-Za-z_-]|$)'
scan CAP service-management      '\b(systemctl|systemd-run)\b|\.service["'\'' ]'
scan CAP sudoers-modification    '(/etc/sudoers|visudo)'
scan CAP remote-build            '(cargo[[:space:]]+build|npm[[:space:]]+run[[:space:]]+build|make[[:space:]]+(all|build)?|go[[:space:]]+build|\./configure)'
# secret-reference: the plugin mentions a secret env var or an inline token/key.
# Legitimate for an API-backed widget (weather keys, a mail token), so it is a
# capability to review, not a finding. `password =` is intentionally excluded —
# too common as a plain field name to carry any signal.
scan CAP secret-reference        '(ANTHROPIC_API_KEY|OPENAI_API_KEY|AWS_SECRET(_ACCESS_KEY)?|AWS_ACCESS_KEY_ID|[A-Z0-9_]*_TOKEN[[:space:]]*=|[A-Z0-9_]*_SECRET[[:space:]]*=|apiKey[[:space:]]*[:=])'

for f in "${BIN_EXEC[@]}"; do
  rel="${f#"$TARGET"/}"
  emit CAP bundled-executable-binary "$rel:0" "$(file -b -- "$f" 2>/dev/null | cut -c1-120)"
done

# =============================================================================
# INFORMATIONAL  (context for the human; never affects outcome)
# =============================================================================
scan INFO process-spawn          '(Process[[:space:]]*\{|execDetached|Quickshell\.execDetached|IpcHandler|\.startDetached)' '\.qml$'
scan INFO network-access         '(XMLHttpRequest|[^A-Za-z]fetch[[:space:]]*\(|https?://|curl|wget|Socket|WebSocket)' '\.(qml|js|mjs|sh|py)$'
scan INFO filesystem-write       '(FileView|writeFile|std::ofstream|>[[:space:]]*\$?(HOME|~)|open\([^)]*[wa]["'\''])' '\.(qml|js|mjs|sh|py)$'

# =============================================================================
# NIXOS COMPATIBILITY  (does this run on NixOS? separate from the security
# verdict; the outer audit maps each id to blocker/review)
# =============================================================================
# Code a plugin runs: QML/JS, shell, Python, and extensionless scripts.
NIX_CODE='\.(qml|js|mjs|sh|py)$|/[^./]+$'

# fhs-path: an absolute FHS path. NixOS has no /usr/bin/<tool>, no
# /usr/share/omarchy ($OMARCHY_PATH is a store path) and no /usr/lib or /opt.
# /usr/bin/env is the one path NixOS guarantees.
scan NIX fhs-path \
  '/usr/s?bin/[A-Za-z]|/usr/share/omarchy|/usr/lib/|(^|[^A-Za-z0-9_.~])/opt/' \
  "$NIX_CODE" '/usr/bin/env'

# fhs-shebang: an interpreter NixOS does not have at that path. #!/bin/sh and
# #!/usr/bin/env are fine. (scan() skips # lines, so this reads line 1 itself.)
for f in "${TEXT[@]}"; do
  first=$(head -n1 -- "$f" 2>/dev/null)
  if [[ $first =~ ^\#![[:space:]]*/(usr/)?bin/(bash|zsh|fish|python[0-9.]*|node|perl)([[:space:]]|$) ]]; then
    emit NIX fhs-shebang "${f#"$TARGET"/}:1" "$(cut -c1-200 <<<"$first")"
  fi
done

# imperative-pkg: Arch package managers, or Omarchy's pacman wrapper. On
# nixarchy these either do not exist or refuse; packages are declared.
scan NIX imperative-pkg '\b(pacman|yay|paru|makepkg)\b|omarchy[- ]pkg[- ](add|install)'

# etc-write: /etc on NixOS is generated from the configuration and is mostly
# read-only links into the store; a write there fails or is lost on rebuild.
scan NIX etc-write '(tee|cp|install|mv|ln)[^|;]*[[:space:]]/etc/|>[[:space:]]*/etc/'

# global-lang-install: pip outside a venv, npm -g. Both write where NixOS
# either forbids it or loses it.
for f in "${TEXT[@]}"; do
  rel="${f#"$TARGET"/}"
  if ! grep -q venv -- "$f" 2>/dev/null; then
    while IFS= read -r hit; do
      emit NIX global-lang-install "$rel:${hit%%:*}" "$(sed -E 's/^[[:space:]]+//' <<<"${hit#*:}" | cut -c1-200)"
    done < <(grep -nE 'pip[0-9]?[[:space:]]+install' -- "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|//|\*)')
  fi
  while IFS= read -r hit; do
    emit NIX global-lang-install "$rel:${hit%%:*}" "$(sed -E 's/^[[:space:]]+//' <<<"${hit#*:}" | cut -c1-200)"
  done < <(grep -nE 'npm[[:space:]]+(i|install)[[:space:]]+(-g|--global)' -- "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|//|\*)')
done

# download-exec: fetches a file and marks it executable, i.e. runs a prebuilt
# binary, which on NixOS needs nix-ld or patching.
for f in "${TEXT[@]}"; do
  grep -qE '(curl|wget)[^|]*(-o|-O|--output)' -- "$f" 2>/dev/null || continue
  grep -qE 'chmod[[:space:]]+\+?[0-7]*x' -- "$f" 2>/dev/null || continue
  ln=$(grep -nE '(curl|wget)[^|]*(-o|-O|--output)' -- "$f" | head -1 | cut -d: -f1)
  emit NIX download-exec "${f#"$TARGET"/}:${ln:-1}" "downloads a file and makes it executable"
done

# bundled-elf: a shipped prebuilt binary; its interpreter path is not on NixOS.
for f in "${BIN_EXEC[@]}"; do
  emit NIX bundled-elf "${f#"$TARGET"/}:0" "prebuilt binary; needs nix-ld or autoPatchelf"
done

# =============================================================================
# MANIFEST VALIDATION  (same check the shell enforces before loading)
# =============================================================================
if [[ -x "$OMARCHY_BIN/omarchy-plugin-validate" ]]; then
  if vout=$("$OMARCHY_BIN/omarchy-plugin-validate" "$TARGET" 2>&1); then
    printf 'VALIDATE\tok\t%s\n' "manifest passes the shell's schema checks"
  else
    printf 'VALIDATE\tfail\t%s\n' "$(printf '%s' "$vout" | tr '\n' ' ' | cut -c1-200)"
  fi
else
  printf 'VALIDATE\tskip\t%s\n' "omarchy-plugin-validate not present in sandbox"
fi

# =============================================================================
# DONE
# =============================================================================
# The outer omarchy-plugin-audit tallies FIND/CAP records to decide the outcome
# (passed / review-required / needs-fixes) — it is the single source of truth,
# so the scanner deliberately does not print its own OUTCOME line. A completed
# run exits 0; only an infrastructure failure (handled above) exits non-zero.
printf 'STAT\tscan\tcomplete\n'
exit 0
