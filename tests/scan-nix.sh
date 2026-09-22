#!/usr/bin/env bash
#
# tests/scan-nix.sh — self-check for the scanner's NixOS rules (and the A4
# rule that code in docs/ is still scanned). Builds a fixture plugin, runs the
# scanner on it unsandboxed (it only reads files), and asserts each expected
# record. Prints "ok" and exits 0, or names the first failure and exits 1.
set -uo pipefail

SCANNER="$(cd -- "$(dirname -- "$0")/.." && pwd)/lib/omarchy-plugin-scan.sh"
FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/docs"

echo '{"id":"t.fixture"}' >"$FX/manifest.json"
printf '#!/usr/bin/bash\npacman -S foo\n' >"$FX/run.sh"
printf 'import QtQuick\nItem { property string p: "/usr/share/omarchy/bin/x" }\n' >"$FX/Widget.qml"
printf 'import QtQuick\nItem { Component.onCompleted: eval(x) }\n' >"$FX/docs/Evil.qml"
printf '#!/usr/bin/env bash\n/usr/bin/env jq . f.json\n' >"$FX/ok.sh"
printf '#!/bin/sh\nsudo tee /etc/foo.conf <x\npip install requests\nnpm install -g left-pad\n' >"$FX/setup.sh"
printf '#!/bin/sh\ncurl -L -o tool https://example.com/tool\nchmod +x tool\n' >"$FX/fetch.sh"

OUT=$(bash "$SCANNER" "$FX")

has() {  # has <kind> <id> <file:line>
  grep -qP "^$1\t$2\t$3\t" <<<"$OUT" || { echo "FAIL: expected $1 $2 at $3"; echo "$OUT"; exit 1; }
}
has NIX fhs-shebang         'run\.sh:1'
has NIX imperative-pkg      'run\.sh:2'
has NIX fhs-path            'Widget\.qml:2'
has NIX etc-write           'setup\.sh:2'
has NIX global-lang-install 'setup\.sh:3'
has NIX global-lang-install 'setup\.sh:4'
has NIX download-exec       'fetch\.sh:2'
has FIND dynamic-code-load  'docs/Evil\.qml:2'

# /usr/bin/env and #!/usr/bin/env are what NixOS guarantees: no NIX record.
if grep -qP '^NIX\t[^\t]+\tok\.sh:' <<<"$OUT"; then
  echo "FAIL: ok.sh should produce no NIX record"; grep -P '\tok\.sh:' <<<"$OUT"; exit 1
fi
# #!/bin/sh exists on NixOS: not an fhs-shebang.
if grep -qP '^NIX\tfhs-shebang\t(setup|fetch)\.sh:' <<<"$OUT"; then
  echo "FAIL: #!/bin/sh must not be flagged"; exit 1
fi
echo ok
