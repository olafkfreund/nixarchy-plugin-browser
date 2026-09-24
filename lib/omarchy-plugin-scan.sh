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

# A file name or a line of plugin text can hold a tab or a newline, which would
# start a forged record (e.g. "VALIDATE ok"). Every value is cleaned.
clean() { local s=${1//[[:cntrl:]]/ }; printf '%s' "$s"; }
emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$(clean "$2")" "$(clean "$3")" "$(clean "$4")"; }
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
  -type f \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' -o -name '*.sh' \
             -o ! -name '*.*' -o -name '*.py' \) -print0 2>/dev/null)

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

# code_lines <file>: the file with every comment line emptied, so `grep -n`
# still gives real line numbers. QML/JS: a // line, or a line inside a /* */
# block (opened by a line starting /*, closed at the first */; what follows */
# is code). A * line outside a block is code. Any other file: a # or <!-- line.
code_lines() {
  local js=0; [[ $1 =~ \.(qml|js|mjs)$ ]] && js=1
  awk -v js="$js" '
    function tail(s,  i) {  # code after the first */ in s, or -1 if none
      i = index(s, "*/"); if (!i) return -1
      return substr(s, i + 2)
    }
    js && blk { r = tail($0); if (r == -1) print ""; else { blk = 0; print r }; next }
    js && /^[[:space:]]*\/\// { print ""; next }
    js && /^[[:space:]]*\/\*/ { s = $0; sub(/^[[:space:]]*\/\*/, "", s); r = tail(s)
                                if (r == -1) { blk = 1; print "" } else print r; next }
    !js && /^[[:space:]]*(#|<!--)/ { print ""; next }
    { print }' 2>/dev/null <"$1"
}

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
    done < <(code_lines "$f" | grep -nE -- "$re")
  done
}

# Every literal word in a FIND, CAP or NIX detector is spelled with one letter
# in brackets (pac[m]an, NOPASSW[D], sud[o], /op[t]/): it matches exactly the
# plain word, but the detector's own line does not, so this scanner (and
# nixarchy's build check, programs.nixarchy.plugins, which rejects any plugin
# whose code names pacman or yay) never reads a detector as a caller. Keep the
# rule when adding a detector; tests/audit-self.sh checks it.

# =============================================================================
# FINDINGS  (a match here means "needs fixes" — the marketplace would block it)
# =============================================================================

# curl-pipe-shell: content fetched then handed straight to a shell.
scan FIND curl-pipe-shell \
  '(curl|wget)[^|]*\|[[:space:]]*(sud[o][[:space:]]+)?(ba|z|da)?sh\b'
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
  done < <(code_lines "$f" | grep -nE 'cargo[[:space:]]+install[^|&;]*--git')
done

# remote-git-execution-unpinned: clone an external repo then build/run it,
# with no detached checkout of a pinned commit anywhere in the same file.
for f in "${TEXT[@]}"; do
  grep -qE 'git[[:space:]]+clone[[:space:]]+(--[a-z=0-9]+[[:space:]]+)*https?://' -- "$f" 2>/dev/null || continue
  grep -qE '(cargo[[:space:]]+build|make\b|npm[[:space:]]+(ci|install|run)|pnpm|yarn|python[0-9]?[[:space:]]+setup\.py|\./configur[e]|ninja\b|go[[:space:]]+build|\./[A-Za-z0-9_./-]+\.sh)' -- "$f" 2>/dev/null || continue
  if ! grep -qE 'git[[:space:]]+(-C[[:space:]]+\S+[[:space:]]+)?checkout[[:space:]]+([0-9a-f]{40}|--detach)' -- "$f" 2>/dev/null; then
    ln=$(grep -nE 'git[[:space:]]+clone' -- "$f" | head -1 | cut -d: -f1)
    rel="${f#"$TARGET"/}"
    emit FIND remote-git-execution-unpinned "$rel:${ln:-1}" "clones an external repo and builds/runs it without checking out a pinned commit"
  fi
done

# sudoers-dangerous-passwordless-command: NOPASSWD granting a broad surface.
scan FIND sudoers-dangerous-passwordless-command \
  'NOPASSW[D]:[[:space:]]*(ALL|/bin/(ba|z)?sh|/usr/bin/(ba|z)?sh|/usr/bin/env|.*\*)'

# privileged-process-control-from-shared-temp: PID read from a predictable
# /tmp file then fed to privileged process control.
for f in "${TEXT[@]}"; do
  grep -qE '/tmp/[A-Za-z0-9._-]*(pid|PID)' -- "$f" 2>/dev/null || continue
  if grep -qE '(sud[o]|pkexe[c]).*\b(kill|systemct[l]|renice)' -- "$f" 2>/dev/null; then
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
  '(\.ss[h]/|id_rs[a]|id_ed2551[9]|id_ecds[a]|\.aw[s]/credentials|\.config/g[h]/hosts|\.netr[c]|\.gnup[g]|/keyrings?/|cookies\.sqlite|Login Dat[a]|login\.keychain|\.mozilla/[^"'\'' ]*key|wallet\.dat|password-stor[e])'

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
scan CAP installer               '(^|/)(install|installer|setup|uninstall)([-_.]|$)|makefil[e]|Makefil[e]' '(\.sh|\.mjs|\.js|\.py|akefile)$'
scan CAP package-manager         '\b(pac[m]an|y[a]y|par[u]|a[p]t-get|ap[t]|dn[f]|zyppe[r]|pip[0-9]?[[:space:]]+install|npm[[:space:]]+install|cargo[[:space:]]+install|flatpak[[:space:]]+install|brew[[:space:]]+install)\b'
scan CAP privilege               '(^|[^A-Za-z_-])(sud[o]|pkexe[c])([^A-Za-z_-]|$)'
scan CAP service-management      '\b(systemct[l]|systemd-ru[n])\b|\.service["'\'' ]'
scan CAP sudoers-modification    '(/etc/sudoer[s]|visud[o])'
scan CAP remote-build            '(cargo[[:space:]]+build|npm[[:space:]]+run[[:space:]]+build|make[[:space:]]+(all|build)?|go[[:space:]]+build|\./configur[e])'
# secret-reference: the plugin mentions a secret env var or an inline token/key.
# Legitimate for an API-backed widget (weather keys, a mail token), so it is a
# capability to review, not a finding. `password =` is intentionally excluded —
# too common as a plain field name to carry any signal.
scan CAP secret-reference        '(ANTHROPIC_API_KE[Y]|OPENAI_API_KE[Y]|AWS_SECRE[T](_ACCESS_KEY)?|AWS_ACCESS_KEY_I[D]|[A-Z0-9_]*_TOKEN[[:space:]]*=|[A-Z0-9_]*_SECRET[[:space:]]*=|apiKey[[:space:]]*[:=])'

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
# Whether a plugin runs on NixOS is decided by its runtime files, not by its
# tests, benchmarks, docs or Makefile (the security rules above still scan
# those). The NixOS rules below see TEXT/BIN_EXEC without them; both are
# restored after this section.
NIX_SKIP='/(tests?|specs?|fixtures|benchmarks?|docs)/|/(GNUm|M|m)akefile$'
SEC_TEXT=("${TEXT[@]}"); SEC_BIN=("${BIN_EXEC[@]}")
TEXT=(); for f in "${SEC_TEXT[@]}"; do [[ ${f#"$TARGET"} =~ $NIX_SKIP ]] || TEXT+=("$f"); done
BIN_EXEC=(); for f in "${SEC_BIN[@]}"; do [[ ${f#"$TARGET"} =~ $NIX_SKIP ]] || BIN_EXEC+=("$f"); done

# nixarchy turns envfs on for every machine (modules/nixos.nix): /bin and
# /usr/bin resolve any command on PATH. Nothing else under /usr exists, and
# /opt does not either, so only those paths are blockers.

# fhs-path (blocker): /usr/share (so /usr/share/omarchy: $OMARCHY_PATH is a
# store path), /usr/lib, /opt. envfs does not cover these.
scan NIX fhs-path \
  '/usr/share/[A-Za-z]|/usr/lib(64)?/|(^|[^A-Za-z0-9_.~])/op[t]/' "$NIX_CODE"

# fhs-bin (review): /usr/bin/<cmd> works through envfs only if <cmd> is
# installed. /usr/bin/env is the one path NixOS guarantees.
scan NIX fhs-bin '/usr/s?bin/[A-Za-z]' "$NIX_CODE" '/usr/bin/env'

# fhs-shebang (review): #!/bin/bash and the like run through envfs if the
# interpreter is installed. #!/bin/sh and #!/usr/bin/env are always fine.
# (scan() skips # lines, so this reads line 1 itself.)
for f in "${TEXT[@]}"; do
  first=$(head -n1 -- "$f" 2>/dev/null)
  if [[ $first =~ ^\#![[:space:]]*/(usr/)?bin/(bash|zsh|fish|python[0-9.]*|node|perl)([[:space:]]|$) ]]; then
    emit NIX fhs-shebang "${f#"$TARGET"/}:1" "$(cut -c1-200 <<<"$first")"
  fi
done

# imperative-pkg (review): Arch package managers, or Omarchy's pacman wrapper,
# in code. On nixarchy these do not exist or refuse, so a dependency check or
# an install hint built on them is wrong. Docs (.md, .json) are not code.
# (Bracketed letters: see the spelling rule above FINDINGS.)
scan NIX imperative-pkg '\b(pac[m]an|y[a]y|par[u]|makepk[g])\b|omarchy[- ]pkg[- ](add|install)' "$NIX_CODE"

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
    done < <(code_lines "$f" | grep -nE 'pip[0-9]?[[:space:]]+install')
  fi
  while IFS= read -r hit; do
    emit NIX global-lang-install "$rel:${hit%%:*}" "$(sed -E 's/^[[:space:]]+//' <<<"${hit#*:}" | cut -c1-200)"
  done < <(code_lines "$f" | grep -nE 'npm[[:space:]]+(i|install)[[:space:]]+(-g|--global)')
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
TEXT=("${SEC_TEXT[@]}"); BIN_EXEC=("${SEC_BIN[@]}")

# =============================================================================
# MANIFEST VALIDATION  (same check the shell enforces before loading)
# =============================================================================
if [[ -x "$OMARCHY_BIN/omarchy-plugin-validate" ]]; then
  if vout=$("$OMARCHY_BIN/omarchy-plugin-validate" "$TARGET" 2>&1); then
    printf 'VALIDATE\tok\t%s\n' "$(clean "manifest passes the shell's schema checks")"
  else
    printf 'VALIDATE\tfail\t%s\n' "$(clean "$vout" | cut -c1-200)"
  fi
else
  printf 'VALIDATE\tskip\t%s\n' "$(clean "omarchy-plugin-validate not present in sandbox")"
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
