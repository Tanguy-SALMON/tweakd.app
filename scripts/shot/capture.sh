#!/usr/bin/env bash
#
# capture.sh — screenshot Tweakd's windows into marketing/shots/.
#
# Usage:
#   scripts/shot/capture.sh                 # capture the main window
#   scripts/shot/capture.sh --name sidebar  # name the output file
#   scripts/shot/capture.sh --list          # just show the windows and exit
#
# Requires Screen Recording permission for whatever runs this (Terminal,
# iTerm, …): System Settings → Privacy & Security → Screen Recording. Without
# it `screencapture` writes a file containing the desktop wallpaper and no
# window, and exits 0 — so this script checks the result rather than the exit
# code.
#
# The app must already be running; capture.sh does not launch it, because a
# window caught mid-launch shows empty panes and a spinner.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="marketing/shots"
NAME="main"
LIST_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --name)  NAME="$2"; shift 2 ;;
    --list)  LIST_ONLY=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1 (use --help)"; exit 1 ;;
  esac
done

WINDOWS="$(swift scripts/shot/winlist.swift tweakd 2>&1)" || {
  echo "$WINDOWS"
  echo
  echo "Start the app first:  open app/build/tweakd.app"
  exit 1
}

echo "$WINDOWS"
$LIST_ONLY && exit 0

# Layer 0 is an ordinary window; the menu-bar popover sits higher. Picking the
# largest layer-0 window gets the main window even when an About or Settings
# panel is also open.
WIN_ID="$(echo "$WINDOWS" | awk '
  /layer=0/ {
    split($3, s, "=");            # size=WxH
    split(s[2], d, "x");
    area = d[1] * d[2];
    if (area > best) { best = area; split($1, i, "="); id = i[2] }
  }
  END { print id }
')"

[ -n "$WIN_ID" ] || { echo "ERROR: no layer-0 window found. Is the main window open?"; exit 1; }

mkdir -p "$OUT_DIR"
OUT="${OUT_DIR}/${NAME}@2x.png"

echo "==> capturing window ${WIN_ID} → ${OUT}"
# -o drops the drop shadow (it bloats the file and fights the page background),
# -x silences the shutter sound.
screencapture -o -x -l"$WIN_ID" "$OUT"

[ -f "$OUT" ] || { echo "ERROR: screencapture wrote nothing."; exit 1; }

# Screen Recording denial is silent: the file exists, the command exits 0, and
# the image is the wallpaper. A window capture is never 1x1, and a denied one
# tends to come back as the full screen, so compare against the window we asked
# for.
DIMS="$(sips -g pixelWidth -g pixelHeight "$OUT" 2>/dev/null | awk '/pixel/ {print $2}' | paste -sd'x' -)"
echo "    ${DIMS} px"
echo
echo "If that looks like your wallpaper rather than the app, grant Screen"
echo "Recording to your terminal in System Settings and run this again."
