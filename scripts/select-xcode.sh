#!/usr/bin/env bash
# Selects the newest installed Xcode with the given major version (default 27).
# From April 2027 App Store Connect only accepts builds made with the iOS 27 SDK (Xcode 27) or later.
set -euo pipefail
MAJOR="${1:-27}"
XCODE="$(ls -d /Applications/Xcode_${MAJOR}*.app 2>/dev/null | grep -v -i beta | sort -V | tail -1 || true)"
if [ -z "$XCODE" ]; then
  echo "::error::No Xcode $MAJOR found on this runner. Installed:" >&2
  ls -d /Applications/Xcode*.app >&2 || true
  exit 1
fi
sudo xcode-select -s "$XCODE"
xcodebuild -version
