#!/usr/bin/env bash
# macOS CI test pass (no signing): core package tests, project generation, simulator build,
# app unit tests. Signing is deliberately absent so test failures and signing failures are
# never confused. Usage: scripts/ci-test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

run_xcodebuild() {
  local log="$1"; shift
  set +e
  xcodebuild "$@" > "$log" 2>&1
  local status=$?
  set -e
  grep -E "error:|Test Case .* (passed|failed)|Executed [0-9]+ test|\*\* (BUILD|TEST) " "$log" | tail -60 || true
  if [[ $status -ne 0 ]]; then
    echo "xcodebuild failed ($status). Last lines of $log:"; tail -80 "$log"; exit "$status"
  fi
}

echo "── 1/4 PianoCore package tests (swift test, macOS host)"
swift test --package-path PianoCore

echo "── 2/4 Generate Xcode project"
scripts/install-xcodegen.sh
.tools/xcodegen/bin/xcodegen generate

SIM_ID=$(scripts/pick-simulator.sh)
echo "Using simulator: $(xcrun simctl list devices | grep "$SIM_ID" || echo "$SIM_ID")"

echo "── 3/4 Build for testing (simulator, unsigned)"
rm -rf build/TestResults.xcresult
run_xcodebuild build/xcodebuild-build.log build-for-testing \
  -project PianoPractice.xcodeproj -scheme PianoPractice \
  -destination "id=$SIM_ID" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO

echo "── 4/4 App unit tests (Touch Demo wiring)"
run_xcodebuild build/xcodebuild-test.log test-without-building \
  -project PianoPractice.xcodeproj -scheme PianoPractice \
  -destination "id=$SIM_ID" -derivedDataPath build/DerivedData \
  -resultBundlePath build/TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO

echo "All CI checks passed."
