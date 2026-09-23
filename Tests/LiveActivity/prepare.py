"""Build real ActivityKit/intent/widget code with a recording location driver.

Only the privileged engine dependency changes; system surfaces are not mocked.
"""
from pathlib import Path
import plistlib
import runpy
import sys

out = Path(sys.argv[1]).resolve()
runpy.run_path('Tests/ShareLifecycle/prepare.py', run_name='__main__')
# Leave enough route distance for actual system animations and speed/return
# interactions; the short engine-unit fixture would finish mid-UI test.
fixture = (out / 'EngineFixture.swift').read_text(encoding='utf-8')
old = 'let b = CLLocationCoordinate2D(latitude: 44.81, longitude: -0.59)'
assert fixture.count(old) == 1
(out / 'EngineFixture.swift').write_text(fixture.replace(old,
    'let b = CLLocationCoordinate2D(latitude: 44.9, longitude: -0.5)'), encoding='utf-8')
runtime = Path('TrollRoute/LiveActivity/RouteRuntime.swift').read_text(encoding='utf-8')
assert runtime.count('simulator = RouteSimulator()') == 1
(out / 'RouteRuntime.swift').write_text(runtime.replace('simulator = RouteSimulator()',
    'simulator = QAFixture.shared.engine!'), encoding='utf-8')
view = (out / 'LocSimView.swift').read_text(encoding='utf-8')
assert view.count('QAFixture.shared.engine!') == 1
(out / 'LocSimView.swift').write_text(view.replace('QAFixture.shared.engine!',
    'RouteRuntime.shared.simulator'), encoding='utf-8')
host_support = Path('Tests/ShareLifecycle/Host.swift').read_text(encoding='utf-8').split('@main struct')[0]
# Simulator UI tests share a temporary directory with the recording owner.
(out / 'Support.swift').write_text(host_support, encoding='utf-8')

app_files = [
    'TrollRoute/Storage/SharedPreferences.swift', 'TrollRoute/Storage/FavoritesStore.swift',
    'TrollRoute/LocSim/PlaceModels.swift', 'TrollRoute/LocSim/PlaceInput.swift',
    'TrollRoute/LocSim/AddressQuery.swift', 'TrollRoute/LocSim/PlaceSearch.swift',
    'TrollRoute/LocSim/CoordTransform.swift', 'TrollRoute/LocSim/RouteSimulator.swift',
    'TrollRoute/LocSim/LocationSession.swift', 'TrollRoute/LocSim/RouteFinish.swift',
    'TrollRoute/LocSim/RouteStop.swift', 'TrollRoute/LocSim/RouteElevation.swift',
    'TrollRoute/LocSim/Altitude.swift', 'TrollRoute/LocSim/AltitudeSheet.swift',
    'TrollRoute/LocSim/RouteFinishControls.swift', 'TrollRoute/LocSim/RouteStopDialog.swift',
    'TrollRoute/LocSim/CustomMapView.swift', 'TrollRoute/LocSim/FloatingQuickMenu.swift',
    'TrollRoute/LocSim/MapMoveConfirmation.swift', 'TrollRoute/LocSim/MainStopConfirmation.swift',
    'TrollRoute/LocSim/LongPressRoute.swift', 'TrollRoute/LocSim/GPXParser.swift',
    'TrollRoute/LocSim/JoystickView.swift', 'TrollRoute/LocSim/RouteLocationPicker.swift',
    'TrollRoute/LocSim/FavoritePlaceEditor.swift', 'TrollRoute/SettingsView.swift', 'TrollRoute/LocationAccess.swift',
    'TrollRoute/LiveActivity/RouteActivityState.swift', 'TrollRoute/LiveActivity/RouteActivityAttributes.swift',
    'TrollRoute/LiveActivity/RouteActivityController.swift', 'TrollRoute/LiveActivity/RouteActivityIntent.swift',
    'Tests/LiveActivity/Host.swift',
] + [str(out / name) for name in ['RouteRuntime.swift', 'RouteLocationSample.swift', 'EngineFixture.swift',
    'Bookmarks.swift', 'SharedPlace.swift', 'SharePlaceView.swift', 'LocSimView.swift',
    'RouteSimView.swift', 'FavoritesView.swift', 'Support.swift']]
widget_files = ['TrollRoute/LiveActivity/RouteActivityState.swift',
    'TrollRoute/LiveActivity/RouteActivityAttributes.swift', 'TrollRoute/LiveActivity/RouteActivityIntent.swift',
    'TrollRouteActivity/TrollRouteActivity.swift']
objects = {}
def obj(kind, **values):
    key = f'{len(objects) + 1:024X}'
    objects[key] = dict(isa=kind, **values)
    return key

group = obj('PBXGroup', children=[], sourceTree='<group>')
def target(name, files, extension=False):
    refs = [obj('PBXFileReference', lastKnownFileType='sourcecode.swift',
        path=str(Path(path).resolve()), sourceTree='<absolute>') for path in files]
    objects[group]['children'] += refs
    phase = obj('PBXSourcesBuildPhase', buildActionMask=2147483647,
        files=[obj('PBXBuildFile', fileRef=ref) for ref in refs], runOnlyForDeploymentPostprocessing=0)
    product = obj('PBXFileReference', explicitFileType='wrapper.app-extension' if extension else 'wrapper.application',
        path=name + ('.appex' if extension else '.app'), sourceTree='BUILT_PRODUCTS_DIR')
    objects[group]['children'].append(product)
    identifier = 'local.trollroute.activityqa' + ('.activity' if extension else '')
    info = dict(CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)', CFBundleExecutable='$(EXECUTABLE_NAME)',
        CFBundleName=name, CFBundleDisplayName='Activity QA', CFBundleShortVersionString='3.0.0',
        CFBundleVersion='1', CFBundlePackageType='XPC!' if extension else 'APPL')
    if extension:
        info['NSExtension'] = dict(NSExtensionPointIdentifier='com.apple.widgetkit-extension')
    else:
        info.update(NSSupportsLiveActivities=True, UIDeviceFamily=[1], UILaunchScreen={},
            UIBackgroundModes=['location'], NSLocationWhenInUseUsageDescription='Exercise route activity.',
            NSLocationAlwaysAndWhenInUseUsageDescription='Exercise route activity.',
            CFBundleURLTypes=[dict(CFBundleURLSchemes=['trollroute'])])
    info_path = out / (name + '-Info.plist')
    info_path.write_bytes(plistlib.dumps(info))
    settings = dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.0', SWIFT_VERSION='5.0',
        TARGETED_DEVICE_FAMILY='1', GENERATE_INFOPLIST_FILE='NO', INFOPLIST_FILE=str(info_path),
        PRODUCT_BUNDLE_IDENTIFIER=identifier, PRODUCT_NAME=name, CODE_SIGNING_ALLOWED='NO',
        SWIFT_OPTIMIZATION_LEVEL='-Onone', SWIFT_ACTIVE_COMPILATION_CONDITIONS='' if extension else 'TROLLROUTE_APP',
        APPLICATION_EXTENSION_API_ONLY='YES' if extension else 'NO', ENABLE_DEBUG_DYLIB='NO',
        LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'])
    config = obj('XCBuildConfiguration', name='Debug', buildSettings=settings)
    configs = obj('XCConfigurationList', buildConfigurations=[config], defaultConfigurationIsVisible=0,
        defaultConfigurationName='Debug')
    target_id = obj('PBXNativeTarget', name=name, buildConfigurationList=configs,
        buildPhases=[phase], buildRules=[], dependencies=[], productName=name, productReference=product,
        productType='com.apple.product-type.app-extension' if extension else 'com.apple.product-type.application')
    return target_id, product, configs

widget, product, _ = target('TrollRouteActivity', widget_files, extension=True)
app, _, configs = target('LiveActivityQA', app_files)
embed = obj('PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='', dstSubfolderSpec=13,
    files=[obj('PBXBuildFile', fileRef=product, settings=dict(ATTRIBUTES=['RemoveHeadersOnCopy']))],
    runOnlyForDeploymentPostprocessing=0, name='Embed Extensions')
objects[app]['buildPhases'].append(embed)
objects[app]['dependencies'].append(obj('PBXTargetDependency', target=widget))
root = obj('PBXProject', attributes=dict(LastUpgradeCheck='1640'), buildConfigurationList=configs,
    compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0,
    knownRegions=['en'], mainGroup=group, projectDirPath='', projectRoot='', targets=[app, widget])
project = out / 'LiveActivityQA.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_bytes(plistlib.dumps(dict(archiveVersion='1', classes={},
    objectVersion='56', objects=objects, rootObject=root)))
print('Generated actual system ActivityKit/widget host with production intents and a recording engine')
