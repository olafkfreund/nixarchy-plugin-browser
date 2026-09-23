---
title: What this is
---

# nixarchy.plugin-browser

A way to add an Omarchy shell plugin **after** you have seen what it does.

Omarchy's plugins are panels, bar widgets and menus that run inside the
desktop shell. They are not sandboxed once they run: a plugin is code in the
long-lived `omarchy-shell` process, with everything your user account can
reach. The marketplace at plugins.omarchy.org lists thousands of them, and
most are written for Arch.

This plugin is the step between finding one and running it:

- it **searches the whole marketplace** from the keyboard, with each
  plugin's preview image;
- it **audits** a plugin in a bubblewrap sandbox at the commit the
  marketplace verified, and says what it found: a security verdict, and a
  NixOS verdict;
- it **installs it disabled**, pinned to the audited commit;
- when a plugin won't run on NixOS, it **hands the findings to your
  agent**, to explain them or fix a copy.

On nixarchy it is the panel behind **Setup ▸ Plugins ▸ Add Plugin**.

## The pages

| Page | What it covers |
|---|---|
| [Getting started](getting-started) | on nixarchy it is already there; on other NixOS machines, the flake |
| [The panel](the-panel) | searching, the details, and every key |
| [The audit](the-audit) | the sandbox, both verdicts, and what each rule means |
| [Asking your agent](the-agent) | `e` and `f`, what the agent gets, and the risk that remains |
| [Installing a plugin](installing) | `i`, disabled installs, and adding by URL |
| [Previews and privacy](previews-and-privacy) | what is fetched, from where, and how to turn previews off |
| [From a terminal](from-a-terminal) | the TUI, `omarchy-plugin-audit` and `nixarchy-plugin-fix` |
| [Troubleshooting](troubleshooting) | the few things that go wrong, and why |

## What it is not

The audit is static triage: it reads files and matches patterns. It does
not run the plugin, and a `passed` verdict is not a guarantee. The sandbox
protects the *audit*, not your desktop once you turn a plugin on. Read the
source of anything you enable.
