#!/usr/bin/env bash
# Fails if the bundle ID in project.yml and codemagic.yaml ever diverge.
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ID=$(grep -E '^\s+PRODUCT_BUNDLE_IDENTIFIER:' project.yml | head -1 | awk '{print $2}')
CM_SIGNING_ID=$(grep -E '^\s+bundle_identifier:' codemagic.yaml | head -1 | awk '{print $2}')
CM_VAR_ID=$(grep -E '^\s+BUNDLE_ID:' codemagic.yaml | head -1 | awk '{print $2}' | tr -d '"')
echo "project.yml:       $PROJECT_ID"
echo "codemagic signing: $CM_SIGNING_ID"
echo "codemagic var:     $CM_VAR_ID"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" != "$CM_SIGNING_ID" || "$PROJECT_ID" != "$CM_VAR_ID" ]]; then
  echo "Bundle IDs do not match. Use the same ID everywhere." >&2
  exit 1
fi
echo "Bundle ID consistent."
