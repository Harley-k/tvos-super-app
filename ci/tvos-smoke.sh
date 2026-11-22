#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "${RUNNER_OS:-}" = macOS
test "${RUNNER_ARCH:-}" = ARM64
expected="${EXPECTED_COMMIT:-}"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]]
test "$expected" = "$(git rev-parse HEAD)"
test "$expected" = "${GITHUB_SHA:-}"
echo "Commit: $expected"
echo 'Reference v0.1.0 source archive SHA-256: eea05a78f59ac8308e082afd4ef21b14db87116032968d7335025c8b14605c5e'
shasum -a 256 -c ci/source.sha256
diff -u <(awk '{print $2}' ci/source.sha256 | LC_ALL=C sort) <(find tvos-super-app -type f -print | LC_ALL=C sort)

export DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer
test -d "$DEVELOPER_DIR"
xcodebuild -version
xcodebuild -showsdks
xcrun simctl list runtimes
xcrun simctl list devices available

work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/supertv-ci.XXXXXX")"
udid=''
cleanup() {
  if [[ -n "$udid" ]]; then xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
cd tvos-super-app

python3 scripts/verify-source.py
xcrun --sdk macosx swiftc SuperTV/Catalog.swift tests/CoreSmoke.swift -o "$work/CoreSmoke"
"$work/CoreSmoke" SuperTV/DemoCatalog.json

xcodebuild -project SuperTV.xcodeproj -scheme SuperTV -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath "$work/DerivedData" CODE_SIGNING_ALLOWED=NO build

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
devices = data.get("com.apple.CoreSimulator.SimRuntime.tvOS-26-5", ())
print(next(x["udid"] for x in devices if x["name"] == "Apple TV 4K (3rd generation)"))
')"
[[ "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]]
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
app="$work/DerivedData/Build/Products/Debug-appletvsimulator/SuperTV.app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")"
test "$bundle_id" = org.example.supertvdemo
xcrun simctl install "$udid" "$app"
launch="$(xcrun simctl launch "$udid" "$bundle_id")"
printf '%s\n' "$launch"
pid="${launch##*: }"
[[ "$pid" =~ ^[0-9]+$ ]]
sleep 3
ps -p "$pid" -o pid= >/dev/null
printf '%s\n' 'PASS: Foundation smoke, tvOS Simulator compile/install/launch.' \
  'Not tested: focus, episode playback, resume, Apple TV hardware, or Hongguo.'
