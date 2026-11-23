#!/usr/bin/env bash
# Use in a separately approved standard macOS job AFTER one existing tvOS simulator is booted.
# This wrapper never provisions a runner or triggers a job. Arguments: baseline, fix, booted-UDID.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
baseline="$(cd "$1" && pwd)"
fixed="$(cd "$2" && pwd)"
udid="$3"
[[ "$udid" =~ ^[0-9a-fA-F-]{36}$ ]]
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/supertv-focus-compare.XXXXXX")"
probe="$(python3 "$root/prepare-probe.py" "$baseline" "$work/baseline-test-only")"
printf '%s\n' 'Baseline: exact 0.2.0 product, only addition is temporary XCTest.'
set +e
xcodebuild -project "$probe/SuperTV.xcodeproj" -scheme SuperTV -configuration Debug \
  -destination "platform=tvOS Simulator,id=$udid" -derivedDataPath "$work/BaselineDerivedData" \
  -only-testing:SuperTVUITests/SuperTVUITests/testBaselineRemoteVerticalImport \
  -parallel-testing-enabled NO test 2>&1 | tee "$work/baseline.log"
baseline_rc=${PIPESTATUS[0]}
set -e
if [[ "$baseline_rc" == 0 ]]; then
  grep -q "testBaselineRemoteVerticalImport.*passed" "$work/baseline.log"
  echo 'DECISION: preserve product 0.2.0. Vertical remote route and validation work; old locator geometry is the primary failure.'
  exit 0
fi
if ! grep -Eq 'error:.*BASELINE_VERTICAL_ROUTE_BLOCKED:' "$work/baseline.log"; then
  echo 'DECISION: baseline inconclusive or another failure; do not automatically build the layout patch.' >&2
  exit "$baseline_rc"
fi
echo 'DECISION: the original product failed the recorded direction-only route; testing fixed layout with all three regressions.'
xcodebuild -project "$fixed/SuperTV.xcodeproj" -scheme SuperTV -configuration Debug \
   -destination "platform=tvOS Simulator,id=$udid" -derivedDataPath "$work/FixedDerivedData" \
   -parallel-testing-enabled NO test 2>&1 | tee "$work/fixed.log"
