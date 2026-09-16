//
//  LocSimManager.swift
//  TrollRoute
//
//  Developed by son3ra1n.
//

import Foundation
import CoreLocation

/// Creates the exact position and motion values of the simulated route model.
/// This describes Core Location data; it does not create a Core Motion activity
/// or control the activity/appearance that another app chooses to display.
enum RouteLocationSample {
    static func make(
        coordinate: CLLocationCoordinate2D,
        altitude: CLLocationDistance? = nil,
        course: CLLocationDirection,
        speed: CLLocationSpeed,
        timestamp: Date
    ) -> CLLocation {
        let validSpeed = speed.isFinite && speed >= 0
        let validCourse = course.isFinite && course >= 0 && course < 360
        return CLLocation(
            coordinate: coordinate,
            altitude: altitude?.isFinite == true ? altitude! : 0,
            horizontalAccuracy: 5,
            verticalAccuracy: altitude?.isFinite == true ? 5 : -1,
            course: validCourse ? course : -1,
            // The route model has an exact bearing while moving. At rest retain
            // the last numeric bearing, but do not describe it as a travel direction.
            courseAccuracy: validSpeed && speed > 0 && validCourse ? 0 : -1,
            speed: validSpeed ? speed : -1,
            // These are deterministic simulation values, not sensor estimates.
            // Negative accuracy means invalid to Core Location consumers.
            speedAccuracy: validSpeed ? 0 : -1,
            timestamp: timestamp
        )
    }
}

class LocSimManager {
    static let session = LocationSession(driver: CoreLocationSimulationDriver(),
                                         lease: .shared, requiresLease: true)
}

/// Starts once, then replaces the queued sample while the session stays active.
/// This private API path must also be checked on a physical TrollStore device.
final class CoreLocationSimulationDriver: LocationSimulationDriver {
    private let simManager = CLSimulationManager()
    private var running = false
    private let timezoneUpdate: () -> Void

    init(timezoneUpdate: @escaping () -> Void = CoreLocationSimulationDriver.postTimezoneUpdate) {
        self.timezoneUpdate = timezoneUpdate
    }

    /// Updates timezone
    static func postTimezoneUpdate(){
        CFNotificationCenterPostNotificationWithOptions(CFNotificationCenterGetDarwinNotifyCenter(), .init("AutomaticTimeZoneUpdateNeeded" as CFString), nil, nil, kCFNotificationDeliverImmediately);
    }
    
    func inject(_ location: CLLocation, reason: LocationInjectionReason) {
        let starting = !running
        if starting { simManager.stopLocationSimulation() }
        simManager.clearSimulatedLocations()
        simManager.appendSimulatedLocation(location)
        simManager.flush()
        if starting {
            simManager.startLocationSimulation()
            running = true
        }
        if starting || reason == .jump { timezoneUpdate() }
    }
    
    /// Stops location simulation
    func stop(){
        simManager.stopLocationSimulation()
        simManager.clearSimulatedLocations()
        simManager.flush()
        running = false
        timezoneUpdate()
    }

    func relinquish() { running = false }
}


struct EquatableCoordinate: Equatable {
    var coordinate: CLLocationCoordinate2D
    
    static func ==(lhs: EquatableCoordinate, rhs: EquatableCoordinate) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}
