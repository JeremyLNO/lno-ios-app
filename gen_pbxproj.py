#!/usr/bin/env python3
"""Generate LNO.xcodeproj/project.pbxproj for the LNO app + LNOWidgets extension.
Scans LNO/*.swift, LNOShared/*.swift (compiled into both targets) and
LNOWidgets/*.swift, wiring them into a valid two-target Xcode project.
Deterministic UUIDs (hash of a role key) so re-runs are stable."""
import os, hashlib, glob

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(ROOT, "LNO")
SHARED_DIR_NAME = "LNOShared"
WIDGET_DIR_NAME = "LNOWidgets"
PROJ = "LNO"
BUNDLE_ID = "company.lno.controlcenter"
ENTITLEMENTS = "LNO/LNO.entitlements"

WIDGET_PROJ = "LNOWidgets"
WIDGET_BUNDLE_ID = "company.lno.controlcenter.widgets"
WIDGET_ENTITLEMENTS = "LNOWidgets/LNOWidgets.entitlements"

# App-target files the widget extension also needs (design tokens, formatters, the
# vector logo, the deep-link URL scheme constant) — no networking/auth, safe to
# compile into both targets.
WIDGET_SHARED_FROM_APP = ["Theme.swift", "LNOLogo.swift", "Config.swift"]

# Free Apple Development identity on this Mac. Xcode always signs Simulator builds
# "Sign to Run Locally" regardless of team, but a from-source `xcodebuild` needs
# SOME team on file for automatic signing to run at all — without it (or with
# CODE_SIGNING_ALLOWED=NO) the app is unsigned and every Keychain call fails with
# errSecMissingEntitlement (-34018). Needed later anyway for a real device build.
DEVELOPMENT_TEAM = "2E6D4Q69QB"

# Swift Package Manager dependencies: (display name, repo URL, exact version, [library products]).
# OneSignal's XCFramework-based package — see LNO/OneSignalManager.swift for the wrapper.
# App target only; the widget extension doesn't need it.
SPM_PACKAGES = [
    ("OneSignal-XCFramework", "https://github.com/OneSignal/OneSignal-XCFramework", "5.5.1", ["OneSignalFramework"]),
]

def uid(key):
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()
u = lambda k: uid(k)

swift_files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(SRC_DIR, "*.swift")))
shared_files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, SHARED_DIR_NAME, "*.swift")))
widget_files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, WIDGET_DIR_NAME, "*.swift")))
assets = "Assets.xcassets"
infoplist = "Info.plist"
widget_infoplist = "Info.plist"

# ---- UUIDs -------------------------------------------------------------
prod_ref = u("product.app")
widget_prod_ref = u("product.widget")
main_group = u("group.main")
proj_group = u("group.LNO")
shared_group = u("group.LNOShared")
widget_group = u("group.LNOWidgets")
products_group = u("group.Products")
target = u("target.LNO")
widget_target = u("target.LNOWidgets")
project = u("project")
sources_phase = u("phase.sources")
resources_phase = u("phase.resources")
frameworks_phase = u("phase.frameworks")
embed_phase = u("phase.embed")
widget_sources_phase = u("phase.widget.sources")
widget_resources_phase = u("phase.widget.resources")
widget_frameworks_phase = u("phase.widget.frameworks")
proj_cfg_list = u("cfglist.project")
target_cfg_list = u("cfglist.target")
widget_cfg_list = u("cfglist.widget")
proj_debug = u("cfg.proj.debug")
proj_release = u("cfg.proj.release")
target_debug = u("cfg.target.debug")
target_release = u("cfg.target.release")
widget_debug = u("cfg.widget.debug")
widget_release = u("cfg.widget.release")
container_proxy = u("containerproxy.widget")
target_dependency = u("targetdep.widget")
embed_build_file = u("buildfile.embed.widget")

# File references (one per physical file, regardless of how many targets use it)
file_refs = {}
for f in swift_files:
    file_refs[f] = u("fileref.app." + f)
for f in shared_files:
    file_refs[f] = u("fileref.shared." + f)
for f in widget_files:
    file_refs[f] = u("fileref.widget." + f)
file_refs[assets] = u("fileref.assets")
entitlements_ref = u("fileref.entitlements")
widget_entitlements_ref = u("fileref.widget.entitlements")
widget_infoplist_ref = u("fileref.widget.info")
file_refs[infoplist] = u("fileref.info")

# Per-target Sources build files. A shared file gets ONE PBXBuildFile per target
# that compiles it (same fileRef, different buildFile — that's how one file can
# belong to two targets).
app_sources = list(swift_files) + list(shared_files)
widget_sources = list(widget_files) + list(shared_files) + list(WIDGET_SHARED_FROM_APP)
app_build_files = {f: u("buildfile.app.sources." + f) for f in app_sources}
widget_build_files = {f: u("buildfile.widget.sources." + f) for f in widget_sources}
assets_build_file = u("buildfile.assets")

# SPM package references + product dependencies + their Frameworks-phase build files (app target only)
pkg_refs = {}
product_deps = {}
product_build_files = {}
for name, url, version, products in SPM_PACKAGES:
    pkg_refs[name] = u("pkgref." + name)
    for prod in products:
        product_deps[prod] = u("proddep." + prod)
        product_build_files[prod] = u("buildfile.product." + prod)

def L(s=""):
    lines.append(s)

lines = []
L("// !$*UTF8*$!")
L("{")
L("\tarchiveVersion = 1;")
L("\tclasses = {")
L("\t};")
L("\tobjectVersion = 56;")
L("\tobjects = {")

# ---- PBXBuildFile -------------------------------------------------------
L("\n/* Begin PBXBuildFile section */")
for f in app_sources:
    L('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (app_build_files[f], f, file_refs[f], f))
for f in widget_sources:
    L('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (widget_build_files[f], f, file_refs[f], f))
L('\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (assets_build_file, assets, file_refs[assets], assets))
for prod, bf_uid in product_build_files.items():
    L('\t\t%s /* %s in Frameworks */ = {isa = PBXBuildFile; productRef = %s /* %s */; };' % (bf_uid, prod, product_deps[prod], prod))
L('\t\t%s /* %s.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = %s /* %s.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };' % (embed_build_file, WIDGET_PROJ, widget_prod_ref, WIDGET_PROJ))
L("/* End PBXBuildFile section */")

# ---- PBXFileReference -----------------------------------------------------
L("\n/* Begin PBXFileReference section */")
L('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "%s.app"; sourceTree = BUILT_PRODUCTS_DIR; };' % (prod_ref, PROJ, PROJ))
L('\t\t%s /* %s.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = "%s.appex"; sourceTree = BUILT_PRODUCTS_DIR; };' % (widget_prod_ref, WIDGET_PROJ, WIDGET_PROJ))
for f in swift_files:
    L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = "<group>"; };' % (file_refs[f], f, f))
for f in shared_files:
    L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = "<group>"; };' % (file_refs[f], f, f))
for f in widget_files:
    L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = "<group>"; };' % (file_refs[f], f, f))
L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = %s; sourceTree = "<group>"; };' % (file_refs[assets], assets, assets))
L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = %s; sourceTree = "<group>"; };' % (file_refs[infoplist], infoplist, infoplist))
L('\t\t%s /* LNO.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = LNO.entitlements; sourceTree = "<group>"; };' % entitlements_ref)
L('\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };' % widget_infoplist_ref)
L('\t\t%s /* LNOWidgets.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = LNOWidgets.entitlements; sourceTree = "<group>"; };' % widget_entitlements_ref)
L("/* End PBXFileReference section */")

# ---- PBXFrameworksBuildPhase ----------------------------------------------
L("\n/* Begin PBXFrameworksBuildPhase section */")
L('\t\t%s /* Frameworks */ = {' % frameworks_phase)
L('\t\t\tisa = PBXFrameworksBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
for prod, bf_uid in product_build_files.items():
    L('\t\t\t\t%s /* %s in Frameworks */,' % (bf_uid, prod))
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L('\t\t%s /* Frameworks */ = {' % widget_frameworks_phase)
L('\t\t\tisa = PBXFrameworksBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L("/* End PBXFrameworksBuildPhase section */")

# ---- PBXCopyFilesBuildPhase (Embed Foundation Extensions) ------------------
L("\n/* Begin PBXCopyFilesBuildPhase section */")
L('\t\t%s /* Embed Foundation Extensions */ = {' % embed_phase)
L('\t\t\tisa = PBXCopyFilesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tdstPath = "";')
L('\t\t\tdstSubfolderSpec = 13;')
L('\t\t\tfiles = (')
L('\t\t\t\t%s /* %s.appex in Embed Foundation Extensions */,' % (embed_build_file, WIDGET_PROJ))
L('\t\t\t);')
L('\t\t\tname = "Embed Foundation Extensions";')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L("/* End PBXCopyFilesBuildPhase section */")

# ---- PBXGroup ---------------------------------------------------------
L("\n/* Begin PBXGroup section */")
L('\t\t%s = {' % main_group)
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
L('\t\t\t\t%s /* %s */,' % (proj_group, PROJ))
L('\t\t\t\t%s /* %s */,' % (shared_group, SHARED_DIR_NAME))
L('\t\t\t\t%s /* %s */,' % (widget_group, WIDGET_PROJ))
L('\t\t\t\t%s /* Products */,' % products_group)
L('\t\t\t);')
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')
L('\t\t%s /* %s */ = {' % (proj_group, PROJ))
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
for f in swift_files:
    L('\t\t\t\t%s /* %s */,' % (file_refs[f], f))
L('\t\t\t\t%s /* %s */,' % (file_refs[assets], assets))
L('\t\t\t\t%s /* %s */,' % (file_refs[infoplist], infoplist))
L('\t\t\t\t%s /* LNO.entitlements */,' % entitlements_ref)
L('\t\t\t);')
L('\t\t\tpath = %s;' % PROJ)
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')
L('\t\t%s /* %s */ = {' % (shared_group, SHARED_DIR_NAME))
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
for f in shared_files:
    L('\t\t\t\t%s /* %s */,' % (file_refs[f], f))
L('\t\t\t);')
L('\t\t\tpath = %s;' % SHARED_DIR_NAME)
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')
L('\t\t%s /* %s */ = {' % (widget_group, WIDGET_PROJ))
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
for f in widget_files:
    L('\t\t\t\t%s /* %s */,' % (file_refs[f], f))
L('\t\t\t\t%s /* Info.plist */,' % widget_infoplist_ref)
L('\t\t\t\t%s /* LNOWidgets.entitlements */,' % widget_entitlements_ref)
L('\t\t\t);')
L('\t\t\tpath = %s;' % WIDGET_PROJ)
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')
L('\t\t%s /* Products */ = {' % products_group)
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
L('\t\t\t\t%s /* %s.app */,' % (prod_ref, PROJ))
L('\t\t\t\t%s /* %s.appex */,' % (widget_prod_ref, WIDGET_PROJ))
L('\t\t\t);')
L('\t\t\tname = Products;')
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')
L("/* End PBXGroup section */")

# ---- PBXNativeTarget -------------------------------------------------------
L("\n/* Begin PBXNativeTarget section */")
L('\t\t%s /* %s */ = {' % (target, PROJ))
L('\t\t\tisa = PBXNativeTarget;')
L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;' % (target_cfg_list, PROJ))
L('\t\t\tbuildPhases = (')
L('\t\t\t\t%s /* Sources */,' % sources_phase)
L('\t\t\t\t%s /* Frameworks */,' % frameworks_phase)
L('\t\t\t\t%s /* Resources */,' % resources_phase)
L('\t\t\t\t%s /* Embed Foundation Extensions */,' % embed_phase)
L('\t\t\t);')
L('\t\t\tbuildRules = (')
L('\t\t\t);')
L('\t\t\tdependencies = (')
L('\t\t\t\t%s /* PBXTargetDependency */,' % target_dependency)
L('\t\t\t);')
L('\t\t\tname = %s;' % PROJ)
L('\t\t\tpackageProductDependencies = (')
for prod, dep_uid in product_deps.items():
    L('\t\t\t\t%s /* %s */,' % (dep_uid, prod))
L('\t\t\t);')
L('\t\t\tproductName = %s;' % PROJ)
L('\t\t\tproductReference = %s /* %s.app */;' % (prod_ref, PROJ))
L('\t\t\tproductType = "com.apple.product-type.application";')
L('\t\t};')
L('\t\t%s /* %s */ = {' % (widget_target, WIDGET_PROJ))
L('\t\t\tisa = PBXNativeTarget;')
L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;' % (widget_cfg_list, WIDGET_PROJ))
L('\t\t\tbuildPhases = (')
L('\t\t\t\t%s /* Sources */,' % widget_sources_phase)
L('\t\t\t\t%s /* Frameworks */,' % widget_frameworks_phase)
L('\t\t\t\t%s /* Resources */,' % widget_resources_phase)
L('\t\t\t);')
L('\t\t\tbuildRules = (')
L('\t\t\t);')
L('\t\t\tdependencies = (')
L('\t\t\t);')
L('\t\t\tname = %s;' % WIDGET_PROJ)
L('\t\t\tproductName = %s;' % WIDGET_PROJ)
L('\t\t\tproductReference = %s /* %s.appex */;' % (widget_prod_ref, WIDGET_PROJ))
L('\t\t\tproductType = "com.apple.product-type.app-extension";')
L('\t\t};')
L("/* End PBXNativeTarget section */")

# ---- PBXProject -------------------------------------------------------
L("\n/* Begin PBXProject section */")
L('\t\t%s /* Project object */ = {' % project)
L('\t\t\tisa = PBXProject;')
L('\t\t\tattributes = {')
L('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
L('\t\t\t\tLastSwiftUpdateCheck = 1520;')
L('\t\t\t\tLastUpgradeCheck = 1520;')
L('\t\t\t\tTargetAttributes = {')
L('\t\t\t\t\t%s = {' % target)
L('\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;')
L('\t\t\t\t\t\tSystemCapabilities = {')
L('\t\t\t\t\t\t\t"com.apple.Push" = {')
L('\t\t\t\t\t\t\t\tenabled = 1;')
L('\t\t\t\t\t\t\t};')
L('\t\t\t\t\t\t};')
L('\t\t\t\t\t};')
L('\t\t\t\t\t%s = {' % widget_target)
L('\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;')
L('\t\t\t\t\t};')
L('\t\t\t\t};')
L('\t\t\t};')
L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "%s" */;' % (proj_cfg_list, PROJ))
L('\t\t\tcompatibilityVersion = "Xcode 14.0";')
L('\t\t\tdevelopmentRegion = en;')
L('\t\t\thasScannedForEncodings = 0;')
L('\t\t\tknownRegions = (')
L('\t\t\t\ten,')
L('\t\t\t\tBase,')
L('\t\t\t);')
L('\t\t\tmainGroup = %s;' % main_group)
L('\t\t\tpackageReferences = (')
for name in pkg_refs:
    L('\t\t\t\t%s /* XCRemoteSwiftPackageReference "%s" */,' % (pkg_refs[name], name))
L('\t\t\t);')
L('\t\t\tproductRefGroup = %s /* Products */;' % products_group)
L('\t\t\tprojectDirPath = "";')
L('\t\t\tprojectRoot = "";')
L('\t\t\ttargets = (')
L('\t\t\t\t%s /* %s */,' % (target, PROJ))
L('\t\t\t\t%s /* %s */,' % (widget_target, WIDGET_PROJ))
L('\t\t\t);')
L('\t\t};')
L("/* End PBXProject section */")

L("\n/* Begin PBXContainerItemProxy section */")
L('\t\t%s /* PBXContainerItemProxy */ = {' % container_proxy)
L('\t\t\tisa = PBXContainerItemProxy;')
L('\t\t\tcontainerPortal = %s /* Project object */;' % project)
L('\t\t\tproxyType = 1;')
L('\t\t\tremoteGlobalIDString = %s;' % widget_target)
L('\t\t\tremoteInfo = %s;' % WIDGET_PROJ)
L('\t\t};')
L("/* End PBXContainerItemProxy section */")

L("\n/* Begin PBXTargetDependency section */")
L('\t\t%s /* PBXTargetDependency */ = {' % target_dependency)
L('\t\t\tisa = PBXTargetDependency;')
L('\t\t\ttarget = %s /* %s */;' % (widget_target, WIDGET_PROJ))
L('\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;' % container_proxy)
L('\t\t};')
L("/* End PBXTargetDependency section */")

L("\n/* Begin XCRemoteSwiftPackageReference section */")
for name, url, version, products in SPM_PACKAGES:
    L('\t\t%s /* XCRemoteSwiftPackageReference "%s" */ = {' % (pkg_refs[name], name))
    L('\t\t\tisa = XCRemoteSwiftPackageReference;')
    L('\t\t\trepositoryURL = "%s";' % url)
    L('\t\t\trequirement = {')
    L('\t\t\t\tkind = exactVersion;')
    L('\t\t\t\tversion = %s;' % version)
    L('\t\t\t};')
    L('\t\t};')
L("/* End XCRemoteSwiftPackageReference section */")

L("\n/* Begin XCSwiftPackageProductDependency section */")
for name, url, version, products in SPM_PACKAGES:
    for prod in products:
        L('\t\t%s /* %s */ = {' % (product_deps[prod], prod))
        L('\t\t\tisa = XCSwiftPackageProductDependency;')
        L('\t\t\tpackage = %s /* XCRemoteSwiftPackageReference "%s" */;' % (pkg_refs[name], name))
        L('\t\t\tproductName = %s;' % prod)
        L('\t\t};')
L("/* End XCSwiftPackageProductDependency section */")

# ---- PBXResourcesBuildPhase -------------------------------------------
L("\n/* Begin PBXResourcesBuildPhase section */")
L('\t\t%s /* Resources */ = {' % resources_phase)
L('\t\t\tisa = PBXResourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
L('\t\t\t\t%s /* %s in Resources */,' % (assets_build_file, assets))
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L('\t\t%s /* Resources */ = {' % widget_resources_phase)
L('\t\t\tisa = PBXResourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L("/* End PBXResourcesBuildPhase section */")

# ---- PBXSourcesBuildPhase ----------------------------------------------
L("\n/* Begin PBXSourcesBuildPhase section */")
L('\t\t%s /* Sources */ = {' % sources_phase)
L('\t\t\tisa = PBXSourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
for f in app_sources:
    L('\t\t\t\t%s /* %s in Sources */,' % (app_build_files[f], f))
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L('\t\t%s /* Sources */ = {' % widget_sources_phase)
L('\t\t\tisa = PBXSourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
for f in widget_sources:
    L('\t\t\t\t%s /* %s in Sources */,' % (widget_build_files[f], f))
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L("/* End PBXSourcesBuildPhase section */")

# ---- XCBuildConfiguration -----------------------------------------------
def proj_common():
    return [
        'ALWAYS_SEARCH_USER_PATHS = NO;',
        'CLANG_ANALYZER_NONNULL = YES;',
        'CLANG_ENABLE_MODULES = YES;',
        'CLANG_ENABLE_OBJC_ARC = YES;',
        'ENABLE_STRICT_OBJC_MSGSEND = YES;',
        'GCC_C_LANGUAGE_STANDARD = gnu17;',
        'GCC_NO_COMMON_BLOCKS = YES;',
        'IPHONEOS_DEPLOYMENT_TARGET = 17.0;',
        'MTL_FAST_MATH = YES;',
        'SDKROOT = iphoneos;',
        'SWIFT_EMIT_LOC_STRINGS = YES;',
    ]

def target_common():
    return [
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;',
        'CODE_SIGN_ENTITLEMENTS = "%s";' % ENTITLEMENTS,
        'CODE_SIGN_STYLE = Automatic;',
        'DEVELOPMENT_TEAM = %s;' % DEVELOPMENT_TEAM,
        'CURRENT_PROJECT_VERSION = 1;',
        'ENABLE_PREVIEWS = YES;',
        'GENERATE_INFOPLIST_FILE = NO;',
        'INFOPLIST_FILE = "%s/%s";' % (PROJ, infoplist),
        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;',
        'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;',
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");',
        'MARKETING_VERSION = 1.0;',
        'PRODUCT_BUNDLE_IDENTIFIER = %s;' % BUNDLE_ID,
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'SWIFT_EMIT_LOC_STRINGS = YES;',
        'SWIFT_VERSION = 5.0;',
        'TARGETED_DEVICE_FAMILY = "1,2";',
    ]

def widget_target_common():
    return [
        'CODE_SIGN_ENTITLEMENTS = "%s";' % WIDGET_ENTITLEMENTS,
        'CODE_SIGN_STYLE = Automatic;',
        'DEVELOPMENT_TEAM = %s;' % DEVELOPMENT_TEAM,
        'CURRENT_PROJECT_VERSION = 1;',
        'GENERATE_INFOPLIST_FILE = NO;',
        'INFOPLIST_FILE = "%s/%s";' % (WIDGET_PROJ, widget_infoplist),
        'INFOPLIST_KEY_CFBundleDisplayName = "LNO Widgets";',
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks");',
        'MARKETING_VERSION = 1.0;',
        'PRODUCT_BUNDLE_IDENTIFIER = %s;' % WIDGET_BUNDLE_ID,
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'SKIP_INSTALL = YES;',
        'SWIFT_EMIT_LOC_STRINGS = YES;',
        'SWIFT_VERSION = 5.0;',
        'TARGETED_DEVICE_FAMILY = "1,2";',
    ]

L("\n/* Begin XCBuildConfiguration section */")
for cfg_uid, name, debug in [(proj_debug, "Debug", True), (proj_release, "Release", False)]:
    L('\t\t%s /* %s */ = {' % (cfg_uid, name))
    L('\t\t\tisa = XCBuildConfiguration;')
    L('\t\t\tbuildSettings = {')
    for s in proj_common():
        L('\t\t\t\t' + s)
    if debug:
        L('\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;')
        L('\t\t\t\tENABLE_TESTABILITY = YES;')
        L('\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;')
        L('\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");')
        L('\t\t\t\tONLY_ACTIVE_ARCH = YES;')
        L('\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";')
        L('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
    else:
        L('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
        L('\t\t\t\tENABLE_NS_ASSERTIONS = NO;')
        L('\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;')
    L('\t\t\t};')
    L('\t\t\tname = %s;' % name)
    L('\t\t};')
for cfg_uid, name in [(target_debug, "Debug"), (target_release, "Release")]:
    L('\t\t%s /* %s */ = {' % (cfg_uid, name))
    L('\t\t\tisa = XCBuildConfiguration;')
    L('\t\t\tbuildSettings = {')
    for s in target_common():
        L('\t\t\t\t' + s)
    L('\t\t\t};')
    L('\t\t\tname = %s;' % name)
    L('\t\t};')
for cfg_uid, name in [(widget_debug, "Debug"), (widget_release, "Release")]:
    L('\t\t%s /* %s */ = {' % (cfg_uid, name))
    L('\t\t\tisa = XCBuildConfiguration;')
    L('\t\t\tbuildSettings = {')
    for s in widget_target_common():
        L('\t\t\t\t' + s)
    L('\t\t\t};')
    L('\t\t\tname = %s;' % name)
    L('\t\t};')
L("/* End XCBuildConfiguration section */")

# ---- XCConfigurationList ------------------------------------------------
L("\n/* Begin XCConfigurationList section */")
L('\t\t%s /* Build configuration list for PBXProject "%s" */ = {' % (proj_cfg_list, PROJ))
L('\t\t\tisa = XCConfigurationList;')
L('\t\t\tbuildConfigurations = (')
L('\t\t\t\t%s /* Debug */,' % proj_debug)
L('\t\t\t\t%s /* Release */,' % proj_release)
L('\t\t\t);')
L('\t\t\tdefaultConfigurationIsVisible = 0;')
L('\t\t\tdefaultConfigurationName = Release;')
L('\t\t};')
L('\t\t%s /* Build configuration list for PBXNativeTarget "%s" */ = {' % (target_cfg_list, PROJ))
L('\t\t\tisa = XCConfigurationList;')
L('\t\t\tbuildConfigurations = (')
L('\t\t\t\t%s /* Debug */,' % target_debug)
L('\t\t\t\t%s /* Release */,' % target_release)
L('\t\t\t);')
L('\t\t\tdefaultConfigurationIsVisible = 0;')
L('\t\t\tdefaultConfigurationName = Release;')
L('\t\t};')
L('\t\t%s /* Build configuration list for PBXNativeTarget "%s" */ = {' % (widget_cfg_list, WIDGET_PROJ))
L('\t\t\tisa = XCConfigurationList;')
L('\t\t\tbuildConfigurations = (')
L('\t\t\t\t%s /* Debug */,' % widget_debug)
L('\t\t\t\t%s /* Release */,' % widget_release)
L('\t\t\t);')
L('\t\t\tdefaultConfigurationIsVisible = 0;')
L('\t\t\tdefaultConfigurationName = Release;')
L('\t\t};')
L("/* End XCConfigurationList section */")

L("\t};")
L('\trootObject = %s /* Project object */;' % project)
L("}")

out_dir = os.path.join(ROOT, "%s.xcodeproj" % PROJ)
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "project.pbxproj"), "w") as fh:
    fh.write("\n".join(lines) + "\n")
print("Wrote %s/project.pbxproj — app: %d+%d shared files, widget: %d+%d shared+app files" % (
    out_dir, len(swift_files), len(shared_files), len(widget_files), len(shared_files) + len(WIDGET_SHARED_FROM_APP)))

# ---- Shared scheme -------------------------------------------------------
# `xcodebuild archive` (used by CI to publish to TestFlight) only works off a
# scheme, never a bare -target — without this file `-list` shows no Schemes at
# all and archiving fails outright.
scheme_dir = os.path.join(out_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
scheme_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1520" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="%(target)s" BuildableName="%(proj)s.app" BlueprintName="%(proj)s" ReferencedContainer="container:%(proj)s.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="%(target)s" BuildableName="%(proj)s.app" BlueprintName="%(proj)s" ReferencedContainer="container:%(proj)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="%(target)s" BuildableName="%(proj)s.app" BlueprintName="%(proj)s" ReferencedContainer="container:%(proj)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
   </ArchiveAction>
</Scheme>
''' % {"target": target, "proj": PROJ}
with open(os.path.join(scheme_dir, "%s.xcscheme" % PROJ), "w") as fh:
    fh.write(scheme_xml)
print("Wrote %s/%s.xcscheme" % (scheme_dir, PROJ))
