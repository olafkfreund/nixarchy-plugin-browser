# Nixarchy Plugin Browser + Auditor

A fork of the Omarchy Plugin Browser for **nixarchy** (Omarchy on NixOS). It
uses NixOS paths throughout and does not run on Arch Omarchy.

Browse the Omarchy plugin marketplace from a terminal, and **audit any plugin in
a sandbox before it touches your shell**.

Omarchy shell plugins run as **unsandboxed code inside the long-lived
`omarchy-shell` process**, with everything your user account can reach
(`$OMARCHY_PATH/shell/README.md`). `omarchy plugin add` clones a repo,
validates its manifest, and lands it **disabled** so you can read it first — but
it clones whatever is at the repo's mutable `HEAD`. The marketplace verifies an
*exact commit*, and its own docs are explicit that the install command is **not
commit-bound** (`VERIFICATION.md` → "Installation boundary"). This tool closes
that gap: it clones into a throwaway sandbox, pins the checkout to the
marketplace's **verified** commit, statically scans it, and only then — if you
ask — hands that reviewed checkout to `omarchy plugin add`.

## What you get

| Tool | What it does |
|------|--------------|
| `omarchy-plugin-browser` | Searchable TUI over the live marketplace catalog (`plugins.omarchy.org`). Never runs marketplace code — it reads names, authors, tags, verification status, and the install command as plain text. |
| `omarchy-plugin-audit` | Clones a plugin into a `bwrap` sandbox with no network and an empty home, pins to the verified commit, greps for hostile patterns, runs the shell's own manifest validator, and prints a verdict. Optionally installs the vetted checkout (disabled). |
| Bar widget | A puzzle-piece button in the bar that opens the browser in a terminal. A thin launcher; all the logic lives in the two scripts above. |

## Install

```bash
./install.sh            # symlinks the two CLI tools into ~/.local/bin
./install.sh --plugin   # also registers the bar widget (installed DISABLED)
```

Requires `git jq curl file gum` (all in nixarchy's base system) and `bwrap`,
which the auditor refuses to run without:

```bash
nixarchy pkg add bubblewrap && nixarchy apply
```

Reverse everything with `./uninstall.sh`.

### Moving from the old plugin id

Versions before 0.3.0 used the upstream id `io.github.modpunk.plugin-browser`.
The id changed with the fork, so an old install does not update itself. Move it
once:

```bash
omarchy plugin remove io.github.modpunk.plugin-browser
./install.sh --plugin
omarchy plugin enable io.github.olafkfreund.nixarchy-plugin-browser
```

### Updates

About once every six hours the bar button fetches this repository's
`manifest.json` (one small HTTPS request, no personal data). If a newer version
is out, a dot appears on the button and the next click shows what changed, from
`CHANGELOG.md`. *Update…* opens a terminal that runs `omarchy plugin update`
(it shows the diff and asks), then `install.sh` (asks again). *Later* hides
that version. Set `"update_check": false` in
`~/.config/nixarchy-plugin-browser/config.json` to turn the check off. By hand:

```bash
omarchy plugin update io.github.olafkfreund.nixarchy-plugin-browser
~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser/install.sh
```

See [docs/update-alerts.md](docs/update-alerts.md) for how it is built.

## Use

```bash
omarchy-plugin-browser                 # search, preview, audit, copy-install
omarchy-plugin-audit crmne.hyprmoncfg  # audit a marketplace id (pins to verified)
omarchy-plugin-audit https://github.com/acme/omarchy-weather.git
omarchy-plugin-audit ~/.config/omarchy/plugins/some.plugin   # re-audit an installed one
omarchy-plugin-audit <id> --head       # audit upstream HEAD instead of the verified commit
omarchy-plugin-audit <id> --install    # install the audited checkout (disabled), pinned
omarchy-plugin-audit <id> --json       # machine-readable report
```

Exit codes: `0` clean · `10` review-required · `20` findings · `2` usage · `3` scan error.

## How the audit works — the corrected step list

The pseudocode this repo started from had the right instinct (sandbox, scan,
never auto-install) but several wrong facts. Here is the flow as actually built,
against the real Omarchy 4.x plugin system:

1. **Resolve the target.** A marketplace id or repo URL is looked up in the
   public catalog (`https://plugins.omarchy.org/catalog.json`, cached for an
   hour) to recover its repo and, crucially, its **verified commit**. A local
   folder is audited in place.
2. **Refuse dangerous URLs** with the same `omarchy-git-url-check` guard the
   real `omarchy plugin add` uses, so a URL naming a git transport helper
   (`ext::…`) can never run a command at clone time.
3. **Clone hardened, don't pin blindly.** `git clone` with `core.symlinks=false`
   and `core.hooksPath=/dev/null`, no submodule recursion, no credential
   prompts. Check out the **verified commit** by default; `--head` opts into
   upstream HEAD; the report always says how many commits upstream is *past* the
   verified snapshot, because that newer code is covered by nothing.
4. **Scan inside `bwrap`, not just "next to" it.** The sandbox has a read-only
   view of the checkout, and of `/nix/store` and `/run/current-system/sw` (where
   every NixOS tool, including the shell's validator, lives). It also has
   `--clearenv` with `PATH=/run/current-system/sw/bin`, an empty tmpfs home (so
   `~/.ssh` and friends are absent), and `--unshare-all` (no network, no host
   PID namespace). Without `bwrap` the audit stops, unless you pass
   `--no-sandbox`. The scanner reads files as text and **never executes plugin
   code.**
5. **Grep for the marketplace's own finding set**, by the same names, so results
   are comparable: `curl-pipe-shell`, `cargo-git-unpinned`,
   `remote-git-execution-unpinned`, `sudoers-dangerous-passwordless-command`,
   `privileged-process-control-from-shared-temp` — plus two the shell context
   adds: reads of credential paths, and dynamic code loading
   (`eval`, the `Function` constructor, QML built from a string, a component
   fetched from a remote URL). Capabilities (installer, package-manager,
   privilege, service-management, sudoers-modification, remote-build, a bundled
   ELF/PE/Mach-O binary) are surfaced for review but are not, by themselves, a
   block.
6. **Run the shell's real validator** (`omarchy-plugin-validate`) inside the
   sandbox — the same schema and no-symlink checks the shell enforces before it
   will load anything. Tracked symlinks (which `core.symlinks=false` would
   otherwise turn into plain files) are detected from git's index and reported;
   `--install` refuses them.
7. **Decide and report.** Findings → `needs-fixes`; capabilities only →
   `review-required`; neither → `passed`. The verdict is triage, not a
   safety proof — the tool says so, every time.
8. **Only then, optionally install.** `--install` gives the audited checkout a
   branch at the exact scanned commit, runs `omarchy plugin add <dir> --yes`
   (which lands it **disabled**), points `origin` back at upstream so
   `omarchy plugin update` still works, and verifies the installed `HEAD` equals
   the audited commit. It **never enables** the plugin or edits your bar; it
   prints the `omarchy plugin enable` command for you to run.

### Why not signature verification?

The earlier draft proposed GPG/minisign. The Omarchy marketplace does not sign
plugins, and `minisign` isn't present here. The real trust root is **TLS to the
GitHub-Pages-hosted catalog plus the commit SHA**: the catalog records the exact
verified commit, and pinning to it is what "verified" can actually mean today.

## What this is not

This is grep-grade static triage. It does not do data-flow analysis, it does not
execute or sandbox the running plugin (Omarchy runs enabled plugins natively,
outside any sandbox — the sandbox here is only for *inspection*), and a `passed`
verdict is not a guarantee. **Read the source of anything you enable.** The
sandbox protects the *audit*, not your desktop once you turn a plugin on.

## Layout

```
manifest.json                 bar-widget manifest (schemaVersion 1)
BarWidget.qml                 the bar button (launches the browser)
bin/omarchy-plugin-browser    marketplace TUI
bin/omarchy-plugin-audit      sandboxed auditor / installer
lib/omarchy-plugin-scan.sh    the in-sandbox scanner
install.sh · uninstall.sh     symlink the tools; optionally register the widget
```

## License

MIT.
