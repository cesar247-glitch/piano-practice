#!/usr/bin/env bash
# Installs the pinned XcodeGen release into ./.tools/xcodegen (macOS only).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/tooling.env
DEST=".tools/xcodegen"
if [[ -x "$DEST/bin/xcodegen" ]] && [[ "$("$DEST/bin/xcodegen" --version 2>/dev/null)" == *"$XCODEGEN_VERSION"* ]]; then
  echo "XcodeGen $XCODEGEN_VERSION already installed"; exit 0
fi
rm -rf "$DEST" .tools/xcodegen.zip
mkdir -p .tools
curl -fsSL -o .tools/xcodegen.zip \
  "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
unzip -q .tools/xcodegen.zip -d .tools
"$DEST/bin/xcodegen" --version
