"""Generate a standalone XCTest UI runner for the installed production-view host.

No third-party project generator, app entitlements or location injection needed.
"""
from pathlib import Path
import plistlib
import sys

folder = Path(sys.argv[1]).resolve()
test_name = sys.argv[3] if len(sys.argv) > 3 else 'MapGestureTests'
source_path = sys.argv[2] if len(sys.argv) > 2 else 'Tests/MapWorkspace/GestureTests.swift'
project = folder / f'{test_name}.xcodeproj'
project.mkdir(parents=True, exist_ok=True)
objects = {}
def obj(identifier, isa, **values):
    objects[identifier] = dict(isa=isa, **values)
    return identifier

source = obj('A00000000000000000000001', 'PBXFileReference', lastKnownFileType='sourcecode.swift',
             path=str(Path(source_path).resolve()), sourceTree='<absolute>')
product = obj('A00000000000000000000002', 'PBXFileReference', explicitFileType='wrapper.cfbundle',
              path=f'{test_name}.xctest', sourceTree='BUILT_PRODUCTS_DIR')
group = obj('A00000000000000000000003', 'PBXGroup', children=[source, product], sourceTree='<group>')
buildfile = obj('A00000000000000000000004', 'PBXBuildFile', fileRef=source)
test_sources = [buildfile]
for index, path in enumerate(sys.argv[4:]):
    ref = obj(f'{0xB00000000000000000000000 + index * 2:024X}', 'PBXFileReference',
              lastKnownFileType='sourcecode.swift', path=str(Path(path).resolve()), sourceTree='<absolute>')
    objects[group]['children'].append(ref)
    test_sources.append(obj(f'{0xB00000000000000000000001 + index * 2:024X}', 'PBXBuildFile', fileRef=ref))
sources = obj('A00000000000000000000005', 'PBXSourcesBuildPhase', buildActionMask=2147483647,
              files=test_sources, runOnlyForDeploymentPostprocessing=0)
settings = dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.0', SWIFT_VERSION='5.0',
                TARGETED_DEVICE_FAMILY='1,2', GENERATE_INFOPLIST_FILE='YES',
                PRODUCT_BUNDLE_IDENTIFIER='local.trollroute.mapgesturetests',
                PRODUCT_NAME='$(TARGET_NAME)', CODE_SIGNING_ALLOWED='NO',
                SWIFT_OPTIMIZATION_LEVEL='-Onone')
config = obj('A00000000000000000000006', 'XCBuildConfiguration', name='Debug', buildSettings=settings)
configs = obj('A00000000000000000000007', 'XCConfigurationList', buildConfigurations=[config],
              defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
target = obj('A00000000000000000000008', 'PBXNativeTarget', name=test_name,
             buildConfigurationList=configs, buildPhases=[sources], buildRules=[], dependencies=[],
             productName=test_name, productReference=product,
             productType='com.apple.product-type.bundle.ui-testing')
root = obj('A00000000000000000000009', 'PBXProject', attributes=dict(LastUpgradeCheck='1640'),
           buildConfigurationList=configs, compatibilityVersion='Xcode 14.0', developmentRegion='en',
           hasScannedForEncodings=0, knownRegions=['en', 'Base'], mainGroup=group,
           projectDirPath='', projectRoot='', targets=[target])
(project / 'project.pbxproj').write_bytes(plistlib.dumps(dict(archiveVersion='1', classes={},
    objectVersion='56', objects=objects, rootObject=root)))
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{test_name}.xctest" BlueprintName="{test_name}" ReferencedContainer="container:{test_name}.xcodeproj"/>'
(schemes / f'{test_name}.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{reference}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference}</TestableReference></Testables></TestAction>
</Scheme>''', encoding='utf-8')
