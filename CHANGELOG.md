# Changelog

The bar button reads the newest sections of this file to tell you what changed
when an update is available. Keep one short line per bullet.

## Unreleased

- A config file that exists but cannot be read turns the update check off, as "update_check": false does (#21)

## 0.5.1

- The audit can no longer be fooled by a file name that forges a scan result
- No control characters from a plugin or the catalog reach your terminal
- Only https (catalog) or https, ssh, git@ and file:// (typed) URLs are cloned
- Symlinks in a plugin are always listed and block --install, never followed
- A local --install refuses uncommitted changes: it installs exactly what was scanned
- The scanner reads extensionless and .py files and no longer skips real code as comments
- Invalid plugin ids and malformed catalog commits are refused before use
- The audit passes its own plugin honestly: no findings from its own patterns
- Cancelling an audit also stops its clone
- One bad marketplace entry no longer empties the plugin list
- The update terminal now offers the shell restart the panel needs
- The update check is HTTPS-only
- The terminal browser copies an install command built from the plugin's GitHub repo
- The panel is a share of your screen and uses your theme's font sizes, so it fits laptops and 4K alike (#16)
- Text is drawn at its real size, no longer scaled up, so it is as sharp as the bar
- c copies "omarchy plugin add <repo>", built from the checked GitHub URL and shown in the pane first (#17)
- Detail keys act only without Ctrl, Alt, Super or Shift, so Ctrl+F no longer starts the fix agent
- Esc or closing the panel stops the running audit; an audit gives up after 5 minutes (needs #15)
- e, f and o close the panel, so the terminal or browser they open gets the keyboard
- Both confirms before an agent runs or a workspace is deleted now default to No
- Nix: `nix run …#cli` works, and `homeModules.default` is exported

## 0.5.0

- Opening a plugin shows its screenshot from the marketplace, fetched and checked safely, cached
- Turn previews off with "previews": false in ~/.config/nixarchy-plugin-browser/config.json
- Enter right after typing a search now opens the plugin you searched for

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
