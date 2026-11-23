#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
test "${GITHUB_REF:-}" = 'refs/heads/test/tvos-import-focus'
test "${GITHUB_EVENT_NAME:-}" = workflow_dispatch
test "${RUNNER_OS:-}" = macOS
test "${RUNNER_ARCH:-}" = ARM64
expected="${EXPECTED_COMMIT:-}"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]]
test "$expected" = "$(git rev-parse HEAD)"
test "$expected" = "${GITHUB_SHA:-}"
echo "Exact diagnostics commit: $expected"
echo 'Original product source on main was verified in commit 5631b1153f4945d9f4cf08dd41bec71fe2f1c067.'
shasum -a 256 -c ci/release-02/source.sha256
diff -u <(awk '{print $2}' ci/release-02/source.sha256 | LC_ALL=C sort) \
        <(find releases/v0.2.0 -type f -print | LC_ALL=C sort)
shasum -a 256 -c ci/import-focus/candidate-overlay.sha256

export DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer
test -d "$DEVELOPER_DIR"
xcodebuild -version
xcrun simctl list runtimes
xcrun simctl list devices available
uid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get("com.apple.CoreSimulator.SimRuntime.tvOS-26-5", ())
choices = [d["udid"] for d in devices if d["name"] == "Apple TV 4K (3rd generation)"]
if not choices:
    sys.exit("No preinstalled tvOS 26.5 Apple TV 4K (3rd generation)")
print(choices[0])
')"
[[ "$uid" =~ ^[0-9A-Fa-f-]{36}$ ]]
cleanup() { xcrun simctl shutdown "$uid" >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl boot "$uid"
xcrun simctl bootstatus "$uid" -b

work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/supertv-candidate.XXXXXX")"
mkdir "$work/candidate"
cp -R releases/v0.2.0/. "$work/candidate/"
cp -R ci/import-focus/candidate/. "$work/candidate/"
(cd "$work/candidate"; shasum -a 256 -c "$root/ci/import-focus/candidate-complete.sha256")

bash ci/import-focus/compare-on-simulator.sh "$root/releases/v0.2.0" "$work/candidate" "$uid"
