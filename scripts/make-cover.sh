#!/usr/bin/env bash
# Regenerates Assets/cover.png (the repository cover / GitHub social preview, 1280x640)
# from Assets/cover.html, which lays out the app icon, name and Assets/screenshot.jpg.
#
#   scripts/make-cover.sh
#
# Needs Google Chrome (or set CHROME to any Chromium binary).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1280,640 --screenshot="$root/Assets/cover.png" "file://$root/Assets/cover.html"
echo "wrote Assets/cover.png"
