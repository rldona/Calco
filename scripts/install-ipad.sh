#!/bin/bash
# Builds Calco and installs it on the iPad plugged into this Mac, then opens it.
# Works with a free Apple ID: the install lasts 7 days, run this again to renew it.
#
#   scripts/install-ipad.sh            the first iPad found over USB (or Wi-Fi)
#   scripts/install-ipad.sh <UDID>     a specific device
#
# Signs with DEVELOPMENT_TEAM, from the environment or project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=dev.plazoleta.calco
DERIVED=build/dd-device
TEAM="${DEVELOPMENT_TEAM:-$(sed -n 's/^ *DEVELOPMENT_TEAM: *//p' project.yml | head -1)}"

UDID="${1:-}"
if [ -z "$UDID" ]; then
  LIST="$(mktemp)"
  xcrun devicectl list devices --json-output "$LIST" >/dev/null
  # Real iPads only (simulators are "sameMachine"), connected ones first.
  UDID="$(python3 - "$LIST" <<'EOF'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
ipads = [d for d in devices
         if d["hardwareProperties"].get("deviceType") == "iPad"
         and d["connectionProperties"].get("transportType") in ("wired", "localNetwork")]
ipads.sort(key=lambda d: (d["connectionProperties"].get("transportType") != "wired",
                          d["connectionProperties"].get("tunnelState") != "connected"))
print(ipads[0]["hardwareProperties"]["udid"] if ipads else "")
EOF
)"
  rm -f "$LIST"
  if [ -z "$UDID" ]; then
    echo "No iPad found. Plug it in, unlock it and trust this Mac, then try again." >&2
    exit 1
  fi
fi

[ -d Calco.xcodeproj ] || xcodegen
mkdir -p build

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' project.yml | head -1)"
echo "Building Calco $VERSION…"
# For any iOS device, so the build doesn't wait for this iPad to be unlocked; only the install does.
xcodebuild build -project Calco.xcodeproj -scheme Calco -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
  2>&1 | tee build/install-ipad.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build/install-ipad.log || { echo "The build failed: see build/install-ipad.log" >&2; exit 1; }

echo "Installing on ${UDID}…"
# A locked iPad refuses the install: give the person a moment to unlock it, then try again.
for attempt in 1 2 3 4 5 6; do
  if xcrun devicectl device install app --device "$UDID" "$DERIVED/Build/Products/Release-iphoneos/Calco.app" \
       >build/install-ipad-device.log 2>&1; then
    break
  fi
  if [ "$attempt" = 6 ]; then
    echo "Couldn't install: see build/install-ipad-device.log" >&2
    exit 1
  fi
  if grep -q "unlocked" build/install-ipad-device.log; then
    echo "Unlock the iPad (and keep the screen on)… trying again in 10 s"
  else
    echo "The install failed, trying again in 10 s…"
  fi
  sleep 10
done
echo "Opening…"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 \
  || echo "Installed. If it doesn't open, unlock the iPad, or trust the developer in Settings → General → VPN & Device Management."
echo "Calco $VERSION is on the iPad. It keeps working for 7 days with a free Apple ID."
