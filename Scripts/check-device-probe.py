"""Validate source metadata and (on CI) the iPhone IPA's embedded watch app."""
from pathlib import Path
import argparse
import plistlib
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
probe = root / "Validation/DeviceProbe"
parser = argparse.ArgumentParser()
parser.add_argument("--ipa", type=Path)
args = parser.parse_args()
host_id = "com.personaltrainer.deviceprobe"
watch_id = host_id + ".watchkitapp"

for platform in ["iPhone", "Watch"]:
    support = probe / platform / "Support"
    with (support / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    with (support / "DeviceProbe.entitlements").open("rb") as stream:
        entitlement = plistlib.load(stream)
    assert entitlement == {"com.apple.developer.healthkit": True}, platform
    assert info["NSHealthShareUsageDescription"], platform
    assert "NSHealthUpdateUsageDescription" not in info, "Probe must remain read-only"
    assert "WKBackgroundModes" not in info, "Probe must not start a workout"
    if platform == "Watch":
        assert info["WKApplication"] is True
        assert info["WKCompanionAppBundleIdentifier"] == host_id
        assert info["WKRunsIndependentlyOfCompanionApp"] is False
    assert len(list((probe / platform).glob("*.swift"))) == 1
scheme = ET.parse(probe / "DeviceProbe.xcodeproj/xcshareddata/xcschemes/DeviceProbe.xcscheme")
assert scheme.find(".//BuildableReference").attrib["BlueprintName"] == "DeviceProbe"
pbx = (probe / "DeviceProbe.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
for source in probe.rglob("*.swift"):
    assert source.relative_to(probe).as_posix() in pbx, str(source)
assert 'dstSubfolderSpec = 16;' in pbx
assert '$(CONTENTS_FOLDER_PATH)/Watch' in pbx

if args.ipa:
    with zipfile.ZipFile(args.ipa) as archive:
        names = set(archive.namelist())
        host = "Payload/DeviceProbe.app/"
        watch = host + "Watch/DeviceProbeWatch.app/"
        for prefix, bundle, platform in [(host, host_id, "iPhoneOS"), (watch, watch_id, "WatchOS")]:
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            assert info["CFBundleIdentifier"] == bundle
            assert platform in info["CFBundleSupportedPlatforms"]
            assert prefix + info["CFBundleExecutable"] in names
            assert prefix + "_CodeSignature/CodeResources" in names
        watch_info = plistlib.loads(archive.read(watch + "Info.plist"))
        assert watch_info["WKCompanionAppBundleIdentifier"] == host_id
        assert not any(name.endswith(".mobileprovision") for name in names), "No personal signing profiles in CI artifact"
print("Device probe metadata OK" + ("; packaged host and Watch OK" if args.ipa else " (not a build or device test)"))
