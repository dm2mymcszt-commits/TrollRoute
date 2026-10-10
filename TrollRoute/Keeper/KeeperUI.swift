import SwiftUI
import CoreLocation
import Combine
import UserNotifications

struct KeeperDisplay {
    var running = false
    var started: Date?
    var restarts = 0
    var lastRestart: Date?
    var detail = "Location keeper is not running."
}

@MainActor final class KeeperStatusModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = KeeperStatusModel()
    @Published var display = KeeperDisplay()
    @Published var delivery = "System delivery has not been verified."
    @Published var notice: String?
    @Published var logText = "No keeper events recorded."
    @Published var notifications = true
    @Published var diagnosticRunning = false
    @Published var diagnosticResult = "No diagnostic test has run."
    var diagnosticSamples: [(received: Date, uptime: TimeInterval, simulated: Bool?, matches: Bool)] = []
    private var manager: CLLocationManager?
    private var observation: AnyCancellable?
    private var statusObservation: AnyCancellable?
    private var statusTimer: AnyCancellable?
    private var expected: [(Date, CLLocation)] = []
    private var markerVerified = false
    private var lost = false
    private var preview = false
    override init() { super.init() }
    init(preview: KeeperDisplay) { super.init(); self.preview = true; display = preview }

    func refresh() {
        guard !preview else { return }
        #if TROLLROUTE_APP
        guard let container = KeeperFiles.container else { display.detail = "Shared location storage is unavailable."; return }
        let record = KeeperFiles.read(container)
        display.running = KeeperFiles.locked(container) && record?.error == 0
        display.started = display.running ? record?.started : nil
        display.detail = display.running ? "Watching for location service restarts." : "Location keeper is not running. Protection is unavailable."
        if let error = record?.error, error != 0 { display.detail = "Keeper protection failed (error \(error))." }
        let log = KeeperLog(directory: KeeperFiles.directory(container))
        if let journal = try? log.read() {
            display.restarts = journal.restarts; display.lastRestart = journal.lastRestart
            logText = journal.events.isEmpty ? "No keeper events recorded." : journal.events.map(\.line).joined(separator: "\n")
        }
        notifications = (try? preferences(container).read().notifications) ?? true
        #endif
    }
    func setNotifications(_ enabled: Bool) {
        notifications = enabled
        #if TROLLROUTE_APP
        if let container = KeeperFiles.container { try? preferences(container).update { $0.notifications = enabled } }
        if enabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        #endif
    }
    #if TROLLROUTE_APP
    private func preferences(_ container: URL) -> SharedStateFile<KeeperPreferences> {
        SharedStateFile(url: KeeperFiles.directory(container).appendingPathComponent("keeper-preferences.json"), initial: { KeeperPreferences() })
    }
    #endif
    func setForeground(_ foreground: Bool) {
        guard !preview else { return }
        #if TROLLROUTE_APP
        if !foreground {
            manager?.stopUpdatingLocation(); observation = nil; statusObservation = nil; statusTimer = nil
            if diagnosticRunning { finishDiagnostic(interrupted: true) }
            return
        }
        LocSimManager.session.refreshShared()
        KeeperClient.shared.resumeIfCurrentBoot()
        refresh()
        if manager == nil {
            manager = CLLocationManager(); manager?.delegate = self
            manager?.desiredAccuracy = kCLLocationAccuracyBest
        }
        statusObservation = NotificationCenter.default.publisher(for: .keeperStateChanged).sink { [weak self] _ in self?.refresh() }
        statusTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
        observation = LocSimManager.session.$snapshot.sink { [weak self] snapshot in
            guard let self = self else { return }
            if let current = snapshot.current {
                self.expected.append((Date(), current.location))
                self.expected.removeAll { Date().timeIntervalSince($0.0) > 5 }
                if self.expected.count > 64 { self.expected.removeFirst(self.expected.count - 64) }
                self.manager?.startUpdatingLocation()
            } else { self.expected.removeAll(); self.manager?.stopUpdatingLocation(); self.delivery = "No active simulated location." }
        }
        if notifications && LocSimManager.session.isActive {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        #endif
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delivery = "System location could not be checked (error \((error as NSError).code))."
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        #if TROLLROUTE_APP
        guard LocSimManager.session.isActive else { return }
        for location in locations {
            let flag = location.sourceInformation?.isSimulatedBySoftware
            let sample = LocSimManager.session.current?.location
            let candidates = expected.filter { Date().timeIntervalSince($0.0) < 5 }.map { $0.1 } + (sample.map { [$0] } ?? [])
            let tolerance = max(15, min(100, location.horizontalAccuracy))
            let matches = location.horizontalAccuracy >= 0 && candidates.contains { location.distance(from: $0) <= tolerance }
            if diagnosticRunning {
                diagnosticSamples.append((Date(), ProcessInfo.processInfo.systemUptime, flag, matches))
                continue
            }
            // Ignore delayed cached updates in health monitoring, but retain ALL in diagnostics.
            guard abs(location.timestamp.timeIntervalSinceNow) < 5 else { continue }
            if flag == true && matches { markerVerified = true }
            let confirmed = flag == true && matches
            let mismatch = !matches || (markerVerified && flag == false)
            if mismatch {
                delivery = "System position does not match the simulation. Restoration requested."
                if !lost {
                    lost = true
                    notice = "The system delivered a position inconsistent with the simulation. Restoration was requested."
                    do {
                        _ = try LocationLeaseStore.shared?.restoreCurrent {
                            CoreLocationSimulationDriver().inject($0, reason: .stateChange)
                        }
                    } catch { delivery = "Simulation was lost and restoration failed. Try setting your location again." }
                }
            } else {
                if lost && confirmed { notice = "Location simulation was lost and is now confirmed restored." }
                delivery = confirmed ? (lost ? "Simulation was lost and is now confirmed restored." : "System reports a simulated location.") :
                    "System position matches the request; its simulation marker is unverified."
                lost = false
            }
        }
        #endif
    }
    func restartProtection() {
        #if TROLLROUTE_APP
        do { try KeeperClient.shared.ensureRunning() } catch { delivery = "Location keeper could not start (error \((error as NSError).code))." }
        refresh()
        #endif
    }
    func stop() {
        #if TROLLROUTE_APP
        LocSimManager.session.stop(); notice = nil; refresh()
        if let error = LocSimManager.session.error { delivery = error }
        #endif
    }
    func reactivate() {
        #if TROLLROUTE_APP
        guard let sample = LocSimManager.session.lastKnown else { return }
        LocSimManager.session.receive(sample.stationaryLocation, kind: .stationary, newIntent: true)
        refresh()
        #endif
    }
    func beginDiagnostic() { /* Implemented by the explicit diagnostic action. */ }
    func finishDiagnostic(interrupted: Bool = false) { diagnosticRunning = false }
}

struct KeeperSettingsSection: View {
    @ObservedObject var model: KeeperStatusModel
    @State private var showingLog = false
    var body: some View {
        Section("Location keeper") {
            HStack { Text("Keeper"); Spacer(); Text(model.display.running ? "Running" : "Stopped").foregroundColor(.secondary) }
            if let started = model.display.started { HStack { Text("Running since"); Spacer(); Text(started, style: .date); Text(started, style: .time) } }
            Text(model.display.detail).font(.caption)
            HStack { Text("Service restarts detected"); Spacer(); Text("\(model.display.restarts)") }
            if let date = model.display.lastRestart { HStack { Text("Last restart"); Spacer(); Text(date, style: .date); Text(date, style: .time) } }
            Text(model.delivery).font(.caption)
            Toggle("Notify when location service restarts", isOn: Binding(get: { model.notifications }, set: { model.setNotifications($0) }))
            Button("Check keeper") { model.refresh() }
            Button("Start keeper for active location") { model.restartProtection() }
            Button("Stop simulation and keeper", role: .destructive) { model.stop() }
            Button("View and share log") { model.refresh(); showingLog = true }
        }
        .onAppear { model.refresh() }
        .sheet(isPresented: $showingLog) { KeeperLogView(text: model.logText) }
    }
}
private struct KeeperLogView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    var body: some View {
        NavigationView {
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                .navigationTitle("Keeper log")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("Share") { sharing = true } }
                }
                .sheet(isPresented: $sharing) { KeeperShareText(text: text) }
        }
    }
}
private struct KeeperShareText: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
struct KeeperSettingsPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            Form { KeeperSettingsSection(model: KeeperStatusModel(preview: .init())) }.previewDisplayName("Keeper stopped")
            Form { KeeperSettingsSection(model: KeeperStatusModel(preview: .init(running: true, started: Date(), restarts: 2,
                lastRestart: Date(), detail: "Watching for location service restarts."))) }.previewDisplayName("Keeper running")
        }
    }
}
