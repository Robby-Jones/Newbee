#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator, preferring a Pro model (Dynamic Island).
# Usage: pick-simulator.sh [ios-major-version]
#   With a version (e.g. 17), only simulators on that iOS major version are considered; if none
#   exist, the newest available runtime for that version is used to create one, downloading the
#   runtime first if necessary.
set -euo pipefail
MAJOR="${1:-}"

pick() {
  xcrun simctl list devices available -j | MAJOR="$MAJOR" python3 -c '
import json, os, sys
major = os.environ["MAJOR"]
devices = json.load(sys.stdin)["devices"]
def matches(runtime):
    if "iOS" not in runtime:
        return False
    return not major or f"iOS-{major}-" in runtime
phones = [d for runtime, ds in sorted(devices.items()) if matches(runtime) for d in ds if d["name"].startswith("iPhone")]
pro = [d for d in phones if "Pro" in d["name"]] or phones
print(pro[-1]["udid"] if pro else "")
'
}

udid="$(pick)"
if [ -z "$udid" ] && [ -n "$MAJOR" ]; then
  runtime() {
    xcrun simctl list runtimes available -j | MAJOR="$MAJOR" python3 -c '
import json, os, sys
major = os.environ["MAJOR"]
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["version"].split(".")[0] == major]
print(sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"] if rts else "")
'
  }
  rt="$(runtime)"
  if [ -z "$rt" ]; then
    echo "Downloading iOS $MAJOR simulator runtime..." >&2
    xcodebuild -downloadPlatform iOS -buildVersion "$MAJOR.5" >&2
    rt="$(runtime)"
  fi
  [ -n "$rt" ] || { echo "No iOS $MAJOR runtime available" >&2; exit 1; }
  udid="$(xcrun simctl create "iPhone 15 Pro (iOS $MAJOR)" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$rt")"
fi
[ -n "$udid" ] || { echo "No iPhone simulator available" >&2; exit 1; }
echo "$udid"
