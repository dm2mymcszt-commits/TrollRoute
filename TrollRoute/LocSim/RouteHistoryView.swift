import SwiftUI

struct RouteHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: RouteHistoryStore
    var replay: ((RouteHistoryEntry) -> Void)? = nil
    @State private var confirmClear = false
    var body: some View {
        List {
            if let error = store.error { Text(error).foregroundColor(.red) }
            if store.entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No routes yet", systemImage: "clock.arrow.circlepath").font(.headline)
                    Text("Routes appear here when you start them. History stays on this device.")
                        .font(.subheadline).foregroundColor(.secondary)
                }.padding(.vertical).accessibilityIdentifier("history-empty")
            }
            ForEach(store.entries) { entry in
                Button {
                    replay?(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(entry.start.name) to \(entry.destination.name)").font(.headline).foregroundColor(.primary)
                        Label("\(entry.mode) · \(Int(entry.speedKmh)) km/h · \(String(format: "%.1f", entry.distance / 1000)) km", systemImage: entry.symbol)
                            .font(.subheadline).foregroundColor(.secondary)
                        Text(entry.date, style: .date).font(.caption).foregroundColor(.secondary)
                        if let a = entry.departureAirport, let b = entry.arrivalAirport {
                            Text("\(a.code) to \(b.code)").font(.caption).foregroundColor(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                .disabled(replay == nil)
                .accessibilityIdentifier("history-entry-\(entry.id.uuidString)")
                .swipeActions { Button("Delete", role: .destructive) { store.delete(entry.id) } }
            }
            if replay == nil && !store.entries.isEmpty {
                Text("Finish the active route to prepare a trip from History.").font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("History").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .bottomBar) {
                Button("Clear history", role: .destructive) { confirmClear = true }
                    .disabled(store.entries.isEmpty && store.error == nil)
            }
        }
        .alert("Clear history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This deletes all saved routes from this device.") }
    }
}
