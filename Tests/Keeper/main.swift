import Foundation
import CoreLocation

final class CLSimulationManager {
    static var operations: [String] = []
    static var samples: [CLLocation] = []
    func stopLocationSimulation() { Self.operations.append("stop") }
    func clearSimulatedLocations() { Self.operations.append("clear") }
    func appendSimulatedLocation(_ location: CLLocation) { Self.operations.append("append"); Self.samples.append(location) }
    func flush() { Self.operations.append("flush") }
    func startLocationSimulation() { Self.operations.append("start") }
}

@main struct KeeperTests {
    static func main() throws {
        var alive = false; var starts = 0; var stops = 0
        let keeper = KeeperLifecycle(running: { alive }, spawn: { alive = true; starts += 1 },
                                     terminate: { alive = false; stops += 1 })
        try keeper.ensureRunning(); try keeper.ensureRunning()
        precondition(starts == 1)
        try keeper.stop(); precondition(!alive && stops == 1)
        try keeper.ensureRunning(); precondition(starts == 2)
        print("PASS: fake spawner starts once, stops, and starts a new keeper")
    }
}
