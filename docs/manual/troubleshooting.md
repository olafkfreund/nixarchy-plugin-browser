---
title: Troubleshooting
---

# Troubleshooting

## Add Plugin still opens the Git-URL prompt

Log out and back in. The menu is read from the Omarchy tree your session
started with, so a menu change from an update appears only in a new
session. Restarting the shell is not enough.

## The audit says it can't run without bwrap

The audit refuses to scan outside a sandbox. On nixarchy, bubblewrap comes
with the plugin; on a hand install:

```bash
nixarchy pkg add bubblewrap && nixarchy apply
```

## Super+Alt+U does nothing

nixarchy seeds the key only on new installs. Add it to
`~/.config/hypr/bindings.lua` (see [Getting started](getting-started)).
If the key shows "turned off", the plugin is disabled: enable it in
**Setup ▸ Plugins ▸ Enable Plugin**.

## Something is "not a function" after an update

`omarchy plugin update` reloads a plugin's views but keeps its shared state
from before. Restart the shell once:

```bash
omarchy-restart-shell
```

## The panel closed after I pressed `y`

That is the shell reloading its plugins after the install. The plugin is
installed, and disabled; see [Installing a plugin](installing).

## A plugin shows no preview

Not every plugin has one. If none show, check that previews are not turned
off (see [Previews and privacy](previews-and-privacy)).
