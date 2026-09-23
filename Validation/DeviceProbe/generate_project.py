"""Generate the isolated two-target probe with only Python's standard library."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT / "DeviceProbe.xcodeproj"
HOST_ID = "com.personaltrainer.deviceprobe"
WATCH_ID = HOST_ID + ".watchkitapp"
objects = {}

def ident(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()

def obj(label, isa, **values):
    key = ident(label)
    objects[key] = {"isa": isa, **values}
    return key

def encode(value, depth=0):
    if isinstance(value, dict):
        rows = ['\t' * (depth + 1) + f'{key} = {encode(item, depth + 1)};' for key, item in value.items()]
        return "{\n" + "\n".join(rows) + "\n" + "\t" * depth + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(item, depth + 1) for item in value) + ("," if value else "") + ")"
    return str(value) if isinstance(value, int) else json.dumps(value, ensure_ascii=True)

def configs(label, settings):
    configs = []
    for name in ["Debug", "Release"]:
        values = dict(settings)
        if label != "project":
            values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if name == "Debug" else "-O"
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG" if name == "Debug" else ""
        configs.append(obj(label + name, "XCBuildConfiguration", buildSettings=values, name=name))
    return obj(label + "ConfigList", "XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

product_refs = {}
groups = []
for folder in ["Shared", "iPhone", "Watch"]:
    paths = sorted((ROOT / folder).glob("*.swift"))
    if not paths:
        raise SystemExit(f"No Swift files in {folder}")
    refs = [obj(str(path.relative_to(ROOT)), "PBXFileReference", lastKnownFileType="sourcecode.swift",
                path=str(path.relative_to(ROOT)).replace("\\", "/"), sourceTree="<group>") for path in paths]
    groups.append(obj(folder + "Group", "PBXGroup", children=refs, name=folder, sourceTree="<group>"))
for name in ["DeviceProbe", "DeviceProbeWatch"]:
    product_refs[name] = obj(name + "Product", "PBXFileReference",
        explicitFileType="wrapper.application", includeInIndex=0, path=name + ".app", sourceTree="BUILT_PRODUCTS_DIR")
products = obj("products", "PBXGroup", children=list(product_refs.values()), name="Products", sourceTree="<group>")
main = obj("main", "PBXGroup", children=groups + [products], sourceTree="<group>")

for name, folder, bundle, sdk, platforms, family, deployment_key, deployment in [
    ("DeviceProbeWatch", "Watch", WATCH_ID, "watchos", "watchos watchsimulator", "4", "WATCHOS_DEPLOYMENT_TARGET", "11.0"),
    ("DeviceProbe", "iPhone", HOST_ID, "iphoneos", "iphoneos iphonesimulator", "1", "IPHONEOS_DEPLOYMENT_TARGET", "18.0"),
]:
    paths = sorted((ROOT / "Shared").glob("*.swift")) + sorted((ROOT / folder).glob("*.swift"))
    builds = [obj(name + str(path.relative_to(ROOT)), "PBXBuildFile",
                  fileRef=ident(str(path.relative_to(ROOT)))) for path in paths]
    sources = obj(name + "Sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
    frameworks = obj(name + "Frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    resources = obj(name + "Resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    phases, dependencies = [sources, frameworks, resources], []
    if folder == "iPhone":
        embed = obj("embedWatchFile", "PBXBuildFile", fileRef=product_refs["DeviceProbeWatch"], settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        phases.append(obj("embedWatch", "PBXCopyFilesBuildPhase", buildActionMask=2147483647,
            dstPath="$(CONTENTS_FOLDER_PATH)/Watch", dstSubfolderSpec=16, files=[embed], name="Embed Watch Content", runOnlyForDeploymentPostprocessing=0))
        proxy = obj("watchProxy", "PBXContainerItemProxy", containerPortal=ident("project"), proxyType=1,
            remoteGlobalIDString=ident("DeviceProbeWatchTarget"), remoteInfo="DeviceProbeWatch")
        dependencies.append(obj("watchDependency", "PBXTargetDependency", target=ident("DeviceProbeWatchTarget"), targetProxy=proxy))
    settings = {
        "CODE_SIGN_STYLE": "Automatic",
        "CODE_SIGN_ENTITLEMENTS": folder + "/Support/DeviceProbe.entitlements",
        "INFOPLIST_FILE": folder + "/Support/Info.plist",
        "GENERATE_INFOPLIST_FILE": "NO",
        "PRODUCT_BUNDLE_IDENTIFIER": bundle, "PRODUCT_NAME": "$(TARGET_NAME)",
        "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
        "SDKROOT": sdk, "SUPPORTED_PLATFORMS": platforms, "TARGETED_DEVICE_FAMILY": family,
        deployment_key: deployment, "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete", "ENABLE_PREVIEWS": "YES",
        "SKIP_INSTALL": "YES" if folder == "Watch" else "NO",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    }
    obj(name + "Target", "PBXNativeTarget", buildConfigurationList=configs(name, settings),
        buildPhases=phases, buildRules=[], dependencies=dependencies, name=name,
        productName=name, productReference=product_refs[name], productType="com.apple.product-type.application")

project = obj("project", "PBXProject",
    attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600",
        "TargetAttributes": {ident(name + "Target"): {"CreatedOnToolsVersion": "26.0", "SystemCapabilities": {"com.apple.HealthKit": {"enabled": 1}}} for name in product_refs}},
    buildConfigurationList=configs("project", {"CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SWIFT_VERSION": "6.0"}),
    compatibilityVersion="Xcode 14.0", developmentRegion="pt-BR", hasScannedForEncodings=0,
    knownRegions=["pt-BR", "Base"], mainGroup=main, productRefGroup=products,
    projectDirPath="", projectRoot="", targets=[ident("DeviceProbeTarget"), ident("DeviceProbeWatchTarget")])
PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({
    "archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project
}) + "\n", encoding="utf-8")

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("DeviceProbeTarget")}" BuildableName="DeviceProbe.app" BlueprintName="DeviceProbe" ReferencedContainer="container:DeviceProbe.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("DeviceProbeTarget")}" BuildableName="DeviceProbe.app" BlueprintName="DeviceProbe" ReferencedContainer="container:DeviceProbe.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "DeviceProbe.xcscheme").write_text(scheme, encoding="utf-8")

for folder in ["iPhone", "Watch"]:
    support = ROOT / folder / "Support"
    support.mkdir(parents=True, exist_ok=True)
    info = {
        "CFBundleDevelopmentRegion": "pt-BR", "CFBundleDisplayName": "Teste Personal",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "NSHealthShareUsageDescription": "Ler a última frequência cardíaca para testar o acesso ao Saúde neste aparelho. Nenhum dado sai do aparelho.",
    }
    if folder == "Watch":
        info.update(WKApplication=True, WKCompanionAppBundleIdentifier=HOST_ID, WKRunsIndependentlyOfCompanionApp=False)
    else:
        info.update(LSRequiresIPhoneOS=True, UILaunchScreen={}, UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait"])
    with (support / "Info.plist").open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)
    with (support / "DeviceProbe.entitlements").open("wb") as stream:
        plistlib.dump({"com.apple.developer.healthkit": True}, stream)
