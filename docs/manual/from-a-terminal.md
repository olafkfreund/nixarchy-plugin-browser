---
title: From a terminal
---

# From a terminal

Everything the panel does is a command underneath.

## The browser

`omarchy-plugin-browser` is the same browser as a terminal program: search,
preview, audit and copy the install command. A right click on the bar button
opens it.

## The audit

```bash
omarchy-plugin-audit crmne.hyprmoncfg                 # a marketplace id, at its verified commit
omarchy-plugin-audit https://github.com/acme/x.git    # any repository
omarchy-plugin-audit ~/.config/omarchy/plugins/some.plugin   # one you have installed
omarchy-plugin-audit <id> --head       # upstream HEAD instead of the verified commit
omarchy-plugin-audit <id> --install    # install the audited checkout, disabled
omarchy-plugin-audit <id> --json       # the report as JSON, including nixosCompatibility
```

| Exit code | Meaning |
|---|---|
| `0` | passed |
| `10` | review required |
| `20` | needs fixes |
| `2` | usage |
| `3` | the audit could not complete (for example, no `bwrap`) |

## Asking your agent

```bash
nixarchy-plugin-fix <id | git-url | dir>              # asks: explain or fix
nixarchy-plugin-fix crmne.hyprmoncfg --mode explain
```

The same flow as `e` and `f` in the panel; see
[Asking your agent](the-agent).
