import UIKit
import MapKit
import UserNotifications

func testNotificationContent() {
    let suite = "notification-adapter-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = RouteNotificationPreferences(defaults: defaults)
    for finished in [false, true] {
        for sensitive in [false, true] {
            preferences.finished = finished
            preferences.timeSensitive = sensitive
            let content = RouteNotifications.content("Returning to start", preferences: preferences)
            precondition((content != nil) == finished)
            if let content = content {
                precondition(content.title == "Route complete" && content.body == "Returning to start")
                precondition(content.sound != nil)
                precondition(content.interruptionLevel == (sensitive ? .timeSensitive : .active))
            }
        }
    }
    print("PASS: actual iOS notification content, suppression and interruption levels")
}

// Only the privileged output is replaced. The full production RouteSimulator,
// LocationSession, geometry, altitude and finish code execute in the simulator.
enum LocSimManager {
    static var session: LocationSession { fatalError("Inject the recording owner") }
}
final class EngineDriver: LocationSimulationDriver {
    var samples: [CLLocation] = []
    var stops = 0
    func inject(_ location: CLLocation, reason: LocationInjectionReason) { samples.append(location) }
    func stop() { stops += 1 }
}

final class EngineFixture {
    let suite: String
    let defaults: UserDefaults
    let settings: RouteFinishSettings
    let driver: EngineDriver
    let owner: LocationSession
    let lease: LocationLeaseStore
    let leaseDirectory: URL
    let altitude: AltitudeSettings
    var engine: RouteSimulator!
    var clock = 1000.0
    var notifications: [String] = []
    let a = CLLocationCoordinate2D(latitude: 44.8, longitude: -0.6)
    let b = CLLocationCoordinate2D(latitude: 44.81, longitude: -0.59)
    let c = CLLocationCoordinate2D(latitude: 45, longitude: 1)

    init(realtime: Bool = false) {
        let domain = "engine-tests-\(UUID().uuidString)"
        let storage = UserDefaults(suiteName: domain)!
        let recording = EngineDriver()
        suite = domain
        defaults = storage
        driver = recording
        settings = RouteFinishSettings(defaults: storage)
        let altitudeSettings = AltitudeSettings(defaults: storage)
        altitude = altitudeSettings
        altitudeSettings.setCustom(250)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        leaseDirectory = directory
        let authority = LocationLeaseStore(url: directory.appendingPathComponent("session.json"))
        lease = authority
        owner = LocationSession(driver: recording, defaults: storage, settings: altitudeSettings,
            injectionInterval: 0, lease: authority, lookup: { _ in nil }, batchLookup: { _ in nil })
        engine = RouteSimulator(locationSession: owner, finishDefaults: settings, stopDefaults: storage,
            now: { [unowned self] in realtime ? ProcessInfo.processInfo.systemUptime : self.clock },
            notifyCompletion: { [unowned self] in self.notifications.append($0) })
    }
    func prepare() {
        engine.clearCalculatedRoutes()
        engine.routeStart = a
        engine.routeEnd = b
        let coords = [a, b].map(CoordTransform.wgs84ToGcj02)
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        engine.availableRoutes = [RouteOption(route: RoutePath(polyline: polyline,
            distance: RouteSimulationMath.distance(a, b), expectedTravelTime: 300, name: "Fixture"), index: 0)]
        engine.selectRoute(at: 0)
        engine.updateSpeedKmh(50, for: .driving)
    }
    func close() {
        engine.stopSimulation()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: leaseDirectory)
    }
    func at(_ point: CLLocationCoordinate2D) -> Bool {
        guard let location = owner.current else { return false }
        return location.location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) < 0.1
    }
}

func testActivityStateAndCommands() {
    let f = EngineFixture()
    defer { f.close() }
    precondition(f.engine.activitySnapshot == nil)
    f.prepare()
    f.engine.configureFinish(RouteFinishConfiguration(action: .backAndForth))
    f.engine.startSimulation(startName: "Original start", destinationName: "Destination")
    let initial = f.engine.activitySnapshot!
    precondition(initial.destination == "Destination" && initial.progress == 0 && initial.leg == 1)
    precondition(!initial.paused && initial.speedKmh == 50 && initial.stop == nil)
    precondition(initial.remainingMeters > 0 && initial.remainingSeconds > 0)
    let sampleCount = f.driver.samples.count
    for _ in 0..<10 { _ = f.engine.activitySnapshot }
    precondition(f.driver.samples.count == sampleCount, "Display snapshots must never inject")
    let trip = initial.tripID
    func send(_ action: RouteActivityCommand.Action) -> RouteActivityCommand.Outcome {
        f.engine.performActivityCommand(.init(tripID: trip, action: action))
    }
    precondition(f.engine.performActivityCommand(.init(tripID: UUID(), action: .pause)) == .unavailable)
    precondition(!f.engine.isPaused)
    f.clock += 1; f.engine.advanceRoute()
    let moving = f.engine.activitySnapshot!
    precondition(moving.progress > initial.progress && moving.remainingMeters < initial.remainingMeters)
    f.engine.previewSeek(0.8)
    precondition(f.engine.activitySnapshot!.progress < 0.1, "Show actual motion, not finger preview")
    f.engine.seek(to: 0.46)
    precondition(abs(f.engine.activitySnapshot!.progress - 0.46) < 0.000001)
    let beforeSpeed = f.engine.activitySnapshot!
    f.engine.updateLiveSpeed(120)
    let afterSpeed = f.engine.activitySnapshot!
    precondition(afterSpeed.speedKmh == 120 && afterSpeed.remainingSeconds < beforeSpeed.remainingSeconds)
    precondition(afterSpeed.remainingMeters == beforeSpeed.remainingMeters)
    precondition(send(.pause) == .applied && send(.pause) == .applied)
    precondition(f.engine.activitySnapshot!.paused && f.owner.current!.speed == 0)
    let paused = f.engine.activitySnapshot!
    f.clock += 20; f.engine.advanceRoute()
    precondition(f.engine.activitySnapshot == paused, "Paused content must remain frozen")
    f.engine.seek(to: 0.1)
    precondition(f.engine.activitySnapshot!.paused && abs(f.engine.activitySnapshot!.progress - 0.1) < 0.000001)
    precondition(send(.resume) == .applied && send(.resume) == .applied)
    precondition(!f.engine.activitySnapshot!.paused && f.owner.current!.speed == 120 / 3.6)
    f.engine.seek(to: 1)
    let returning = f.engine.activitySnapshot!
    precondition(returning.tripID == trip && returning.destination == "Original start" && returning.leg == 2)
    precondition(returning.progress == 0 && returning.speedKmh == 120)
    f.engine.configureFinish(RouteFinishConfiguration(action: .stay))
    precondition(f.engine.activitySnapshot!.finishAction == "stay")
    precondition(f.engine.activitySnapshot!.destination == "Original start")
    precondition(send(.requestStop) == .applied)
    let capture = f.engine.stopRequest!
    precondition(send(.requestStop) == .applied && f.engine.stopRequest!.id == capture.id,
                 "Repeated Stop must not replace the press-time point")
    let content = f.engine.activitySnapshot!
    precondition(content.stop!.choices.map(\.id) == ["current", "start", "specific", "real"])
    precondition(content.stop!.preselection == "current")
    let encoded = try! JSONEncoder().encode(content)
    precondition(try! JSONDecoder().decode(RouteActivityState.self, from: encoded) == content)
    precondition(encoded.count < 3000, "Leave room for ActivityKit dates and attributes")
    precondition(f.engine.performActivityCommand(.init(tripID: trip, action: .cancelStop, requestID: UUID())) == .unavailable)
    precondition(f.engine.performActivityCommand(.init(tripID: trip, action: .cancelStop, requestID: capture.id)) == .applied)
    precondition(f.engine.activitySnapshot!.stop == nil && !f.engine.isPaused)
    precondition(f.engine.performActivityCommand(.init(tripID: trip, action: .chooseStop,
        requestID: capture.id, choice: "real")) == .unavailable)
    f.engine.seek(to: 1)
    precondition(f.engine.activitySnapshot == nil && f.at(f.a))
    precondition(send(.resume) == .unavailable)
    f.prepare(); f.engine.startSimulation()
    precondition(f.engine.activitySnapshot!.tripID != trip && send(.requestStop) == .unavailable)
    precondition(f.engine.activitySnapshot!.destination == String(format: "%.5f, %.5f", f.b.latitude, f.b.longitude))
    let longName = String(repeating: "\u{1F4CD}\u{0301}", count: 2000)
    precondition(RouteActivityState.destinationName(longName, fallback: "Fallback").utf8.count <= 384)
    precondition(RouteActivityState.destinationName(" \n", fallback: "Fallback") == "Fallback")

    for previous in [false, true] {
        let choices: [RouteStopAction] = previous ? RouteStopAction.defaults : [.current, .start, .specific, .real]
        for choice in choices {
            let test = EngineFixture()
            defer { test.close() }
            if previous {
                test.altitude.setCustom(-12.5)
                test.owner.receive(RouteLocationSample.make(coordinate: test.c, course: 0, speed: 0,
                    timestamp: Date()), kind: .stationary, newIntent: true)
            }
            test.defaults.set(RouteStopAction.start.rawValue, forKey: "routeStopDefault")
            test.prepare(); test.engine.startSimulation()
            test.altitude.setCustom(250)
            let id = test.engine.activitySnapshot!.tripID
            test.clock += 2
            precondition(test.engine.performActivityCommand(.init(tripID: id, action: .requestStop)) == .applied)
            let request = test.engine.stopRequest!
            let state = test.engine.activitySnapshot!
            precondition(state.stop!.preselection == "start" && state.stop!.choices.map(\.id) == choices.map(\.rawValue))
            precondition(state.stop!.choices.map(\.title) == choices.map(\.title))
            test.clock += 5; test.engine.advanceRoute()
            let command = RouteActivityCommand(tripID: id, action: .chooseStop,
                requestID: request.id, choice: choice.rawValue)
            let result = test.engine.performActivityCommand(command)
            if choice == .specific {
                precondition(result == .openPlacePicker(request.id) && test.engine.isSimulating)
                test.engine.confirmRouteStop(request.id, action: .specific,
                    place: RouteFinishDestination(name: "Picked", address: "", coordinate: test.c))
            } else { precondition(result == .applied) }
            precondition(test.engine.activitySnapshot == nil)
            switch choice {
            case .previous: precondition(test.at(test.c) && test.owner.current!.meters == -12.5)
            case .current: precondition(test.owner.current!.location.distance(from: request.current.location) < 0.001)
            case .start: precondition(test.at(test.a))
            case .specific: precondition(test.at(test.c))
            case .real: precondition(!test.owner.isActive && test.driver.stops == 1)
            }
            if choice != .real { precondition(test.owner.current!.speed == 0 && test.driver.stops == 0) }
            precondition(test.engine.performActivityCommand(command) == .unavailable, "Never replay a Stop outcome")
        }
    }
    // A shared move wins even if an old Live Activity is still on screen.
    let id = f.engine.activitySnapshot!.tripID
    let external = SessionLocation(RouteLocationSample.make(coordinate: f.c, altitude: 123,
        course: 0, speed: 0, timestamp: Date()))
    try! f.lease.move(UUID(), sample: external) { _ in }
    let count = f.driver.samples.count
    precondition(f.engine.performActivityCommand(.init(tripID: id, action: .pause)) == .unavailable)
    precondition(f.engine.activitySnapshot == nil && f.at(f.c) && f.driver.samples.count == count)
    print("PASS: Live Activity engine snapshots, current-leg endpoint, commands, both Stop matrices and stale lease rejection")
}

func testRouteFinishEngine() {
    let fixture = EngineFixture()
    defer { fixture.close() }
    fixture.prepare()
    fixture.engine.configureFinish(RouteFinishConfiguration(action: .returnOnce))
    precondition(fixture.settings.action == .stay)
    fixture.engine.startSimulation()
    precondition(fixture.engine.isSimulating && fixture.owner.current!.speed > 0)
    fixture.engine.seek(to: 1)
    precondition(fixture.engine.isSimulating && fixture.at(fixture.b))
    fixture.engine.seek(to: 1)
    precondition(!fixture.engine.isSimulating && fixture.at(fixture.a))
    precondition(fixture.owner.current!.speed == 0 && fixture.owner.current!.meters == 250)
    precondition(fixture.notifications == ["Returning to start", "Staying at the start"])
    fixture.prepare()
    precondition(fixture.engine.finishConfiguration.action == .stay, "Next prepared trip must use Settings")

    for returning in [false, true] {
        for action in RouteFinishAction.allCases {
            let f = EngineFixture()
            f.prepare()
            if returning { f.engine.configureFinish(RouteFinishConfiguration(action: .returnOnce)) }
            f.engine.startSimulation()
            if returning { f.engine.seek(to: 1) }
            let before = f.driver.samples.count
            let place = RouteFinishDestination(name: "Trip only", address: "", coordinate: f.c)
            f.engine.configureFinish(RouteFinishConfiguration(action: action, destination: place))
            precondition(f.driver.samples.count == before, "Editing completion must not inject or pause")
            precondition(f.settings.action == .stay && f.settings.destination == nil)
            f.clock += 1
            f.engine.advanceRoute()
            precondition(f.owner.current!.speed > 0 && f.owner.current!.meters == 250)
            f.engine.seek(to: 1)
            switch action {
            case .stay:
                precondition(!f.engine.isSimulating && f.at(returning ? f.a : f.b))
                precondition(f.owner.current!.speed == 0)
                precondition(f.notifications.last == (returning ? "Staying at the start" : "Staying at destination"))
            case .goToPlace:
                precondition(!f.engine.isSimulating && f.at(f.c) && f.owner.current!.speed == 0)
                precondition(f.owner.current!.meters == 250)
            case .stop:
                precondition(!f.engine.isSimulating && !f.owner.isActive)
            case .loop:
                precondition(f.engine.isSimulating && f.at(f.a) && f.owner.current!.speed > 0)
                f.engine.seek(to: 1)
                precondition(f.notifications.count == 1 && f.at(f.a))
            case .returnOnce:
                if returning { precondition(!f.engine.isSimulating && f.at(f.a)) }
                else {
                    precondition(f.engine.isSimulating && f.at(f.b))
                    f.engine.seek(to: 1)
                    precondition(!f.engine.isSimulating && f.at(f.a) && f.notifications.count == 2)
                }
            case .backAndForth:
                precondition(f.engine.isSimulating && f.at(returning ? f.a : f.b))
                f.engine.seek(to: 1)
                precondition(f.engine.isSimulating && f.at(returning ? f.b : f.a) && f.notifications.count == 1)
            }
            f.close()
        }
    }
}

func testRouteStopEngine() {
    for previous in [false, true] {
        for preferred in RouteStopAction.defaults {
            let f = EngineFixture()
            f.defaults.set(preferred.rawValue, forKey: "routeStopDefault")
            if previous {
                f.owner.receive(RouteLocationSample.make(coordinate: f.c, course: 90, speed: 12,
                    timestamp: Date()), kind: .joystick, newIntent: true)
            }
            f.prepare(); f.engine.startSimulation()
            f.clock += 2
            f.engine.requestRouteStop()
            let request = f.engine.stopRequest!
            precondition(request.choices == (previous ? RouteStopAction.defaults : [.current, .start, .specific, .real]))
            precondition(request.preselection == (!previous && preferred == .previous ? .current : preferred))
            precondition(f.engine.isSimulating && !f.engine.isPaused && f.owner.current!.speed > 0)
            f.clock += 3; f.engine.advanceRoute()
            precondition(f.owner.current!.location.distance(from: request.current.location) > 20,
                         "Dialog must not pause the route")
            f.engine.cancelRouteStop(request.id)
            precondition(f.engine.isSimulating && f.engine.stopRequest == nil && f.driver.stops == 0)
            f.engine.confirmRouteStop(request.id, action: .real)
            precondition(f.engine.isSimulating && f.driver.stops == 0, "Cancelled response is stale")
            f.close()
        }
        let choices: [RouteStopAction] = previous ? RouteStopAction.defaults : [.current, .start, .specific, .real]
        for action in choices {
            let f = EngineFixture()
            if previous {
                f.altitude.setCustom(-12.5)
                f.owner.receive(RouteLocationSample.make(coordinate: f.c, course: 90, speed: 12,
                    timestamp: Date()), kind: .joystick, newIntent: true)
            }
            f.prepare(); f.engine.startSimulation()
            f.altitude.setCustom(250)
            f.clock += 2; f.engine.requestRouteStop()
            let request = f.engine.stopRequest!
            f.clock += 5; f.engine.advanceRoute()
            let destination = RouteFinishDestination(name: "Specific", address: "", coordinate: f.c)
            f.engine.confirmRouteStop(request.id, action: action, place: destination)
            precondition(!f.engine.isSimulating && f.engine.stopRequest == nil)
            switch action {
            case .previous:
                precondition(f.at(f.c) && f.owner.current!.meters == -12.5,
                             "Previous altitude must not be replaced by today's profile")
            case .current:
                precondition(f.owner.current!.location.distance(from: request.current.location) < 0.001)
                precondition(f.owner.current!.meters == request.current.meters)
            case .start: precondition(f.at(f.a) && f.owner.current!.meters == 250)
            case .specific: precondition(f.at(f.c) && f.owner.current!.meters == 250)
            case .real: precondition(!f.owner.isActive && f.driver.stops == 1)
            }
            if action != .real {
                precondition(f.driver.stops == 0 && f.owner.snapshot.kind == .stationary)
                precondition(f.owner.current!.speed == 0 && f.owner.snapshot.beforeRoute == nil)
                f.altitude.setCustom(300)
                precondition(f.owner.current!.meters == 300, "An explicit altitude edit must still apply")
            }
            let delivered = f.driver.samples.count
            f.clock += 10; f.engine.advanceRoute()
            precondition(f.driver.samples.count == delivered, "Stopped engine cannot overwrite choice")
            f.prepare(); f.engine.startSimulation()
            f.engine.confirmRouteStop(request.id, action: .real)
            precondition(f.engine.isSimulating, "Old trip dialog cannot stop a new trip")
            f.close()
        }
    }
    let f = EngineFixture()
    defer { f.close() }
    f.prepare(); f.engine.startSimulation(); f.engine.togglePause()
    f.engine.requestRouteStop()
    let paused = f.engine.stopRequest!
    f.engine.cancelRouteStop(paused.id)
    precondition(f.engine.isPaused && f.owner.current!.speed == 0)
    f.engine.requestRouteStop()
    f.engine.seek(to: 1)
    precondition(f.engine.stopRequest == nil, "Natural final arrival invalidates the dialog")
}

func testMovingScrubEngine() {
    let f = EngineFixture()
    defer { f.close() }
    f.prepare(); f.engine.startSimulation()
    f.clock += 1
    f.engine.previewSeek(0.46)
    let preview = f.engine.previewPosition!
    let startProgress = f.engine.progress
    precondition(f.owner.current!.speed == 50 / 3.6)
    f.clock += 2; f.engine.advanceRoute()
    precondition(f.engine.progress > startProgress && f.engine.progress < 0.1)
    precondition(f.engine.previewPosition!.latitude == preview.latitude)
    precondition(f.owner.current!.speed == 50 / 3.6 && f.owner.current!.meters == 250)
    let count = f.driver.samples.count
    f.engine.previewSeek(0.7)
    precondition(f.driver.samples.count == count, "Moving a preview must not inject")
    f.engine.updateLiveSpeed(120)
    precondition(f.owner.current!.speed == 120 / 3.6)
    f.clock += 2; f.engine.advanceRoute()
    f.engine.seek(to: 0.46)
    precondition(abs(f.engine.progress - 0.46) < 0.000001 && f.engine.previewPosition == nil)
    precondition(f.owner.current!.speed == 120 / 3.6)
    f.engine.previewSeek(0.1); f.engine.seek(to: 0.1)
    precondition(abs(f.engine.progress - 0.1) < 0.000001)
    f.engine.previewSeek(0.8)
    let beforeCancel = f.driver.samples.count
    f.engine.cancelSeek()
    precondition(f.driver.samples.count == beforeCancel && f.engine.previewPosition == nil)
    f.clock += 1; f.engine.advanceRoute()
    precondition(f.engine.progress > 0.1 && f.owner.current!.speed > 0)
    f.engine.togglePause()
    let pausedAt = f.engine.progress
    f.engine.previewSeek(0.6)
    f.clock += 10; f.engine.advanceRoute()
    precondition(f.engine.progress == pausedAt && f.owner.current!.speed == 0)
    f.engine.seek(to: 0.6)
    precondition(f.engine.isPaused && abs(f.engine.progress - 0.6) < 0.000001 && f.owner.current!.speed == 0)
    f.engine.togglePause(); f.engine.previewSeek(1); f.engine.seek(to: 1)
    precondition(!f.engine.isSimulating && f.at(f.b) && f.owner.current!.speed == 0)
    precondition(f.notifications == ["Staying at destination"])

    f.prepare(); f.engine.configureFinish(RouteFinishConfiguration(action: .backAndForth)); f.engine.startSimulation()
    f.engine.previewSeek(0.4)
    f.clock += 100; f.engine.advanceRoute() // Cross the outbound leg with the finger held.
    precondition(f.engine.isSimulating && f.owner.current!.speed > 0)
    precondition(f.engine.previewPosition != nil)
    f.engine.seek(to: 0.4)
    precondition(abs(f.engine.progress - 0.4) < 0.000001 && f.owner.current!.speed > 0)
}

func testSharedMoveRevokesEngine() {
    // A takeover while idle must not erase the route the user has just prepared.
    do {
        let f = EngineFixture()
        defer { f.close() }
        f.owner.receive(RouteLocationSample.make(coordinate: f.a, course: 0, speed: 0,
            timestamp: Date()), kind: .stationary, newIntent: true)
        f.prepare()
        let external = SessionLocation(RouteLocationSample.make(coordinate: f.c, altitude: 123,
            course: 0, speed: 0, timestamp: Date()))
        try! f.lease.move(UUID(), sample: external) { _ in }
        f.engine.startSimulation()
        precondition(f.engine.isSimulating && f.owner.snapshot.beforeRoute == external)
        f.clock += 1; f.engine.advanceRoute()
        precondition(f.engine.progress > 0 && f.owner.current?.speed == 50 / 3.6)
    }
    for paused in [false, true] {
        let f = EngineFixture()
        defer { f.close() }
        f.prepare(); f.engine.configureFinish(RouteFinishConfiguration(action: .backAndForth))
        f.engine.startSimulation()
        if paused { f.engine.togglePause() }
        f.engine.requestRouteStop()
        let oldStop = f.engine.stopRequest!
        let count = f.driver.samples.count
        let sample = SessionLocation(RouteLocationSample.make(coordinate: f.c, altitude: 123,
            course: 0, speed: 0, timestamp: Date()))
        try! f.lease.move(UUID(), sample: sample) { _ in }
        // A stale dialog must not reclaim authority and restore real GPS.
        f.engine.confirmRouteStop(oldStop.id, action: .real)
        precondition(!f.engine.isSimulating && f.at(f.c) && f.owner.current?.meters == 123)
        f.clock += 1000; f.engine.advanceRoute()
        precondition(f.driver.samples.count == count && f.driver.stops == 0)
        precondition(f.notifications.isEmpty, "An externally ended route must not report natural arrival")
        f.prepare(); f.engine.startSimulation()
        precondition(f.engine.isSimulating && f.owner.snapshot.beforeRoute == sample)
        precondition(f.owner.current?.speed == 50 / 3.6 && f.owner.current?.meters == 250)
    }
}

func testLocationPermissionAdapter() {
    precondition(CLLocationManager().authorizationStatus == .authorizedWhenInUse,
                 "The engine suite must exercise foreground-started routes with WhenInUse")
    let pairs: [(CLAuthorizationStatus, LocationAuthorization)] = [
        (.notDetermined, .notDetermined), (.restricted, .restricted), (.denied, .denied),
        (.authorizedAlways, .authorizedAlways), (.authorizedWhenInUse, .authorizedWhenInUse)]
    for (system, expected) in pairs {
        for accuracy in [CLAccuracyAuthorization.fullAccuracy, .reducedAccuracy] {
            let model = LocationAccessStatus(registration: "System", coreAuthorization: system,
                coreAccuracy: accuracy, servicesEnabled: true)
            precondition(model.authorization == expected)
            precondition(model.accuracy == (accuracy == .fullAccuracy ? .fullAccuracy : .reducedAccuracy))
        }
    }
}

@main final class EngineApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.main.async {
            testLocationPermissionAdapter()
            testNotificationContent()
            testActivityStateAndCommands()
            testRouteFinishEngine()
            testRouteStopEngine()
            testMovingScrubEngine()
            testSharedMoveRevokesEngine()
            let text = "PASS: actual RouteSimulator finish actions, Route Stop choices/outcomes, moving/paused scrub, live speed during scrub, Cancel, reverse transition, endpoint completion, motion and altitude, shared-move revocation and restart\n"
            let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("results.txt")
            try! text.write(to: path, atomically: true, encoding: .utf8)
        }
        return true
    }
}
