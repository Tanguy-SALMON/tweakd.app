#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Tweakd Release Script
#
# Full pipeline: bump version, build, sign, notarize, staple, DMG, upload to
# R2, deploy both website front doors. One entry point, same shape as the
# SQLAgent/MyD1 release script so the muscle memory carries across projects.
#
# Usage:
#   ./scripts/release.sh                 # everything: app + website
#   ./scripts/release.sh --apps-only     # build/sign/notarize/DMG/upload, no website
#   ./scripts/release.sh --web-only      # website only (both front doors)
#   ./scripts/release.sh --dry-run       # show what would happen, execute nothing
#   ./scripts/release.sh --no-bump       # release the current app/VERSION as-is
#
#   ./scripts/release-site.sh            # shim for --web-only
#
# Version bump
# ------------
# Increments the patch digit in app/VERSION and rewrites the version pills in
# web/index.html in the same step. Those two must never disagree: the site
# advertised v0.4.0 for six weeks because nothing tied them together, and CI
# now fails the build if they drift. --no-bump releases app/VERSION unchanged
# (use it to re-ship a version, or when you bumped by hand).
#
# The real work still lives in the two scripts this calls —
# release-download.sh (which refuses to upload an un-notarised .dmg) and
# release-website.sh (which deploys the Worker AND Pages). Running either
# directly is still supported and does the same thing.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'; CYAN='\033[1;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

step_num=0
header()  { echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; echo -e "${MAGENTA}  $1${RESET}"; echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
step()    { step_num=$((step_num + 1)); echo -e "\n${CYAN}[$step_num]${RESET} ${BOLD}$1${RESET}"; }
info()    { echo -e "    ${DIM}$1${RESET}"; }
success() { echo -e "    ${GREEN}$1${RESET}"; }
fail()    { echo -e "\n    ${RED}ERROR: $1${RESET}\n"; exit 1; }

DO_APPS=true
DO_WEB=true
DRY_RUN=false
DO_BUMP=true

for arg in "$@"; do
  case "$arg" in
    --apps-only) DO_WEB=false ;;
    --web-only)  DO_APPS=false; DO_BUMP=false ;;
    --dry-run)   DRY_RUN=true ;;
    --no-bump)   DO_BUMP=false ;;
    -h|--help)
      echo "Usage: ./scripts/release.sh [--apps-only | --web-only] [--dry-run] [--no-bump]"
      echo ""
      echo "  --apps-only   Build, sign, notarize, DMG, upload to R2 (skip website)"
      echo "  --web-only    Deploy both website front doors only (skip the app)"
      echo "  --dry-run     Print what would happen without executing"
      echo "  --no-bump     Release the current app/VERSION without incrementing"
      exit 0
      ;;
    *) fail "Unknown argument: $arg (use --help)" ;;
  esac
done

# ── version bump ─────────────────────────────────────────────────────────────
# app/VERSION and the website pills move together or not at all. Bumping one
# without the other is the exact drift CI is there to catch, so doing it in two
# places by hand is how it went wrong before.
bump_version() {
  local cur new major minor patch
  cur="$(tr -d '[:space:]' < app/VERSION)"
  IFS='.' read -r major minor patch <<< "$cur"
  new="${major}.${minor}.$((patch + 1))"
  info "${cur} → ${new}"

  if $DRY_RUN; then
    info "\$ printf '%s\\n' ${new} > app/VERSION"
    info "\$ sed -i '' 's/v${cur}/v${new}/g' web/index.html"
    NEW_VERSION="$new"
    return 0
  fi

  printf '%s\n' "$new" > app/VERSION
  # Only the pills carry a "vX.Y.Z" string, so a global replace is safe and
  # catches every one of them — there are three, and missing one is invisible
  # until someone reads the page.
  sed -i '' "s/v${cur}/v${new}/g" web/index.html

  local pills
  pills="$(/usr/bin/grep -o 'v[0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}' web/index.html | sort -u)"
  [ "$pills" = "v${new}" ] \
    || fail "web/index.html still advertises '${pills}' after the bump, expected 'v${new}'."

  NEW_VERSION="$new"
  success "app/VERSION and web/index.html are both ${new}"
}

header "Tweakd Release"
echo -e "    ${DIM}App:${RESET}     $( $DO_APPS && echo yes || echo -e "${DIM}skipped${RESET}" )"
echo -e "    ${DIM}Website:${RESET} $( $DO_WEB  && echo yes || echo -e "${DIM}skipped${RESET}" )"
echo -e "    ${DIM}Dry run:${RESET} $( $DRY_RUN && echo -e "${YELLOW}yes${RESET}" || echo -e "${DIM}no${RESET}" )"

NEW_VERSION="$(tr -d '[:space:]' < app/VERSION)"

if $DO_BUMP; then
  step "Bump version"
  bump_version
else
  step "Version"
  info "${NEW_VERSION} (not bumped)"
fi

PASS_ARGS=()
$DRY_RUN && PASS_ARGS+=("--dry-run")

if $DO_APPS; then
  step "App — build, sign, notarize, staple, upload"
  # release-download.sh gates its own upload on `stapler validate`, so an
  # un-notarised .dmg cannot get past this step even if signing silently
  # degraded.
  scripts/release-download.sh "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}" \
    || fail "App release failed — nothing was published."
  success "App published"
fi

if $DO_WEB; then
  step "Website — both front doors"
  # tweakd.app is a Worker; tweakd-app.pages.dev is Pages. release-website.sh
  # deploys both and fails preflight if either config is missing.
  scripts/release-website.sh "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}" \
    || fail "Website deploy failed."
  success "Website deployed"
fi

header "Release complete — v${NEW_VERSION}"
if $DRY_RUN; then
  echo -e "    ${YELLOW}Dry run — nothing was published.${RESET}"
else
  echo -e "    ${GREEN}Download:${RESET} https://tweakd.app/api/download"
  echo -e "    ${GREEN}Website:${RESET}  https://tweakd.app"
  if $DO_BUMP; then
    echo
    info "Not committed. Review, then:"
    info "  git add app/VERSION web/index.html docs/CHANGELOG.md"
    info "  git commit -m \"Release ${NEW_VERSION}\""
  fi
fi
echo
