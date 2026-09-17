import SwiftUI
import CoreLocation

enum SharedPlaceAction: String, Codable, CaseIterable, Identifiable {
    case go, start, destination, favorite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .go: return "Go there now"
        case .start: return "Use as route start"
        case .destination: return "Use as route destination"
        case .favorite: return "Save as favorite"
        }
    }
    var icon: String {
        switch self {
        case .go: return "location.fill"
        case .start: return "a.circle"
        case .destination: return "b.circle"
        case .favorite: return "star"
        }
    }
}

// Transfers are WGS-84, just like Favorites. Map-space coordinates never cross
// the extension boundary. A locked ledger commits requests and receipts atomically.
struct SharedPlaceRequest: Codable, Identifiable, Equatable {
    let id: UUID
    let created: Date
    let action: SharedPlaceAction
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let approximate: Bool
    let source: SharedPlaceSource?
    var sourceTitle: String { (source ?? .text).title }

    init(place: RoutePlace, action: SharedPlaceAction) {
        id = UUID(); created = Date(); self.action = action
        name = place.name; address = place.address; approximate = place.isApproximate
        source = place.sharedSource
        let coordinate = CoordTransform.gcj02ToWgs84(place.coordinate)
        latitude = coordinate.latitude; longitude = coordinate.longitude
    }

    var place: RoutePlace? {
        guard let wgs = PlaceInput.valid(latitude, longitude) else { return nil }
        var place = RoutePlace(name: name, address: address, coordinate: CoordTransform.wgs84ToGcj02(wgs))
        place.approximate = approximate
        place.sharedSource = source ?? .text
        return place
    }
}

struct SharedPlaceInbox {
    static let suite = "group.com.dm2mymcszt.trollroute"
    let directory: URL?

    init(container: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite)) {
        directory = container?.appendingPathComponent("SharedPlaces", isDirectory: true)
    }

    private struct Ledger: Codable {
        var queued: [SharedPlaceRequest] = []
        var handled: Set<UUID> = []
        var draft = SharedRouteDraft()
    }
    private var file: SharedStateFile<Ledger>? {
        directory.map { SharedStateFile(url: $0.appendingPathComponent("ledger.v1.json"), initial: { Ledger() }) }
    }
    private func storage() throws -> SharedStateFile<Ledger> {
        guard let file = file else {
            throw SearchError.message("Couldn't access TrollRoute's shared storage. Open TrollRoute once, then try sharing again.")
        }
        return file
    }

    func enqueue(_ request: SharedPlaceRequest) throws {
        guard request.place != nil else { throw SearchError.message("Invalid shared location.") }
        try importLegacyRequests()
        try storage().update { ledger in
            guard !ledger.handled.contains(request.id) else { return }
            if let existing = ledger.queued.first(where: { $0.id == request.id }) {
                guard existing == request else { throw SearchError.message("Conflicting shared request.") }
                return
            }
            ledger.queued.append(request)
            ledger.queued.sort { $0.created < $1.created }
        }
        SharedPlaceSignal.post()
    }

    /// Throwing read for command consumers; storage failure must not look like success.
    func pendingRequests() throws -> [SharedPlaceRequest] {
        try importLegacyRequests()
        return try storage().read().queued
    }
    func pending() -> [SharedPlaceRequest] { (try? pendingRequests()) ?? [] }

    func remove(_ request: SharedPlaceRequest) throws {
        try importLegacyRequests()
        try storage().update { ledger in
            ledger.queued.removeAll { $0.id == request.id }
            ledger.handled.insert(request.id)
        }
    }

    /// The endpoint change and completion receipt commit in one file replacement.
    /// A crash cannot mark it handled without durably saving the endpoint.
    func consumeEndpoint(_ id: UUID, current: SharedRouteDraft? = nil) throws -> SharedRouteDraft? {
        try importLegacyRequests()
        return try storage().update { ledger in
            guard let request = ledger.queued.first(where: { $0.id == id }),
                  let place = request.place,
                  request.action == .start || request.action == .destination else { return nil }
            if let current = current {
                ledger.draft.start = current.start; ledger.draft.destination = current.destination
            }
            if request.action == .start { ledger.draft.start = place }
            else { ledger.draft.destination = place }
            ledger.draft.presentation = id
            ledger.queued.removeAll { $0.id == id }
            ledger.handled.insert(id)
            return ledger.draft
        }
    }
    func routeDraft() throws -> SharedRouteDraft { try storage().read().draft }
    func acknowledgePresentation(_ id: UUID) throws {
        try storage().update { ledger in
            if ledger.draft.presentation == id { ledger.draft.presentation = nil }
        }
    }

    private func importLegacyRequests() throws {
        guard let directory = directory else { _ = try storage(); return }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let legacy = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        guard !legacy.isEmpty else { return }
        try storage().update { ledger in
            for url in legacy {
                guard let data = try? Data(contentsOf: url),
                      let request = try? JSONDecoder().decode(SharedPlaceRequest.self, from: data),
                      request.place != nil, url.deletingPathExtension().lastPathComponent == request.id.uuidString,
                      !ledger.handled.contains(request.id), !ledger.queued.contains(where: { $0.id == request.id }) else { continue }
                ledger.queued.append(request)
            }
            ledger.queued.sort { $0.created < $1.created }
        }
        // Completion records also guard against re-import if cleanup is interrupted.
        for url in legacy { try? FileManager.default.removeItem(at: url) }
    }

    static func saveFavorite(_ place: RoutePlace, id: UUID = UUID(), store: FavoritesStore? = .shared) throws {
        guard let store = store else { throw FavoritesStore.Failure.unavailable }
        let coordinate = CoordTransform.gcj02ToWgs84(place.coordinate)
        guard CLLocationCoordinate2DIsValid(coordinate) else { throw SearchError.message("Invalid location.") }
        try store.save(.init(id: id, name: place.name, latitude: coordinate.latitude, longitude: coordinate.longitude))
        SharedPlaceSignal.post()
    }

}

struct SharedRouteDraft: Codable {
    var start: RoutePlace?
    var destination: RoutePlace?
    var presentation: UUID?
}

enum SharedCommandURL {
    static func make(_ id: UUID) -> URL { URL(string: "trollroute://shared/" + id.uuidString)! }
    static func requestID(_ url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "trollroute", url.host?.lowercased() == "shared",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].isEmpty else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
}

/// Darwin carries only a wake-up signal; all payloads and receipts remain in the group.
final class SharedPlaceSignal {
    private static let name = "com.dm2mymcszt.trollroute.commands.changed" as CFString
    private let changed: () -> Void
    init(changed: @escaping () -> Void) {
        self.changed = changed
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let signal = Unmanaged<SharedPlaceSignal>.fromOpaque(observer).takeUnretainedValue()
                // Retain through dispatch, even if the owner cancels its observation.
                DispatchQueue.main.async { signal.changed() }
            }, Self.name, nil, .deliverImmediately)
    }
    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(Self.name), nil)
    }
    static func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name), nil, nil, true)
    }
}

/// Holds the latest lifecycle state rather than capturing a SwiftUI scene value
/// when the Darwin observer was installed.
final class SharedPlaceChannel: ObservableObject {
    @Published private(set) var revision = 0
    private(set) var isActive = false
    private var signal: SharedPlaceSignal?
    init() {
        signal = SharedPlaceSignal { [weak self] in self?.wake() }
    }
    func setActive(_ active: Bool) {
        isActive = active
        if active { wake() }
    }
    func wake() { revision += 1 }
}

final class RouteDraft: ObservableObject {
    @Published var start: RoutePlace?
    @Published var destination: RoutePlace?
    // External replacements invalidate any local edits held by an older sheet.
    @Published private(set) var revision = UUID()
    // A shared endpoint invalidates a previous preview when the planner opens.
    var needsRecalculation = false
    // Non-nil only for a newly requested long-press preview; consumed once by Navigation.
    private var automaticPreparation: Bool?

    func prepareFromMap(start: RoutePlace, destination: RoutePlace, autoStart: Bool) {
        self.start = start
        self.destination = destination
        needsRecalculation = true
        automaticPreparation = autoStart
        revision = UUID()
    }

    func takeAutomaticPreparation() -> Bool? {
        let value = automaticPreparation
        automaticPreparation = nil
        return value
    }

    @discardableResult
    func swapEndpoints() -> Bool {
        guard let oldStart = start, let oldDestination = destination else { return false }
        start = oldDestination
        destination = oldStart
        needsRecalculation = true
        automaticPreparation = nil
        return true
    }

    func applySharedDraft(_ saved: SharedRouteDraft) {
        start = saved.start
        destination = saved.destination
        needsRecalculation = true
        automaticPreparation = nil
        revision = UUID()
    }

    func commitEdits(start: RoutePlace?, destination: RoutePlace?, revision: UUID) {
        guard revision == self.revision else { return }
        self.start = start
        self.destination = destination
    }

    func accept(_ request: SharedPlaceRequest) {
        guard let place = request.place else { return }
        if request.action == .start { start = place }
        else if request.action == .destination { destination = place }
        else { return }
        needsRecalculation = true
        automaticPreparation = nil
        revision = UUID()
    }
}

#if os(iOS)
struct IncomingPlaceView: View {
    let request: SharedPlaceRequest
    let routeRunning: Bool
    let accept: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Shared place") {
                    Text(request.name).font(.headline)
                    if !request.address.isEmpty && PlaceInput.coordinates(request.address) == nil { Text(request.address) }
                    Text(String(format: "%.5f, %.5f", request.latitude, request.longitude)).foregroundColor(.secondary)
                    if request.approximate { Text("Approximate").foregroundColor(.secondary) }
                }
                Section {
                    Button(action: accept) { Label(request.action.title, systemImage: request.action.icon) }
                } footer: {
                    if routeRunning && request.action == .go {
                        Text("Moving here will stop the current route.")
                    } else if routeRunning && (request.action == .start || request.action == .destination) {
                        Text("The current route keeps running. This place will be ready in the route planner after you stop it.")
                    }
                }
            }
            .navigationTitle(request.sourceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
        }
    }
}
#endif
