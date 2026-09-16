//
//  FavoritesView.swift
//  TrollRoute
//
//  Developed by son3ra1n.
//

import SwiftUI
import MapKit
import AlertKit

struct FavoritesView: View {
    @Binding var isPresented: Bool
    var currentLat: Double
    var currentLong: Double
    var onSelect: (Double, Double, String) -> Void
    
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var changes = SharedPlaceChannel()
    @State private var bookmarks: [FavoritesStore.Favorite] = []
    @State private var failure: String?
    @State private var showAddSheet = false
    @State private var newName = ""
    
    let categoryIcons: [String: String] = [
        "Home": "house.fill",
        "Work": "briefcase.fill",
        "Gym": "figure.run",
        "School": "graduationcap.fill"
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color.indigo.opacity(0.08), Color.black.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                
                if bookmarks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Favorites Yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Tap + to save your current location")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                } else {
                    List {
                        ForEach(bookmarks) { bookmark in
                            let name = bookmark.name
                            let lat = bookmark.latitude
                            let long = bookmark.longitude
                            
                            Button(action: {
                                onSelect(lat, long, name)
                                isPresented = false
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(categoryColor(for: name).opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: categoryIcons[name] ?? "mappin.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(categoryColor(for: name))
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(name)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("\(String(format: "%.4f", lat)), \(String(format: "%.4f", long))")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.indigo)
                                        .padding(8)
                                        .background(Color.indigo.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deleteBookmark)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.indigo)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                addFavoriteSheet()
            }
            .onAppear(perform: reload)
            .onChange(of: changes.revision) { _ in reload() }
            .onChange(of: scenePhase) { phase in if phase == .active { reload() } }
            .alert("Favorites unavailable", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }
    
    @ViewBuilder
    private func addFavoriteSheet() -> some View {
        NavigationView {
            Form {
                if let failure = failure { Text(failure).foregroundColor(.red) }
                Section(header: Text("Location Name")) {
                    TextField("e.g. Home, Work, Park...", text: $newName)
                }
                Section(header: Text("Current Location"), footer: Text("Your current simulated coordinates will be saved automatically.")) {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.indigo)
                        Text("\(String(format: "%.6f", currentLat)), \(String(format: "%.6f", currentLong))")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    Button(action: saveFavorite) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Save Current Location")
                        }
                        .foregroundColor(.indigo)
                    }
                    .disabled(newName.isEmpty)
                }
            }
            .navigationTitle("Add Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showAddSheet = false }
                }
            }
        }
    }
    
    private func reload() {
        do { bookmarks = try bookmarkStore().read() }
        catch { failure = error.localizedDescription }
    }

    private func saveFavorite() {
        guard BookMarkSave(lat: currentLat, long: currentLong, name: newName) else {
            failure = "Couldn't save this favorite. Your existing places have not been changed."
            return
        }
        reload()
        newName = ""
        showAddSheet = false
        AlertKitAPI.present(title: "Saved!", icon: .done, style: .iOS17AppleMusic, haptic: .success)
    }

    private func deleteBookmark(at offsets: IndexSet) {
        // Remove the displayed identities, never offsets into a newly read array.
        let ids = Set(offsets.compactMap { bookmarks.indices.contains($0) ? bookmarks[$0].id : nil })
        do {
            try bookmarkStore().remove(ids: ids)
            SharedPlaceSignal.post()
            reload()
        } catch { failure = error.localizedDescription }
    }

    private func categoryColor(for name: String) -> Color {
        switch name.lowercased() {
        case let n where n.contains("home"): return .green
        case let n where n.contains("work"): return .blue
        case let n where n.contains("gym"): return .orange
        case let n where n.contains("school"): return .purple
        default: return .indigo
        }
    }
}
