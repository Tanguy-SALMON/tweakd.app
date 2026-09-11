# Tweakd — project notes

## Repo layout

```
app/        Swift package and Resources (the build output lands in app/build/)
app/VERSION single line, e.g. 0.9.3 — the build stamps this into the bundle
web/        index.html, privacy.html, terms.html — the public site
docs/       the Markdown reference (TWEAKS.md, TOOLS.md, SAFETY.md, …)
scripts/    build.sh (entry point), release.sh (entry point), release-site.sh,
            release-download.sh, release-website.sh, package-dmg.sh,
            make_icon.swift
scripts/shot/  capture.sh (app screenshots), snap.swift (html->png), winlist.swift
marketing/  shots/ and hero/ — presentation assets, nothing the build needs
```

Build: `scripts/build.sh --no-launch` (release) — `scripts/build.sh` also launches.

## The website has TWO front doors, deployed two different ways

| URL | Served by | Config |
|---|---|---|
| `https://tweakd.app` | Worker **`still-pond-7677`** (a Workers *custom domain*) | `wrangler.worker.toml` |
| `https://tweakd-app.pages.dev` | Pages project **`tweakd-app`** | `wrangler.toml` |

**`tweakd.app` is NOT a Pages custom domain.** `wrangler pages deploy` does
nothing to it — that is why it served the 2026-07-30 build (v0.4.0) for six weeks
while pages.dev was current, and why `wrangler pages project list` shows
`tweakd.app` attached to no project. It was found with:

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACC/workers/domains?service=still-pond-7677"
```

`scripts/release-website.sh` now deploys **both**, and fails preflight if either
config is missing. Never deploy just one.

**When reporting a deploy, verify `tweakd.app`** — that is the URL people use.

Cloudflare account: `tanguy.salmon@gmail.com`, account ID
`6c8d37ea88675da2282af94b7438b14c`. Zone `tweakd.app`:
`0b7e57a06696b1e502ae9928802bc819`. The stored wrangler OAuth token
(`~/Library/Preferences/.wrangler/config/default.toml`) can read Workers and
Pages via the API but **not** DNS.

## Downloads — R2, not a file in the repo

The Download button points at **`/api/download`**, a Pages Function
(`functions/api/download.js`) bound to the R2 bucket **`tweakd-downloads`**.

- Objects are named **`Tweakd-<version>.dmg`**. The Function lists the bucket
  and serves the **highest version** it finds, so publishing is a single upload
  with no pointer, manifest or database row to keep in sync.
- The `.dmg` is **never committed** — `dist/` is gitignored. It is a build
  artifact of one `app/VERSION`.
- `wrangler.toml` at the repo root exists **for the R2 binding**. Without it the
  Function has no `env.DOWNLOADS` and every download 500s. That is also why
  `release-website.sh` deploys with **no directory argument** — the config
  supplies `pages_build_output_dir = "web"`. Passing `web` explicitly deploys
  the same files with no bindings.
- Pages routes each HTTP method to its own export. The Function exports both
  `onRequestGet` and `onRequestHead`; without the HEAD export, HEAD falls
  through to the static handler and answers with the homepage.

## Signing and notarisation

The `.dmg` is public, so it must survive Gatekeeper on a Mac that has never
seen it. Ad-hoc signing (`codesign --sign -`) does not — it produces
*"Tweakd is damaged and can't be opened"*, which reads like a corrupt download
and is unfixable by the person seeing it.

- **Team `BXH6425K7L`**, cert *Developer ID Application: Tanguy SALMON*. This is
  a different certificate from the *Apple Distribution* one used for the App
  Store; only Developer ID works outside the store.
- `scripts/build.sh` picks the identity out of the keychain automatically and signs
  with `--options runtime --timestamp`. **Hardened Runtime is mandatory for
  notarisation and can only be set at signing time.** With no cert present it
  falls back to ad-hoc and says so. Force a lane with `TWEAKD_SIGN_IDENTITY`.
- The only entitlement is `com.apple.security.automation.apple-events`, needed
  because Disk Cleanup shells out to `osascript … "tell application \"Finder\"
  to empty trash"` and TCC attributes that event to us, not to osascript.
  Everything privileged runs as a *child process*, so library validation and the
  executable-memory exceptions are not required — do not add them.
- `scripts/package-dmg.sh` signs the image, submits it with `notarytool
  --wait`, then **staples** the ticket. Stapling is what lets a first launch
  work offline; without it the receiving Mac must reach Apple. Stapling the
  `.dmg` covers the `.app` inside it.
- `scripts/release-download.sh` refuses to upload a `.dmg` with no ticket
  (`stapler validate` + `spctl --assess`). An un-notarised image uploads
  perfectly happily and only fails days later on someone else's machine.

One-time credential setup. The Apple ID that owns team `BXH6425K7L` is
**`tanguy.salmon@gmail.com`** — the same account as Cloudflare, *not* the
`@hthai.co.th` address this Mac uses for iCloud. The password is an
app-specific password from **appleid.apple.com** (not developer.apple.com, and
no App ID registration is involved — App IDs are an App Store concept).
Stored in the keychain, never in the repo — there is no file to edit, and
the profile name is **case-sensitive** (`Tweakd`, not `tweakd`):

```bash
xcrun notarytool store-credentials "Tweakd" \
  --apple-id "tanguy.salmon@gmail.com" --team-id "BXH6425K7L" \
  --password "<app-specific password>"
```

`scripts/package-dmg.sh --no-notarize` skips the Apple round-trip for local
testing. The result must not be published.

Release — one entry point, same shape as the SQLAgent/MyD1 scripts:

```bash
scripts/release.sh                 # bump version, app, then both front doors
scripts/release.sh --apps-only     # .dmg → R2, no website
scripts/release-site.sh            # website only (shim for --web-only)
scripts/release.sh --dry-run       # show everything, execute nothing
```

`release.sh` bumps the patch digit in `app/VERSION` **and** the version pills in
`web/index.html` in the same step, then verifies they agree. Those two drifting
apart is what let the site advertise v0.4.0 for six weeks, and CI now fails on
it. `--no-bump` re-ships the current version.

The work still lives in the two scripts it calls, which remain runnable
directly:

```bash
scripts/release-download.sh     # build → dist/Tweakd-<v>.dmg → R2, then verifies
scripts/release-website.sh      # site + Function, both front doors
```

`release-download.sh` finishes by HEAD-ing the live endpoint and comparing
`X-Tweakd-Version` to `app/VERSION` — an upload can succeed while the Function
is broken, so trusting the upload alone is not a check.

## Site conventions

- No public GitHub repo. The site must not link to one — the "View source"
  button and the footer/legal-page GitHub links were removed on 2026-09-10, and
  privacy/terms name email as the only contact route.
- The download button points at `/api/download` (see above), not a static file.
- The hero pill quotes the catalog size. Verify it against
  `app/Sources/Tweakd/Models/TweakCatalog.swift` before changing it
  (`static let all` and `static let actions`) — it was wrong once already.

## Marketing assets

`marketing/` at the repo root holds anything used to *present* Tweakd and
nothing the app or site needs to run — `shots/` for screenshots, `hero/` for
hero art. The test: if removing it breaks a build or a page, it does not belong
there. `app/Resources/AppIcon.*` is a build input and `web/icon.png` is served
to browsers, so both stay where they are.

Screenshots are captured from a real running build:

```bash
scripts/shot/capture.sh --list            # window IDs currently on screen
scripts/shot/capture.sh --name dashboard  # -> marketing/shots/dashboard@2x.png
```

**Screen Recording denial is silent.** `screencapture` writes the desktop
wallpaper and exits 0, so never trust its exit code — a real window capture is
exactly 2x the size `--list` reports, which is why `capture.sh` prints the
dimensions.

Screenshots are committed (they depend on live system state and cannot be
reproduced on demand); rendered hero art is gitignored (one command rebuilds it
from `hero.html` + a screenshot). Only the resized copy in `web/` ships —
`wrangler` uploads `web/` and nothing else.

## Gotchas

- `launchctl bootout` returns `150` under SIP. Chain daemon disables with `;` and
  a trailing `true`, never `&&`, or a tweak that worked reports as failed. See
  `docs/SAFETY.md`.
- `osascript … with administrator privileges` buffers stdout until the process
  exits, so it can never stream. Live sampling needs the passwordless `sudo -n`
  lane — `CommandRunner.streamAdmin`.
- This machine's shell has a custom `du` that dumps file contents. Call
  `/usr/bin/du` explicitly.
