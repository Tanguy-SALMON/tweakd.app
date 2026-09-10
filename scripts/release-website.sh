#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Tweakd Website Release Script
#
# Deploys web/ (the static marketing/docs site) to Cloudflare Pages,
# production only. No build step — web/index.html is plain HTML.
#
# The deploy directory is passed to wrangler on the command line below, NOT
# configured in the Cloudflare dashboard — so moving the site is a change here
# and nowhere else.
#
# This used to deploy docs/, back when that one folder held both the website and
# the Markdown reference. That published every .md file alongside the page; now
# the site lives in web/ and only the page ships.
#
# Usage:
#   ./scripts/release-website.sh              # deploy web/ to production
#   ./scripts/release-website.sh --dry-run    # show what would happen
#
# Prod URL:    https://tweakd-app.pages.dev  (attach tweakd.app as a
#              custom domain in the Cloudflare dashboard once its DNS
#              zone is set up — Pages > tweakd-app > Custom domains)
# Project:     tweakd-app (Cloudflare Pages, created via
#              `wrangler pages project create tweakd-app`)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

header()  { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; echo -e "${CYAN}  $1${RESET}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
step()    { echo -e "\n${BOLD}$1${RESET}"; }
info()    { echo -e "    ${DIM}$1${RESET}"; }
success() { echo -e "    ${GREEN}$1${RESET}"; }
fail()    { echo -e "\n    ${RED}ERROR: $1${RESET}\n"; exit 1; }

PROJECT_NAME="tweakd-app"
DOMAIN="tweakd.app"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      echo "Usage: ./scripts/release-website.sh [--dry-run]"
      exit 0
      ;;
    *) fail "Unknown argument: $arg" ;;
  esac
done

run() {
  if $DRY_RUN; then
    echo -e "    ${DIM}\$ $*${RESET}"
  else
    "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$ROOT/web"

header "Tweakd Website Release"
echo -e "    ${DIM}Project:${RESET}  ${CYAN}${PROJECT_NAME}${RESET}"
echo -e "    ${DIM}Source:${RESET}   ${WEB_DIR}"
echo -e "    ${DIM}Dry run:${RESET}  $( $DRY_RUN && echo -e "${YELLOW}yes${RESET}" || echo -e "${DIM}no${RESET}" )"

if $DRY_RUN; then
  echo -e "\n${YELLOW}DRY RUN — nothing will be deployed.${RESET}"
fi

step "Preflight checks"

if ! command -v npx >/dev/null 2>&1; then
  fail "npx not found. Install Node.js."
fi
success "npx available"

if [ ! -d "$WEB_DIR" ]; then
  fail "Website directory not found: $WEB_DIR"
fi
success "Website directory OK ($WEB_DIR)"

if [ ! -f "$ROOT/wrangler.toml" ]; then
  fail "wrangler.toml not found — the R2 binding for /api/download lives there."
fi
success "wrangler.toml present (R2 binding for /api/download)"

if [ ! -f "$ROOT/functions/api/download.js" ]; then
  fail "functions/api/download.js not found — the Download button would 404."
fi
success "Download Function present"

if ! npx wrangler whoami >/dev/null 2>&1; then
  fail "Not logged in to Cloudflare. Run: npx wrangler login"
fi
success "Cloudflare auth OK"

step "Deploy to production"
info "→ https://${PROJECT_NAME}.pages.dev (+ ${DOMAIN} once the custom domain is attached)"
# Deploy from the repo root, with no directory argument: wrangler.toml supplies
# `pages_build_output_dir = "web"` AND the R2 binding the download Function
# needs. Passing the directory here instead would deploy the same files with no
# bindings, and /api/download would 500 with `env.DOWNLOADS` undefined.
cd "$ROOT"
run npx wrangler pages deploy --project-name="$PROJECT_NAME" --branch=main --commit-dirty=true

success "Deployed"

echo ""
header "Website release complete"
echo -e "    ${GREEN}Production:${RESET} https://${PROJECT_NAME}.pages.dev"
echo -e "    ${GREEN}Custom domain:${RESET} https://${DOMAIN} (attach in Cloudflare dashboard: Pages > ${PROJECT_NAME} > Custom domains)"
echo ""
