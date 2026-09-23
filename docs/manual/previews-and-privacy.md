---
title: Previews and privacy
---

# Previews and privacy

## What is fetched, and when

Only when you use the panel, and only from **plugins.omarchy.org**:

- **the catalog** (about 8 MB), when the panel opens, cached for an hour in
  `~/.cache/omarchy-plugin-audit/`;
- **one preview image,** for the plugin you open, if it has one (3,379 of
  them do), cached in `~/.cache/omarchy-plugin-audit/previews/`, up to
  50 MiB.

So plugins.omarchy.org learns which plugins you look at: the same site the
catalog comes from. Nothing is fetched in the background, and the list
itself never loads images.

The audit clones the plugin's own repository (usually GitHub), at the
commit the marketplace verified.

## How a preview is checked

The shell never downloads or decodes anything straight from the network. A
small script fetches the 720×405 thumbnail and checks it first:

- the address must be
  `https://plugins.omarchy.org/assets/img/plugins/<name>.webp|png`, and
  nothing else;
- the file must be at most 2 MiB, arriving within 15 s;
- the file's own first bytes must say WebP or PNG, matching its name.

Only then does the panel show it, decoded at no more than 720×405.

## Turning previews off

In `~/.config/nixarchy-plugin-browser/config.json`:

```json
{ "previews": false }
```

Nothing is fetched for previews after that, not even from the cache.

## The update check

About every six hours the bar button fetches this repository's
`manifest.json`, to show a dot when a new version is out. It is one small
request with no personal data. `"update_check": false` in the same file
turns it off.
