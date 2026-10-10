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

enum KeeperDeliveryState {
    case checking, confirmed, matching, recovering, unavailable
}

@MainActor final class KeeperStatusModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = KeeperStatusModel()
    @Published var display = KeeperDisplay()
    @Published var checkedAt: Date?
    @Published var actionFeedback: String?
    @Published var deliveryState = KeeperDeliveryState.checking
    @Published var delivery = "System delivery has not been verified."
    @Published var notice: String?
    @Published var logText = "No keeper events recorded."
    @Published var notifications = true
    @Published var diagnosticRunning = false
    @Published var diagnosticResult = "No diagnostic test has run."
    var diagnosticSamples: [KeeperDiagnosticSample] = []
    private var diagnosticStart = 0.0
    private var diagnosticWallStart = Date.distantPast
    private var diagnosticWork: DispatchWorkItem?
    private var manager: CLLocationManager?
    private var observation: AnyCancellable?
    private var statusObservation: AnyCancellable?
    private var statusTimer: AnyCancellable?
    private var expected: [(Date, CLLocation)] = []
    private var markerVerified = false
    private var lost = false
    private var preview = false
    override init() { super.init() }
    init(preview: KeeperDisplay) { super.init(); self.preview = true; display = preview; checkedAt = Date() }

    var mapTitle: String {
        if checkedAt == nil { return "Checking protection" }
        if !display.running { return "Location protection unavailable" }
        switch deliveryState {
        case .checking: return "Waiting for system location"
        case .confirmed: return notice == nil ? "Simulated location verified" : "Simulation restored"
        case .matching: return "Position matches; simulation unverified"
        case .recovering: return "Restoring simulation"
        case .unavailable: return "Location check unavailable"
        }
    }
    var needsAttention: Bool {
        (checkedAt != nil && !display.running) || deliveryState == .recovering || deliveryState == .unavailable || notice != nil
    }

    func refresh() {
        guard !preview else { return }
        #if TROLLROUTE_KEEPER_UI
        defer { checkedAt = Date() }
        guard let container = KeeperFiles.container else {
            display = KeeperDisplay(detail: "Shared location storage is unavailable."); return
        }
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
    func checkProtection() {
        refresh()
        checkedAt = Date()
        actionFeedback = display.running ? "The keeper is running. It is watching for location service restarts." : display.detail
    }
    func setNotifications(_ enabled: Bool) {
        notifications = enabled
        #if TROLLROUTE_KEEPER_UI
        if let container = KeeperFiles.container { try? preferences(container).update { $0.notifications = enabled } }
        if enabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        #endif
    }
    #if TROLLROUTE_KEEPER_UI
    private func preferences(_ container: URL) -> SharedStateFile<KeeperPreferences> {
        SharedStateFile(url: KeeperFiles.directory(container).appendingPathComponent("keeper-preferences.json"), initial: { KeeperPreferences() })
    }
    #endif
    func setForeground(_ foreground: Bool) {
        guard !preview else { return }
        #if TROLLROUTE_KEEPER_UI
        if !foreground {
            manager?.stopUpdatingLocation(); observation = nil; statusObservation = nil; statusTimer = nil
            if diagnosticRunning { finishDiagnostic(interrupted: true) }
            return
        }
        LocSimManager.session.refreshShared()
        deliveryState = .checking
        delivery = "Waiting for a fresh system location."
        KeeperClient.shared.resumeIfCurrentBoot()
        refresh()
        if manager == nil {
            manager = CLLocationManager(); manager?.delegate = self
            manager?.desiredAccuracy = kCLLocationAccuracyBest
        }
        statusObservation = NotificationCenter.default.publisher(for: .keeperStateChanged).sink { [weak self] _ in self?.refresh() }
        statusTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in KeeperClient.shared.resumeIfCurrentBoot(); self?.refresh() }
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
        let error = error as NSError
        // locationUnknown is transient: Core Location keeps trying without a restart.
        if error.domain == kCLErrorDomain && error.code == CLError.locationUnknown.rawValue {
            if !lost { deliveryState = .checking; delivery = "Waiting for a fresh system location." }
            return
        }
        deliveryState = .unavailable
        delivery = error.domain == kCLErrorDomain && error.code == CLError.denied.rawValue
            ? "Location access is unavailable. Check Location Services and the app's location permission."
            : "System location could not be checked (error \(error.code))."
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        #if TROLLROUTE_KEEPER_UI
        guard LocSimManager.session.isActive else { return }
        for location in locations {
            let flag = location.sourceInformation?.isSimulatedBySoftware
            let sample = LocSimManager.session.current?.location
            let candidates = expected.filter { Date().timeIntervalSince($0.0) < 5 }.map { $0.1 } + (sample.map { [$0] } ?? [])
            let tolerance = max(15, min(100, location.horizontalAccuracy))
            let matches = location.horizontalAccuracy >= 0 && candidates.contains { location.distance(from: $0) <= tolerance }
            if diagnosticRunning {
                diagnosticSamples.append(KeeperDiagnosticSample(received: Date(), uptime: ProcessInfo.processInfo.systemUptime, timestamp: location.timestamp, simulated: flag, matches: matches))
                continue
            }
            // Ignore delayed cached updates in health monitoring, but retain ALL in diagnostics.
            guard abs(location.timestamp.timeIntervalSinceNow) < 5 else { continue }
            if flag == true && matches { markerVerified = true }
            let confirmed = flag == true && matches
            let mismatch = !matches || (markerVerified && flag == false)
            if mismatch {
                deliveryState = .recovering
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
                deliveryState = confirmed ? .confirmed : .matching
                if lost && confirmed { notice = "Location simulation was lost and is now confirmed restored." }
                delivery = confirmed ? (lost ? "Simulation was lost and is now confirmed restored." : "System reports a simulated location.") :
                    "System position matches the request; its simulation marker is unverified."
                lost = false
            }
        }
        #endif
    }
    func restartProtection() {
        refresh()
        if display.running { actionFeedback = "The keeper is already running. No second keeper was started."; return }
        #if TROLLROUTE_KEEPER_UI
        LocSimManager.session.refreshShared()
        guard LocSimManager.session.isActive else { actionFeedback = "Set a simulated location before starting the keeper."; return }
        do {
            try KeeperClient.shared.ensureRunning(forceCheck: true)
            refresh()
            actionFeedback = display.running ? "The keeper has started." : display.detail
        } catch { actionFeedback = "Location keeper could not start (error \((error as NSError).code))." }
        refresh()
        #endif
    }
    func stop() {
        #if TROLLROUTE_KEEPER_UI
        finishDiagnostic(interrupted: true)
        LocSimManager.session.stop(); notice = nil; refresh()
        if let error = LocSimManager.session.error { delivery = error }
        #endif
    }
    func reactivate() {
        #if TROLLROUTE_KEEPER_UI
        guard let sample = LocSimManager.session.lastKnown else { return }
        LocSimManager.session.receive(sample.stationaryLocation, kind: .stationary, newIntent: true)
        refresh()
        #endif
    }
    func beginDiagnostic() {
        #if TROLLROUTE_KEEPER_UI
        guard !diagnosticRunning, LocSimManager.session.isActive,
              let container = KeeperFiles.container else { diagnosticResult = "Set a simulated location before running the test."; return }
        do { try KeeperClient.shared.ensureRunning() } catch { diagnosticResult = "The keeper is not available. No restart was requested."; return }
        guard let manager = manager,
              manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            diagnosticResult = "Location access is required to measure delivery. No restart was requested."; return
        }
        diagnosticSamples = []; diagnosticStart = ProcessInfo.processInfo.systemUptime; diagnosticWallStart = Date()
        diagnosticRunning = true; diagnosticResult = "Measuring for 15 seconds. Keep TrollRoute in the foreground."
        manager.startUpdatingLocation()
        let work = DispatchWorkItem { [weak self] in self?.finishDiagnostic() }
        diagnosticWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        // Do not block delivery callbacks while the privileged relay starts.
        DispatchQueue.global(qos: .userInitiated).async {
            let rc = TRSpawn(KeeperFiles.executable, ["--keeper-relay", "diagnose", container.path], false, true)
            if rc != 0 { DispatchQueue.main.async { [weak self] in
                self?.finishDiagnostic(interrupted: true)
                self?.diagnosticResult += "\nRestart command failed (error \(rc))."
            } }
        }
        #endif
    }
    func finishDiagnostic(interrupted: Bool = false) {
        guard diagnosticRunning else { return }
        diagnosticRunning = false; diagnosticWork?.cancel(); diagnosticWork = nil
        #if TROLLROUTE_KEEPER_UI
        let end = ProcessInfo.processInfo.systemUptime
        let events = KeeperFiles.container.flatMap { try? KeeperLog(directory: KeeperFiles.directory($0)).read().events } ?? []
        diagnosticResult = KeeperDiagnosticReport.render(start: diagnosticStart, end: end,
            samples: diagnosticSamples, events: events.filter { $0.time >= diagnosticWallStart && $0.uptime >= diagnosticStart && $0.uptime <= end },
            markerVerified: markerVerified, interrupted: interrupted)
        refresh()
        #endif
    }
}

struct KeeperSettingsSection: View {
    @ObservedObject var model: KeeperStatusModel
    @State private var showingLog = false
    var body: some View {
        Section("Location keeper") {
            HStack { Text("Keeper"); Spacer(); Text(model.checkedAt == nil ? "Checking..." : (model.display.running ? "Running" : "Stopped")).foregroundColor(.secondary) }
            if let started = model.display.started { HStack { Text("Running since"); Spacer(); Text(started, style: .date); Text(started, style: .time) } }
            Text(model.display.detail).font(.caption)
            HStack { Text("Service restarts detected"); Spacer(); Text("\(model.display.restarts)") }
            if let date = model.display.lastRestart { HStack { Text("Last restart"); Spacer(); Text(date, style: .date); Text(date, style: .time) } }
            Text(model.delivery).font(.caption)
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundColor(.orange)
                Button("Dismiss notice") { model.notice = nil }
            }
            Toggle("Notify when location service restarts", isOn: Binding(get: { model.notifications }, set: { model.setNotifications($0) }))
            Button("Check keeper") { model.checkProtection() }
            if let checked = model.checkedAt { HStack { Text("Last checked"); Spacer(); Text(checked, style: .time) }.font(.caption).foregroundColor(.secondary) }
            Button(model.display.running ? "Keeper is already running" : "Start keeper for active location") { model.restartProtection() }
                .disabled(model.display.running)
            Button("Stop simulation and keeper", role: .destructive) { model.stop() }
            Button("View and share log") { model.refresh(); showingLog = true }
        }
        .onAppear { model.refresh() }
        .sheet(isPresented: $showingLog) { KeeperLogView(text: model.logText) }
        .alert("Location keeper", isPresented: Binding(get: { model.actionFeedback != nil }, set: { if !$0 { model.actionFeedback = nil } })) {
            Button("OK", role: .cancel) { model.actionFeedback = nil }
        } message: { Text(model.actionFeedback ?? "") }
    }
}

struct KeeperMapStatus: View {
    @ObservedObject var model: KeeperStatusModel
    var openSettings: () -> Void
    var body: some View {
        Button(action: openSettings) {
            HStack(spacing: 8) {
                Image(systemName: model.needsAttention ? "exclamationmark.shield" : "location")
                    .foregroundColor(model.needsAttention ? .orange : .secondary)
                Text(model.mapTitle).font(.caption).fontWeight(.medium)
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open Settings for location delivery and keeper details")
        .padding(.horizontal, 16).padding(.bottom, 32)
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

struct KeeperDiagnosticsSection: View {
    @ObservedObject var model: KeeperStatusModel
    @State private var confirm = false
    @State private var share = false
    var body: some View {
        Section("Deliberate restart test") {
            Text("This test restarts the location service once. Your real position may be visible. First set the simulated location at your real position. Keep this app open during the test.")
            Button(model.diagnosticRunning ? "Measuring..." : "Restart service and measure", role: .destructive) { confirm = true }
                .disabled(model.diagnosticRunning)
            Text(model.diagnosticResult).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Button("Share test result") { share = true }.disabled(model.diagnosticRunning)
        }
        .alert("Your real position may be revealed", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restart once and measure", role: .destructive) { model.beginDiagnostic() }
        } message: { Text("Set your simulated position at your real position first. This test cannot guarantee privacy. Continue only when you are ready to measure.") }
        .sheet(isPresented: $share) { KeeperShareText(text: model.diagnosticResult) }
    }
}
