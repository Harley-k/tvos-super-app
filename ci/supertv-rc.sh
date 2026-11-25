#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
test "$(uname -s)" = Darwin && test "$(uname -m)" = arm64
if [[ -d /Applications/Xcode_26.5.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer
fi
xcodebuild -version
xcrun simctl list runtimes
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/supertv-rc.XXXXXX")"
cd app
python3 scripts/verify-source.py
bash scripts/prepare-open-film.sh
film_sha=8c23aae165447a26d88e356849b0ea4fd84edaee1be9ccd63f981ed7b08b750c
verify_film() {
  local media="$1/Offline/OpenFilm"
  printf '%s  %s\n' "$film_sha" "$media/wing-it.mp4" | shasum -a 256 -c -
  cmp "$media/ATTRIBUTION.txt" SuperTV/Offline/OpenFilm/ATTRIBUTION.txt
}
verify_film SuperTV
xcrun swiftc -swift-version 5 SuperTV/Catalog.swift tests/CoreSmoke.swift -o "$work/core-smoke"
"$work/core-smoke" SuperTV/DemoCatalog.json
sim="$(xcrun simctl list -j devices available | python3 -c '
import sys,json,re
candidates=[]
for runtime,devices in json.load(sys.stdin)["devices"].items():
    if ".tvOS-" not in runtime: continue
    version = tuple(map(int, re.findall(r"[0-9]+",runtime.split(".tvOS-")[1])))
    if version<(17,): continue
    candidates += [(version == (26,5),version,"4K" in d["name"],d["udid"]) for d in devices if d.get("isAvailable") and d["name"].startswith("Apple TV")]
if not candidates: sys.exit("No compatible, available tvOS 17+ simulator")
print(max(candidates)[-1])')"
cleanup() { xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl bootstatus "$sim" -b > "$work/boot.log" 2>&1 & boot=$!
project=(-project SuperTV.xcodeproj)
mac=(-scheme SuperTV-macOS -destination 'platform=macOS,arch=arm64' -derivedDataPath "$work/mac")
tv=(-scheme SuperTV -destination "platform=tvOS Simulator,id=$sim" -derivedDataPath "$work/tv")
# macOS XCTest uses a dedicated local debug library; no production provisioning profiles.
# Run macOS and tvOS separately, so both results are visible even if one fails.
logs="$root/build-diagnostics"; mkdir -p "$logs"
mac_rc=0
xcodebuild "${project[@]}" "${mac[@]}" -configuration Debug -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- test 2>&1 | tee "$logs/mac-test.log" || mac_rc=$?
tv_rc=0
if wait "$boot"; then
  xcodebuild "${project[@]}" "${tv[@]}" -configuration Debug -parallel-testing-enabled NO test 2>&1 | tee "$logs/tvos-test.log" || tv_rc=$?
else
  cat "$work/boot.log"; cp "$work/boot.log" "$logs/tvos-boot.log"; tv_rc=1
fi
printf 'macOS native UI result=%s, tvOS simulator UI result=%s\n' "$mac_rc" "$tv_rc"
test "$mac_rc" = 0 && test "$tv_rc" = 0 || exit 1
xcodebuild "${project[@]}" "${mac[@]}" -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
app="$work/mac/Build/Products/Release/SuperTV-macOS.app"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
exe="$app/Contents/MacOS/SuperTV-macOS"
test "$(lipo -archs "$exe")" = arm64
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")" = 0.3.0
cmp "$app/Contents/Resources/Offline/demo-episode-1.mp4" SuperTV/Offline/demo-episode-1.mp4
cmp "$app/Contents/Resources/Offline/demo-episode-2.mp4" SuperTV/Offline/demo-episode-2.mp4
verify_film "$app/Contents/Resources"
"$exe" > "$work/mac-release.log" 2>&1 & app_pid=$!
sleep 5
kill -0 "$app_pid"
kill "$app_pid"; wait "$app_pid" || true
xcrun swiftc -swift-version 5 SuperTV/Catalog.swift "$root/ci/release-02/MacPlaybackProbe.swift" -o "$work/probe"
"$work/probe" "$app/Contents/Resources/Offline/demo-episode-1.mp4" "$app/Contents/Resources/Offline/demo-episode-2.mp4"
xcodebuild "${project[@]}" "${tv[@]}" -configuration Release CODE_SIGNING_ALLOWED=NO build
tvapp="$work/tv/Build/Products/Release-appletvsimulator/SuperTV.app"
test "$(/usr/libexec/PlistBuddy -c 'Print DTPlatformName' "$tvapp/Info.plist")" = appletvsimulator
verify_film "$tvapp"
dist="$root/build-delivery"; mkdir -p "$dist"
ditto -c -k --keepParent "$app" "$dist/SuperTV-macOS-Apple-Silicon-adhoc.zip"
ditto -c -k --keepParent "$tvapp" "$dist/SuperTV-tvOS-simulator-only.zip"
# Verify restoration of the inner ZIP, including resource and signature preservation.
mkdir "$work/reopened"; ditto -x -k "$dist/SuperTV-macOS-Apple-Silicon-adhoc.zip" "$work/reopened"
codesign --verify --strict "$work/reopened/SuperTV-macOS.app"
cmp "$exe" "$work/reopened/SuperTV-macOS.app/Contents/MacOS/SuperTV-macOS"
verify_film "$work/reopened/SuperTV-macOS.app/Contents/Resources"
mkdir "$work/reopened-tv"; ditto -x -k "$dist/SuperTV-tvOS-simulator-only.zip" "$work/reopened-tv"
verify_film "$work/reopened-tv/SuperTV.app"
git rev-parse HEAD > "$dist/SOURCE-COMMIT.txt"
(cd "$dist" && shasum -a 256 *.zip > SHA256SUMS.txt)
cat > "$dist/请先阅读.txt" <<'NOTE'
Mac：Apple 芯片、macOS 14 或以上。请解压 Mac ZIP，将应用移到“应用程序”并打开。本构建仅临时签名，未公证；不承诺系统免提示。只在核对来源、版本和校验和并信任开发者后，才考虑按系统提供的单项提示打开，不要关闭系统安全防护。
Apple TV：tvOS ZIP 仅供 Mac 上的 Xcode Apple TV 模拟器使用，不能装在电视盒子上。真机请用源码在 Xcode 配对并签名运行；本包不是 TestFlight 或 App Store 版本。
本应用演示样例和合法 HTTPS 播放源；导入许可和第三方平台播放权不是同一件事。
NOTE
