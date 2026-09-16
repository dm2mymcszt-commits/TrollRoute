import SwiftUI

struct SharePlaceView: View {
    var initialPlace: RoutePlace? = nil
    let load: () async throws -> [RoutePlace]
    let done: () -> Void
    var openContainingApp: (URL) -> Bool = { _ in false }
    var goThereNow: (SharedPlaceRequest) async throws -> Void = { _ in
        throw SearchError.message("Location delivery is unavailable in this preview.")
    }
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var queuedFavorite: SharedPlaceRequest?
    @State private var queuedMove: SharedPlaceRequest?
    @State private var queuedEndpoint: SharedPlaceRequest?
    @State private var places: [RoutePlace] = []
    @State private var selected: RoutePlace?
    @State private var name = ""
    @State private var loading = true
    @State private var error: String?
    @State private var completion: String?

    var body: some View {
        NavigationView {
            Form {
                if loading { ProgressView("Finding shared location…") }
                if let completion = completion {
                    Section { Label(completion, systemImage: "checkmark.circle") }
                } else if let place = selected {
                    Section((place.sharedSource ?? .text).title) {
                        TextField("Place name", text: $name)
                        if !place.address.isEmpty { Text(place.address).foregroundColor(.secondary) }
                        if place.isApproximate { Text("Approximate").foregroundColor(.secondary) }
                    }
                    if places.count > 1 {
                        Section("Other matches") {
                            ForEach(places.filter { $0.id != place.id }) { alternative in
                                Button(alternative.name + " · " + alternative.address) {
                                    selected = alternative; name = alternative.name
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(SharedPlaceAction.allCases) { action in
                            Button { save(action) } label: { Label(action.title, systemImage: action.icon) }
                        }
                    } footer: {
                        Text("Moving here stops any running route. Favorites are saved here. Route start and destination open TrollRoute Navigation automatically.")
                    }
                }
                if let error = error {
                    Section { Text(error).foregroundColor(.red) }
                }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView("Moving location...").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .navigationTitle("TrollRoute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(completion == nil ? "Cancel" : "Done", action: done) } }
        }
        .onDisappear { operation?.cancel() }
        .task {
            do {
                let result: [RoutePlace]
                if let initialPlace = initialPlace { result = [initialPlace] }
                else { result = try await load() }
                guard !Task.isCancelled else { return }
                places = result; selected = result.first; name = result.first?.name ?? ""
                if result.isEmpty { error = "No matching location. Copy its coordinates or plus code from Maps and try again." }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    @MainActor private func save(_ action: SharedPlaceAction) {
        guard !busy, let selected = selected else { return }
        let entered = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var place = RoutePlace(name: entered.isEmpty ? selected.name : entered, address: selected.address, coordinate: selected.coordinate)
        place.approximate = selected.approximate
        place.sharedSource = selected.sharedSource
        do {
            if action == .favorite {
                let candidate = SharedPlaceRequest(place: place, action: .favorite)
                let request: SharedPlaceRequest
                if let queued = queuedFavorite, queued.name == candidate.name,
                   queued.latitude == candidate.latitude, queued.longitude == candidate.longitude { request = queued }
                else { request = candidate }
                queuedFavorite = request
                try SharedPlaceInbox.saveFavorite(place, id: request.id)
                completion = "Saved to Favorites"
            } else if action == .start || action == .destination {
                let candidate = SharedPlaceRequest(place: place, action: action)
                let request: SharedPlaceRequest
                if let queued = queuedEndpoint, queued.action == action,
                   queued.name == candidate.name, queued.address == candidate.address,
                   queued.latitude == candidate.latitude, queued.longitude == candidate.longitude { request = queued }
                else { request = candidate }
                try SharedPlaceInbox().enqueue(request)
                queuedEndpoint = request
                guard openContainingApp(SharedCommandURL.make(request.id)) else {
                    throw SearchError.message("Couldn't open TrollRoute automatically. Try the action again.")
                }
                completion = "Opening TrollRoute Navigation"
                done()
            } else {
                let candidate = SharedPlaceRequest(place: place, action: .go)
                let request: SharedPlaceRequest
                if let queued = queuedMove, queued.latitude == candidate.latitude,
                   queued.longitude == candidate.longitude { request = queued }
                else { request = candidate }
                queuedMove = request
                busy = true
                operation = Task { @MainActor in
                    defer { busy = false; operation = nil }
                    do {
                        try await goThereNow(request)
                        guard !Task.isCancelled else { return }
                        completion = "Location moved"
                        error = nil
                    } catch is CancellationError { }
                    catch { self.error = error.localizedDescription }
                }
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
