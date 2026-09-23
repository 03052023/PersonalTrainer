#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
output="$root/build/device-probe"
mkdir -p "$output"
python3 Validation/DeviceProbe/generate_project.py
python3 Scripts/check-device-probe.py
xcodebuild -version
xcodebuild -project Validation/DeviceProbe/DeviceProbe.xcodeproj \
  -scheme DeviceProbe -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$output/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
app="$output/DerivedData/Build/Products/Release-iphoneos/DeviceProbe.app"
watch="$app/Watch/DeviceProbeWatch.app"
test -f "$app/DeviceProbe"
test -f "$watch/DeviceProbeWatch"
# Local ad-hoc signatures carry HealthKit entitlements for the Windows re-signer.
# These are NOT Apple provisioning signatures and cannot install as shipped.
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements Validation/DeviceProbe/Watch/Support/DeviceProbe.entitlements "$watch"
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements Validation/DeviceProbe/iPhone/Support/DeviceProbe.entitlements "$app"
codesign --verify --deep --strict "$app"
stage="$(mktemp -d "$output/package.XXXXXX")"
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/DeviceProbe.app"
ditto -c -k --keepParent "$stage/Payload" "$output/DeviceProbe-for-resigning.ipa"
python3 Scripts/check-device-probe.py --ipa "$output/DeviceProbe-for-resigning.ipa"
shasum -a 256 "$output/DeviceProbe-for-resigning.ipa" > "$output/SHA256.txt"
git rev-parse HEAD > "$output/SOURCE_COMMIT.txt"
xcodebuild -version > "$output/XCODE_VERSION.txt"
