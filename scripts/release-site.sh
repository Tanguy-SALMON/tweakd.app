#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Tweakd website release wrapper
#
# Thin shim that delegates to release.sh with --web-only. Deploys BOTH front
# doors — the Worker serving tweakd.app and the Pages project serving
# tweakd-app.pages.dev — because deploying one without the other is how
# tweakd.app sat on a six-week-old build.
#
# Examples:
#   ./scripts/release-site.sh              # deploy the website
#   ./scripts/release-site.sh --dry-run    # show what would happen
#
# No version bump: the site advertises whatever app/VERSION already says. To
# ship a new app version use ./scripts/release.sh.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
exec "$(dirname "$0")/release.sh" --web-only "$@"
