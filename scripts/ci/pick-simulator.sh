#!/usr/bin/env bash
# Prints the UDID of an available iPad simulator, newest runtime first, for xcodebuild test.
set -euo pipefail
xcrun simctl list devices available --json | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return tuple(int(x) for x in m.groups()) if m else (0, 0)
for runtime in sorted(devices, key=version, reverse=True):
    if "iOS" not in runtime:
        continue
    ipads = [d for d in devices[runtime] if d["name"].startswith("iPad")]
    pro = [d for d in ipads if "Pro" in d["name"]]
    for d in pro + ipads:
        print(d["udid"]); sys.exit(0)
sys.exit("No iPad simulator available")
'
