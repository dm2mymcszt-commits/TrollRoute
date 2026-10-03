import Foundation
import CoreLocation

final class CLSimulationManager {
    static var operations: [String] = []
    static var samples: [CLLocation] = []
    func stopLocationSimulation() { Self.operations.append("stop") }
    func clearSimulatedLocations() { Self.operations.append("clear") }
    func appendSimulatedLocation(_ location: CLLocation) {
        Self.operations.append("append"); Self.samples.append(location)
    }
    func flush() { Self.operations.append("flush") }
    func startLocationSimulation() { Self.operations.append("start") }
}

final class TestClock {
    var time: TimeInterval = 0
    var tasks: [(id: UUID, time: TimeInterval, work: () -> Void)] = []
    var cancelled = Set<UUID>()
    var allWork: [() -> Void] = []
    func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        let id = UUID()
        tasks.append((id, time + delay, work)); allWork.append(work)
        return { self.cancelled.insert(id) }
    }
    func advance(to target: TimeInterval) {
        while let next = tasks.filter({ $0.time <= target }).min(by: { $0.time < $1.time }) {
            tasks.removeAll { $0.id == next.id }
            time = next.time
            if !cancelled.contains(next.id) { next.work() }
        }
        time = target
    }
}

@main struct InjectionTests {
    @MainActor static func main() {
        let clock = TestClock()
        var timezone = 0
        let driver = CoreLocationSimulationDriver(timezoneUpdate: { timezone += 1 }, now: { clock.time })
        var deliveries: [(TimeInterval, SessionLocation)] = []
        let queue = LocationInjectionQueue(now: { clock.time }, schedule: clock.schedule) { sample, reason in
            deliveries.append((clock.time, SessionLocation(sample)))
            driver.inject(sample, reason: reason)
        }
        func sample(_ number: Int, speed: Double = 500 / 3.6) -> CLLocation {
            RouteLocationSample.make(coordinate: CLLocationCoordinate2D(latitude: 44, longitude: Double(number) / 10000),
                altitude: 12.5, course: 90, speed: speed, timestamp: Date(timeIntervalSince1970: Double(number)))
        }
        // Old implementation restarted and notified once for each of these 140
        // inputs: 40 regular route ticks and 100 extra slider callbacks in 10 s.
        var inputs = 0
        var latest: CLLocation!
        for step in 0..<1000 {
            clock.advance(to: Double(step) / 100)
            if step % 25 == 0 {
                latest = sample(step); queue.submit(latest, reason: .continuous); inputs += 1
            }
            if step % 10 == 0 {
                latest = sample(step + 1, speed: Double(20 + step % 100) / 3.6)
                queue.submit(latest, reason: .continuous); inputs += 1
            }
        }
        clock.advance(to: 10.25)
        precondition(inputs == 140 && deliveries.count <= 41)
        for pair in zip(deliveries, deliveries.dropFirst()) {
            precondition(pair.1.0 - pair.0.0 >= 0.25 - 1e-9)
        }
        precondition(deliveries.last!.1 == SessionLocation(latest), "Trailing delivery keeps the newest complete sample")
        precondition(CLSimulationManager.operations.filter { $0 == "start" }.count == 1)
        precondition(CLSimulationManager.operations.filter { $0 == "stop" }.count == 1)
        precondition(timezone == 1, "Short bursts of continuous movement must not notify per sample")
        precondition(Array(CLSimulationManager.operations.prefix(5)) == ["stop", "clear", "append", "flush", "start"])
        precondition(CLSimulationManager.samples.allSatisfy { $0.courseAccuracy == 0 && $0.speedAccuracy == 0 && $0.altitude == 12.5 })
        print("PASS: 140 inputs / 10 s: old 140 starts + 140 timezone posts; new \(deliveries.count) deliveries, 1 start + 1 timezone post")

        queue.submit(sample(1500), reason: .jump)
        queue.submit(sample(1501), reason: .continuous)
        let staleWork = clock.allWork.last!
        queue.submit(sample(1800), reason: .jump)
        precondition(deliveries.last!.1 == SessionLocation(sample(1800)) && timezone == 3)
        staleWork() // Even a callback already dispatched before cancellation is harmless.
        clock.advance(to: 11)
        precondition(deliveries.last!.1 == SessionLocation(sample(1800)))
        queue.submit(sample(1801), reason: .continuous)
        queue.submit(sample(1802, speed: 0), reason: .stateChange)
        precondition(deliveries.last!.1.speed == 0 && deliveries.last!.1.courseAccuracy == -1)
        precondition(timezone == 3)
        queue.submit(sample(1803), reason: .stateChange) // Resume is immediate.
        precondition(deliveries.last!.1.speed == 500 / 3.6)
        queue.submit(sample(1804), reason: .continuous)
        let count = deliveries.count
        queue.stop(); driver.stop()
        clock.advance(to: 12)
        clock.allWork.forEach { $0() }
        precondition(deliveries.count == count && timezone == 4, "Stop must not allow any queued sample to restore spoofing")
        precondition(Array(CLSimulationManager.operations.suffix(3)) == ["stop", "clear", "flush"])
        queue.submit(sample(1900), reason: .continuous)
        precondition(timezone == 5 && CLSimulationManager.operations.filter { $0 == "start" }.count == 2)
        let operationsBeforeRelinquish = CLSimulationManager.operations
        driver.relinquish()
        precondition(CLSimulationManager.operations == operationsBeforeRelinquish)
        driver.inject(sample(2000), reason: .jump)
        precondition(Array(CLSimulationManager.operations.suffix(5)) == ["stop", "clear", "append", "flush", "start"])
        print("PASS: explicit jumps, latest-wins, cancellation race, pause/arrival/resume, Stop and restart; sample metadata unchanged")

        // The real adapter is mode-independent: test distance and elapsed time
        // at walking, cycling, driving, train and plane speeds across the date line.
        for kmh in [5.0, 20, 50, 130, 850, 1000] {
            var time = 0.0
            var posts = 0
            let moving = CoreLocationSimulationDriver(timezoneUpdate: { posts += 1 }, now: { time })
            let initialStarts = CLSimulationManager.operations.filter { $0 == "start" }.count
            var lastPost = 0.0
            for second in 0...3600 {
                time = Double(second)
                let degrees = time * kmh / 3.6 / 111_195
                let lon = (179.99 + degrees + 180).truncatingRemainder(dividingBy: 360) - 180
                let point = RouteLocationSample.make(coordinate: .init(latitude: 0, longitude: lon),
                    altitude: 100, course: 90, speed: kmh / 3.6, timestamp: Date(timeIntervalSince1970: time))
                let before = posts
                moving.inject(point, reason: .continuous)
                if posts > before && second > 0 {
                    precondition(time - lastPost >= 60, "Timezone notifications are bounded independently of speed")
                    lastPost = time
                }
            }
            precondition(posts > 1 && posts <= 61, "Every mode updates while travelling, never per sample")
            precondition(CLSimulationManager.operations.filter { $0 == "start" }.count == initialStarts + 1,
                         "Timezone updates must not restart location simulation")
            let last = CLSimulationManager.samples.last!
            precondition(last.speed == kmh / 3.6 && last.course == 90 && last.altitude == 100)
            let beforeRest = posts
            time += 3600
            moving.inject(last, reason: .continuous)
            let afterRest = posts
            // An unsent final displacement may cause one deferred update.
            precondition(afterRest <= beforeRest + 1)
            time += 3600
            moving.inject(last, reason: .stateChange)
            precondition(posts == afterRest, "Stationary samples must not keep requesting timezone changes")
            moving.inject(last, reason: .jump)
            precondition(posts == afterRest + 1, "Explicit jumps always notify, even without displacement")
            moving.stop()
            precondition(posts == afterRest + 2)
            moving.inject(last, reason: .continuous)
            precondition(posts == afterRest + 3, "New ownership starts with a fresh timezone notification")
            moving.relinquish()
            precondition(posts == afterRest + 3, "Relinquishing must not change the new owner's timezone")
        }
        print("PASS: long-route timezone updates at all mode speeds, date-line crossing, bounded frequency and no simulation restart")
    }
}
