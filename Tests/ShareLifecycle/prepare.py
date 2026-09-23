"""Actual app/share views; replace only privileged and container dependencies."""
from pathlib import Path
import plistlib
import sys

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

def source(path):
    return Path(path).read_text(encoding="utf-8")

def save(name, text):
    (out / name).write_text(text, encoding="utf-8")

def replace(text, old, new, count=1):
    assert text.count(old) == count, (old, text.count(old))
    return text.replace(old, new)

sample = source('TrollRoute/LocSim/LocSimManager.swift')
save('RouteLocationSample.swift', sample.split('class LocSimManager {')[0])
fixture = source('Tests/RouteEngine/EngineTests.swift').split('@main final class EngineApp')[0]
fixture = replace(fixture, 'FileManager.default.temporaryDirectory.appendingPathComponent(domain)', 'qaRoot.appendingPathComponent("owner")')
save('EngineFixture.swift', fixture)

# Keep production presentation, lifecycle handlers, queue consumption and receipts.
view = source('TrollRoute/LocSim/LocSimView.swift').replace('import AlertKit', '')
view = replace(view, 'RouteRuntime.shared.simulator', 'QAFixture.shared.engine!')
view = replace(view, 'LocSimManager.session', 'QAFixture.shared.owner')
view = view.replace('SharedPlaceInbox()', 'SharedPlaceInbox(container: qaRoot)')
view = replace(view, 'sharedEndpoint = saved\n                    base = nil', '''sharedEndpoint = saved
                    try Data(String(Date().timeIntervalSince(request.created)).utf8).write(to: qaRoot.appendingPathComponent("accepted-" + request.id.uuidString))
                    base = nil''')
save('LocSimView.swift', view)
for name in ['RouteSimView.swift', 'FavoritesView.swift']:
    save(name, source('TrollRoute/LocSim/' + name).replace('import AlertKit', ''))
bookmarks = source('TrollRoute/LocSim/BookMark/BookMarkHelper.swift')
save('Bookmarks.swift', replace(bookmarks, 'FavoritesStore.shared', 'Optional(qaFavorites)'))
share = source('TrollRoute/LocSim/SharedPlace.swift')
share = replace(share, 'store: FavoritesStore? = .shared', 'store: FavoritesStore? = qaFavorites')
save('SharedPlace.swift', share)
view = source('TrollRoute/LocSim/SharePlaceView.swift')
save('SharePlaceView.swift', view.replace('SharedPlaceInbox()', 'SharedPlaceInbox(container: qaRoot)'))
app = out / 'ShareLifecycle.app'
app.mkdir(exist_ok=True)
with (app / 'Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='local.trollroute.sharelifecycle', CFBundleExecutable='ShareLifecycle',
        CFBundleName='ShareLifecycle', CFBundlePackageType='APPL', MinimumOSVersion='17.0',
        UIDeviceFamily=[1], UILaunchScreen={}, UIBackgroundModes=['location'],
        NSLocationWhenInUseUsageDescription='Exercise shared-location lifecycle.',
        NSLocationAlwaysAndWhenInUseUsageDescription='Exercise shared-location lifecycle.'), f)
