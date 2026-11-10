#!/usr/bin/env bash
# Selects the pinned Xcode on a CI runner. Falls back to the newest installed Xcode 26+
# with a loud warning, so a runner-image refresh doesn't silently change toolchains.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/tooling.env
PINNED="/Applications/Xcode_${XCODE_VERSION}.app"
if [[ -d "$PINNED" ]]; then
  sudo xcode-select -s "$PINNED"
else
  FALLBACK=$(ls -d /Applications/Xcode_2[6-9]*.app 2>/dev/null | grep -v -i beta | sort -V | tail -1 || true)
  if [[ -z "$FALLBACK" ]]; then
    echo "::error::No Xcode 26+ found. Installed:"; ls -d /Applications/Xcode*.app; exit 1
  fi
  echo "::warning::Pinned Xcode $XCODE_VERSION not on this runner; using $FALLBACK. Update scripts/tooling.env."
  sudo xcode-select -s "$FALLBACK"
fi
xcodebuild -version
