#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
test "${RUNNER_OS:-}" = macOS
test "${RUNNER_ARCH:-}" = ARM64
expected="${EXPECTED_COMMIT:-}"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]]
test "$expected" = "$(git rev-parse HEAD)"
test "$expected" = "${GITHUB_SHA:-}"
echo "Verifying commit: $expected"
echo "Reference 0.2.0 ZIP SHA-256: 4df5bca68bc5ed18b08ca31c224b7e5d4f431e33083b8862b0929ded4b448013"
shasum -a 256 -c ci/release-02/source.sha256
diff -u <(awk '{print $2}' ci/release-02/source.sha256 | LC_ALL=C sort) \
        <(find releases/v0.2.0 -type f -print | LC_ALL=C sort)

export DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer
test -d "$DEVELOPER_DIR"
xcodebuild -version
xcodebuild -showsdks
xcrun simctl list runtimes
xcrun simctl list devices available

work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/supertv-v02.XXXXXX")"
sim_id=''
boot_pid=''
cleanup() {
  if [[ -n "$boot_pid" ]]; then kill "$boot_pid" >/dev/null 2>&1 || true; fi
  if [[ -n "$sim_id" ]]; then xcrun simctl shutdown "$sim_id" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
cd releases/v0.2.0

set +e
sim_id="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get("com.apple.CoreSimulator.SimRuntime.tvOS-26-5", ())
choices = [d["udid"] for d in devices if d["name"] == "Apple TV 4K (3rd generation)"]
if not choices:
    sys.exit("preconfigured tvOS 26.5 Apple TV 4K (3rd generation) not found")
print(choices[0])
')"
sim_find_rc=$?
if [[ "$sim_find_rc" == 0 && "$sim_id" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  (
    set -e
    xcrun simctl boot "$sim_id"
    xcrun simctl bootstatus "$sim_id" -b
  ) > "$work/tvos-boot.log" 2>&1 &
  boot_pid=$!
else
  sim_find_rc=1
  sim_id=''
fi

echo '::group::Shared Foundation tests'
(
  set -e
  python3 scripts/verify-source.py
  xcrun --sdk macosx swiftc -swift-version 5 -module-cache-path "$work/Modules" \
    SuperTV/Catalog.swift tests/CoreSmoke.swift -o "$work/CoreSmoke"
  "$work/CoreSmoke" SuperTV/DemoCatalog.json
)
foundation_rc=$?
echo '::endgroup::'

echo '::group::macOS native compile and app launch'
(
  set -e
  xcodebuild -project SuperTV.xcodeproj -scheme SuperTV-macOS -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$work/MacBuild" \
    CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO build
  app="$work/MacBuild/Build/Products/Debug/SuperTV-macOS.app"
  test -d "$app"
  info="$app/Contents/Info.plist"
  bid="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$info")"
  exe="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$info")"
  test "$bid" = org.example.supertvdemo.macos
  test -x "$app/Contents/MacOS/$exe"
  cmp "$app/Contents/Resources/Offline/demo-episode-1.mp4" SuperTV/Offline/demo-episode-1.mp4
  cmp "$app/Contents/Resources/Offline/demo-episode-2.mp4" SuperTV/Offline/demo-episode-2.mp4
  # Local runner-only ad hoc signature for Apple silicon; not distributable.
  /usr/bin/codesign --force --sign - "$app"
  /usr/bin/codesign --verify --strict --verbose=2 "$app"
  "$app/Contents/MacOS/$exe" > "$work/mac-app.log" 2>&1 &
  child=$!
  stop_app() { kill "$child" >/dev/null 2>&1 || true; wait "$child" 2>/dev/null || true; }
  trap stop_app EXIT
  sleep 5
  if ! kill -0 "$child"; then tail -80 "$work/mac-app.log"; exit 1; fi
  echo "PASS: macOS native application running; bundle ID and offline media bytes verified."
)
mac_build_rc=$?
echo '::endgroup::'

echo '::group::macOS native AVFoundation decoder and resume probe'
(
  set -e
  test "$mac_build_rc" = 0
  app="$work/MacBuild/Build/Products/Debug/SuperTV-macOS.app"
  xcrun --sdk macosx swiftc -swift-version 5 -module-cache-path "$work/Modules" \
    SuperTV/Catalog.swift "$root/ci/release-02/MacPlaybackProbe.swift" -o "$work/MacPlaybackProbe"
  "$work/MacPlaybackProbe" \
    "$app/Contents/Resources/Offline/demo-episode-1.mp4" \
    "$app/Contents/Resources/Offline/demo-episode-2.mp4" > "$work/mac-probe.log" 2>&1 &
  probe_pid=$!
  (sleep 65; kill "$probe_pid" 2>/dev/null || true) &
  timer=$!
  stop_timer() { kill "$timer" 2>/dev/null || true; wait "$timer" 2>/dev/null || true; }
  trap stop_timer EXIT
  if wait "$probe_pid"; then cat "$work/mac-probe.log"
  else cat "$work/mac-probe.log"; exit 1
  fi
)
mac_probe_rc=$?
echo '::endgroup::'

echo '::group::tvOS Simulator and XCUI Remote tests'
boot_rc=1
if [[ "$sim_find_rc" == 0 ]]; then
  wait "$boot_pid"
  boot_rc=$?
  boot_pid=''
  cat "$work/tvos-boot.log"
fi
(
  set -e
  test "$sim_find_rc" = 0
  test "$boot_rc" = 0
  xcodebuild -project SuperTV.xcodeproj -scheme SuperTV -configuration Debug \
    -destination "platform=tvOS Simulator,id=$sim_id" -derivedDataPath "$work/TVBuild" \
    -parallel-testing-enabled NO test
)
tv_rc=$?
echo '::endgroup::'

status() {
  if [[ "$1" == 0 ]]; then printf 'PASS'; else printf 'FAIL/BLOCKED (exit %s)' "$1"; fi
}
summary="$(printf '%s\n' "Commit: $expected" \
 'Stage | Result' '--- | ---' \
 "Shared Foundation | $(status "$foundation_rc")" \
 "macOS build and process launch | $(status "$mac_build_rc")" \
 "macOS AVFoundation native frame/time/seek (not App UI) | $(status "$mac_probe_rc")" \
 "tvOS Simulator XCTest remote/import/playback | $(status "$tv_rc")" \
 'No artifacts; no Developer ID, physical Apple TV, network-source integration, or notary testing.')"
printf '%s\n' "$summary"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then printf '%s\n' "$summary" >> "$GITHUB_STEP_SUMMARY"; fi
test "$foundation_rc" = 0 && test "$mac_build_rc" = 0 && test "$mac_probe_rc" = 0 && test "$tv_rc" = 0
