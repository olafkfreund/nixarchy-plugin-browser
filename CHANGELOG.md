# Changelog

The bar button reads the newest sections of this file to tell you what changed
when an update is available. Keep one short line per bullet.

## 0.4.0

- The browser runs inside the shell: a full-screen, keyboard-driven panel on Super+Alt+U
- Opening a plugin shows its security and NixOS verdicts; e / f hand it to your agent, i installs it disabled
- The bar button opens the panel; right-click it for the terminal browser
- Can replace Setup → Plugins → Add Plugin (see the README for the flake lines)
- Installable with Nix: a flake with the plugin, the tools and a keybinding module

## 0.3.0

- Runs on nixarchy: NixOS paths, a sandbox that can see /nix/store, and the manifest check now really runs
- The audit refuses to run without bwrap instead of quietly dropping the sandbox
- Own id and update feed: io.github.olafkfreund.nixarchy-plugin-browser
- Code files in docs/ and test/ folders are scanned too
- Every audit shows whether the plugin will run on NixOS: likely-ok, needs-review or blocked
- nixarchy-plugin-fix (and a browser action) hands the findings to your default agent to explain or fix a copy

## 0.2.2

- The checkout of a remote plugin has the same deadline and size limits as the clone

## 0.2.1

- The clone or copy before the sandbox has a deadline and size and file-count limits

## 0.2.0

- The bar button shows a dot when a new version is out; click it for what changed and a one-click update
- `lib/update.sh check | dismiss | run` from the command line

## 0.1.0

- Bar button that opens the marketplace browser; every install routes through the sandboxed auditor
- The catalog download is bounded and written safely; the launcher uses no PATH lookups or shell strings
