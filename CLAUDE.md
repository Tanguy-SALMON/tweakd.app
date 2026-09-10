# Tweakd — project notes

## Repo layout

```
app/        Swift package + build.sh (produces app/build/tweakd.app)
app/VERSION single line, e.g. 0.9.3 — the build stamps this into the bundle
web/        index.html, privacy.html, terms.html — the public site
docs/       the Markdown reference (TWEAKS.md, TOOLS.md, SAFETY.md, …)
scripts/    make_icon.swift, release-website.sh
```

Build: `app/build.sh --no-launch` (release) — `app/build.sh` also launches.

## The website has TWO live URLs, and they are not the same site

| URL | What it is | Current? |
|---|---|---|
| `https://tweakd-app.pages.dev` | The Cloudflare Pages project **`tweakd-app`**, which `scripts/release-website.sh` deploys to | **Yes** — this is what a deploy updates |
| `https://tweakd.app` | The custom domain. Serves an **older, unrelated deployment** | **No** — stale |

**Deploying does not update `tweakd.app`.** As of 2026-09-10:

- `wrangler pages project list` shows only `tweakd-app.pages.dev` under the
  `tweakd-app` project's domains — `tweakd.app` is **not attached to it**.
- Cache-busted fetches confirm the two serve different HTML: pages.dev is on
  v0.9.3, `tweakd.app` still advertises **v0.4.0**, still shows the removed
  "View source" GitHub button, and 404s on `/privacy.html` and `/terms.html`.
- `tweakd.app`'s nameservers are Cloudflare (`jake`/`lina.ns.cloudflare.com`) and
  it is served by Cloudflare, so it is some other Pages project or Worker on the
  same account.
- Anchors like `https://tweakd.app/#manual` resolve because the *old* page also
  has a `#manual` section — that is not evidence the domain is up to date.

**When reporting a deploy, always state which URL you verified.** Checking
`tweakd.app` will show stale content and is not a valid check of a release.

**To fix (manual, one time):** Cloudflare dashboard → Pages → `tweakd-app` →
Custom domains → add `tweakd.app`. The installed wrangler (4.130.0) has no
`pages domain` subcommand, so this cannot be scripted from here.

Cloudflare account: `tanguy.salmon@gmail.com`, account ID
`6c8d37ea88675da2282af94b7438b14c`.

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

Release, in order:

```bash
scripts/release-download.sh     # build → dist/Tweakd-<v>.dmg → R2, then verifies
scripts/release-website.sh      # site + Function
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

## Gotchas

- `launchctl bootout` returns `150` under SIP. Chain daemon disables with `;` and
  a trailing `true`, never `&&`, or a tweak that worked reports as failed. See
  `docs/SAFETY.md`.
- `osascript … with administrator privileges` buffers stdout until the process
  exits, so it can never stream. Live sampling needs the passwordless `sudo -n`
  lane — `CommandRunner.streamAdmin`.
- This machine's shell has a custom `du` that dumps file contents. Call
  `/usr/bin/du` explicitly.
