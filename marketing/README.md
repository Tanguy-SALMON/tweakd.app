# marketing/

Everything used to *present* Tweakd, and nothing the app or the website needs
in order to run.

```
marketing/
  shots/      app screenshots, captured from a real running build
  hero/       hero and social art: the .html source next to its rendered .png
```

## What belongs here

- Product screenshots
- Hero images, social/OG cards, App Store-style art
- Copy drafts, launch notes, ad text

## What does not

| File | Where it lives | Why |
|---|---|---|
| `app/Resources/AppIcon.*` | `app/` | Build input — `build.sh` compiles the iconset into the bundle |
| `web/icon.png` | `web/` | Served to browsers at runtime |
| Anything the site loads | `web/` | `wrangler` uploads `web/`, not this folder |

The rule: if removing it breaks a build or a page, it is not marketing.

## Taking screenshots

The app must already be running — a window caught mid-launch shows empty panes
and a spinner.

```bash
scripts/build.sh                              # build and launch
scripts/shot/capture.sh --list            # what is on screen
scripts/shot/capture.sh --name dashboard  # → marketing/shots/dashboard@2x.png
```

`capture.sh` picks the largest layer-0 window, so an About or Settings panel
sitting open does not get captured instead of the main window. To shoot a
different view, navigate there in the app and run it again with a new `--name`.

**Screen Recording permission is required** for whichever terminal you run it
from (System Settings → Privacy & Security → Screen Recording). Denied, macOS
does not error: `screencapture` writes the desktop wallpaper and exits 0. That
is why `capture.sh` prints the pixel dimensions — a window capture is exactly
2x the window size reported by `--list`; anything the size of your display is a
denied capture, not a screenshot.

## Rendering hero art

`hero/hero.html` is rendered by WebKit, so it uses real fonts and real CSS
rather than an approximation drawn by hand.

```bash
swift scripts/shot/snap.swift marketing/hero/hero.html \
  marketing/hero/hero@2x.png 1600 900
```

The last two numbers are CSS pixels; scale defaults to 2, so that writes
3200x1800. The background is transparent so the art composites onto any page
colour.

## A note on size

Screenshots are large, and git keeps every version of them forever — a 3 MB
PNG re-captured ten times is 30 MB in the repo that no `git rm` will reclaim.

The rule is whether the file can be reproduced on demand:

- **Screenshots are kept.** They depend on live system state — a particular
  window size, 37 tweaks applied, that sparkline — and re-running `capture.sh`
  tomorrow gives a different picture. They stay a few hundred KB each.
- **Rendered hero art is not.** `hero@2x.png` is fully derived from
  `hero.html` plus a screenshot, and comes back byte-for-byte from one command.
  At ~4 MB a copy, re-rendered on every copy change, it is gitignored.
- Do not commit 5K exports or raw video either — generate them when a store
  listing actually needs one.
