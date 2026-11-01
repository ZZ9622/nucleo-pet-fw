#!/usr/bin/env python3
"""Generate the dependency-free Xcode project and vector-derived app icon."""
from pathlib import Path
import hashlib
import json
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def generate_project():
    files = sorted((ROOT / 'App').glob('*.swift'))
    records = []

    def obj(name, text):
        records.append(f'\t\t{ident(name)} = {{ {text} }};')

    source_refs, source_builds = [], []
    for file in files:
        ref, build = 'ref:' + file.name, 'build:' + file.name
        obj(ref, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{file.name}"; sourceTree = "<group>";')
        obj(build, f'isa = PBXBuildFile; fileRef = {ident(ref)};')
        source_refs.append(ident(ref))
        source_builds.append(ident(build))

    obj('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
    obj('assets-build', f'isa = PBXBuildFile; fileRef = {ident("assets")};')
    obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NucleoPet.app; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('ui-test-file', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CompanionUITests.swift; sourceTree = "<group>";')
    obj('ui-test-build', f'isa = PBXBuildFile; fileRef = {ident("ui-test-file")};')
    obj('ui-test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = NucleoPetUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('ui-test-group', f'isa = PBXGroup; path = UITests; sourceTree = "<group>"; children = ({ident("ui-test-file")});')
    obj('app-group', 'isa = PBXGroup; path = App; sourceTree = "<group>"; children = (' + ','.join(source_refs + [ident('assets')]) + ');')
    obj('products-group', f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({ident("product")}, {ident("ui-test-product")});')
    obj('root-group', f'isa = PBXGroup; sourceTree = "<group>"; children = ({ident("app-group")}, {ident("ui-test-group")}, {ident("products-group")});')
    obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(source_builds) + '); runOnlyForDeploymentPostprocessing = 0;')
    obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ident("domain-build")}); runOnlyForDeploymentPostprocessing = 0;')
    obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ident("assets-build")}); runOnlyForDeploymentPostprocessing = 0;')
    obj('local-package', 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
    obj('domain-product', f'isa = XCSwiftPackageProductDependency; package = {ident("local-package")}; productName = PetDomain;')
    obj('domain-build', f'isa = PBXBuildFile; productRef = {ident("domain-product")};')
    obj('ui-test-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ident("ui-test-build")}); runOnlyForDeploymentPostprocessing = 0;')
    obj('ui-test-frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj('ui-test-resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj('ui-test-proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("target")}; remoteInfo = NucleoPet;')
    obj('ui-test-dependency', f'isa = PBXTargetDependency; target = {ident("target")}; targetProxy = {ident("ui-test-proxy")};')

    for mode in ['Debug', 'Release']:
        active_arch = 'YES' if mode == 'Debug' else 'NO'
        compilation = 'DEBUG $(inherited)' if mode == 'Debug' else '$(inherited)'
        obj('project-' + mode, 'isa = XCBuildConfiguration; name = ' + mode + '; buildSettings = { CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; MACOSX_DEPLOYMENT_TARGET = 14.0; ONLY_ACTIVE_ARCH = ' + active_arch + '; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "' + compilation + '"; };')
        optimization = '-Onone' if mode == 'Debug' else '-O'
        obj('target-' + mode, f'''isa = XCBuildConfiguration; name = {mode}; buildSettings = {{
            ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
            CODE_SIGN_STYLE = Automatic;
            CURRENT_PROJECT_VERSION = 1;
            GENERATE_INFOPLIST_FILE = YES;
            INFOPLIST_FILE = App/Info.plist;
            INFOPLIST_KEY_CFBundleDisplayName = "方方的小屋";
            INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.lifestyle";
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
            INFOPLIST_KEY_UILaunchScreen_Generation = YES;
            INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
            MARKETING_VERSION = 0.1.0;
            PRODUCT_BUNDLE_IDENTIFIER = com.nucleopet.companion;
            PRODUCT_NAME = NucleoPet;
            SDKROOT = iphoneos;
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            SUPPORTS_MACCATALYST = NO;
            SWIFT_OPTIMIZATION_LEVEL = "{optimization}";
            SWIFT_EMIT_LOC_STRINGS = YES;
            TARGETED_DEVICE_FAMILY = 1;
        }};''')
        obj('ui-test-' + mode, f'''isa = XCBuildConfiguration; name = {mode}; buildSettings = {{
            CODE_SIGN_STYLE = Automatic;
            GENERATE_INFOPLIST_FILE = YES;
            PRODUCT_BUNDLE_IDENTIFIER = com.nucleopet.companion.uitests;
            PRODUCT_NAME = "$(TARGET_NAME)";
            SDKROOT = iphoneos;
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            TARGETED_DEVICE_FAMILY = 1;
            TEST_TARGET_NAME = NucleoPet;
            SWIFT_OPTIMIZATION_LEVEL = "{optimization}";
        }};''')

    for scope in ['project', 'target', 'ui-test']:
        obj(scope + '-configs', f'isa = XCConfigurationList; buildConfigurations = ({ident(scope + "-Debug")}, {ident(scope + "-Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    obj('target', f'''isa = PBXNativeTarget; buildConfigurationList = {ident("target-configs")};
        buildPhases = ({ident("sources")}, {ident("frameworks")}, {ident("resources")});
        buildRules = (); dependencies = (); name = NucleoPet;
        packageProductDependencies = ({ident("domain-product")});
        productName = NucleoPet; productReference = {ident("product")};
        productType = "com.apple.product-type.application";''')
    obj('ui-test-target', f'''isa = PBXNativeTarget; buildConfigurationList = {ident("ui-test-configs")};
        buildPhases = ({ident("ui-test-sources")}, {ident("ui-test-frameworks")}, {ident("ui-test-resources")});
        buildRules = (); dependencies = ({ident("ui-test-dependency")}); name = NucleoPetUITests;
        productName = NucleoPetUITests; productReference = {ident("ui-test-product")};
        productType = "com.apple.product-type.bundle.ui-testing";''')
    obj('project', f'''isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }};
        buildConfigurationList = {ident("project-configs")}; compatibilityVersion = "Xcode 14.0";
        developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base);
        mainGroup = {ident("root-group")}; productRefGroup = {ident("products-group")};
        packageReferences = ({ident("local-package")}); projectDirPath = ""; projectRoot = ""; targets = ({ident("target")}, {ident("ui-test-target")});''')

    project = ROOT / 'NucleoPet.xcodeproj'
    project.mkdir(exist_ok=True)
    (project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(records) + '\n}; rootObject = ' + ident('project') + '; }\n')
    schemes = project / 'xcshareddata' / 'xcschemes'
    schemes.mkdir(parents=True, exist_ok=True)
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target")}" BuildableName="NucleoPet.app" BlueprintName="NucleoPet" ReferencedContainer="container:NucleoPet.xcodeproj"/>'
    testref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("ui-test-target")}" BuildableName="NucleoPetUITests.xctest" BlueprintName="NucleoPetUITests" ReferencedContainer="container:NucleoPet.xcodeproj"/>'
    (schemes / 'NucleoPet.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testref}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''')


def generate_icon():
    size = 1024
    bg, green, coral = (247, 252, 255), (20, 66, 173), (41, 99, 224)
    data = bytearray(bytes(bg) * size * size)

    def rect(x, y, w, h, color):
        for row in range(max(0, y), min(size, y + h)):
            start, end = max(0, x), min(size, x + w)
            data[(row * size + start) * 3:(row * size + end) * 3] = bytes(color) * (end - start)

    def pixel_rect(x, y, w, h, color):
        rect(218 + (x - 43) * 14, 320 + y * 14, w * 14, h * 14, color)

    for r in [(48, 0, 6, 6), (74, 0, 6, 6), (48, 5, 32, 25), (43, 9, 42, 16), (50, 29, 7, 2), (72, 29, 7, 2)]:
        pixel_rect(*r, green)
    for x in [54, 70]:
        for dx, dy in [(0, 14), (2, 12), (4, 14)]:
            pixel_rect(x + dx, dy, 2, 2, bg)
    for r in [(60, 22, 2, 2), (66, 22, 2, 2), (62, 24, 4, 2)]:
        pixel_rect(*r, bg)
    rect(771, 206, 16, 72, coral)
    rect(743, 234, 72, 16, coral)

    def chunk(kind, value):
        return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value) & 0xffffffff)

    pixels = b''.join(b'\x00' + data[y * size * 3:(y + 1) * size * 3] for y in range(size))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
    assets = ROOT / 'App' / 'Assets.xcassets'
    icon = assets / 'AppIcon.appiconset'
    icon.mkdir(parents=True, exist_ok=True)
    (assets / 'Contents.json').write_text(json.dumps({'info': {'version': 1, 'author': 'xcode'}}))
    (icon / 'AppIcon.png').write_bytes(png)
    (icon / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'version': 1, 'author': 'xcode'}}, indent=2))


if __name__ == '__main__':
    generate_icon()
    generate_project()
    print('Created NucleoPet.xcodeproj and AppIcon assets.')
