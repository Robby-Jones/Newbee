#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator, preferring a Pro model (Dynamic Island).
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime, ds in devices.items() if "iOS" in runtime for d in ds if d["name"].startswith("iPhone")]
pro = [d for d in phones if "Pro" in d["name"]] or phones
if not pro:
    sys.exit("No iPhone simulator available")
print(pro[-1]["udid"])
'
