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
