#!/usr/bin/env bash
#
# release-download.sh — build, package and publish the downloadable .dmg.
#
# The website's Download button points at /api/download, a Pages Function that
# lists the `tweakd-downloads` R2 bucket and streams the highest-versioned
# `Tweakd-<version>.dmg` it finds. So publishing a release is: put the object.
# There is no pointer, manifest or database row to update afterwards.
#
# Usage:
#   scripts/release-download.sh              # build, package, upload, verify
#   scripts/release-download.sh --dry-run
#   scripts/release-download.sh --skip-build # package the existing .app
#
set -euo pipefail

GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'
DIM='\033[2m'; BOLD='\033[1m'; RED='\033[1;31m'; RESET='\033[0m'
header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; echo -e "${CYAN}  $1${RESET}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
step()    { echo -e "\n${BOLD}$1${RESET}"; }
info()    { echo -e "    ${DIM}$1${RESET}"; }
ok()      { echo -e "    ${GREEN}$1${RESET}"; }
fail()    { echo -e "\n    ${RED}ERROR: $1${RESET}\n"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUCKET="tweakd-downloads"
DRY_RUN=false
PKG_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --skip-build) PKG_ARGS+=("--skip-build") ;;
    -h|--help)    echo "Usage: scripts/release-download.sh [--dry-run] [--skip-build]"; exit 0 ;;
    *) fail "Unknown argument: $arg" ;;
  esac
done

run() { if $DRY_RUN; then echo -e "    ${DIM}\$ $*${RESET}"; else "$@"; fi; }

VERSION="$(cat app/VERSION)"
DMG="dist/Tweakd-${VERSION}.dmg"
KEY="Tweakd-${VERSION}.dmg"

header "Tweakd Download Release"
echo -e "    ${DIM}Version:${RESET}  ${CYAN}${VERSION}${RESET}"
echo -e "    ${DIM}Bucket:${RESET}   ${BUCKET}"
echo -e "    ${DIM}Object:${RESET}   ${KEY}"
$DRY_RUN && echo -e "\n${YELLOW}DRY RUN — nothing will be uploaded.${RESET}"

step "Preflight"
command -v npx >/dev/null 2>&1 || fail "npx not found. Install Node.js."
ok "npx available"
npx wrangler whoami >/dev/null 2>&1 || fail "Not logged in to Cloudflare. Run: npx wrangler login"
ok "Cloudflare auth OK"

step "Package"
scripts/package-dmg.sh "${PKG_ARGS[@]+"${PKG_ARGS[@]}"}"
[ -f "$DMG" ] || fail "Expected $DMG, not found"
ok "$DMG"

step "Upload to R2"
info "→ r2://${BUCKET}/${KEY}"
run npx wrangler r2 object put "${BUCKET}/${KEY}" \
    --file "$DMG" \
    --content-type application/octet-stream \
    --remote
ok "Uploaded"

if ! $DRY_RUN; then
  step "Verify"
  # HEAD the live endpoint rather than trusting the upload: the Function has to
  # be able to see the binding, list the bucket and pick this version. Any of
  # those can be broken while the upload itself succeeded.
  URL="https://tweakd-app.pages.dev/api/download"
  SERVED="$(curl -sSI "$URL" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-tweakd-version"{print $2}')"
  if [ "$SERVED" = "$VERSION" ]; then
    ok "${URL} serves ${SERVED}"
  else
    echo -e "    ${YELLOW}${URL} reports '${SERVED:-nothing}', expected ${VERSION}.${RESET}"
    info "If you have not deployed the site since adding the Function, run scripts/release-website.sh."
  fi
fi

echo ""
header "Download release complete"
echo -e "    ${GREEN}Download:${RESET} https://tweakd-app.pages.dev/api/download"
echo ""
