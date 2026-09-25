import SwiftUI

struct MigrationLaunchView: View {
    @State private var checked = false
    @State private var summary: MigrationSummary?
    @State private var failure: String?

    var body: some View {
        Group {
            if !checked {
                ProgressView("Checking saved places…").onAppear(perform: check)
            } else if let summary = summary {
                NavigationView {
                    Form {
                        Section("Imported from Andromeda") {
                            LabeledCount(title: "Favorites", count: summary.favorites)
                            LabeledCount(title: "Recent places", count: summary.recents)
                            LabeledCount(title: "After-route place", count: summary.afterRoutePlace)
                            LabeledCount(title: "Settings and speeds", count: summary.settings)
                        }
                        Section {
                            Text("Your original data was left untouched. Andromeda can now be deleted. Its share action stays visible until you delete it.")
                            Text("Any settings already saved in TrollRoute were kept. Existing saved places were combined without duplicates.")
                            Button("Continue") {
                                SharedPreferences.defaults.set(true, forKey: LegacyMigration.acknowledgedKey)
                                self.summary = nil
                            }
                        }
                    }.navigationTitle("Welcome to TrollRoute")
                }
            } else if let failure = failure {
                NavigationView {
                    Form {
                        Text(failure)
                        Button("Retry import", action: check)
                        Button("Continue to TrollRoute") {
                            // Opening the app never depends on successfully saving
                            // a migration flag. The local state dismisses immediately.
                            SharedPreferences.defaults.set(true, forKey: LegacyMigration.skippedKey)
                            self.failure = nil
                        }
                    }.navigationTitle("Optional import")
                }
            } else {
                // Construct app models only after import, so their initial settings
                // and recent-place caches see the imported values immediately.
                ReadyAppView()
            }
        }
    }

    private func check() {
        let defaults = SharedPreferences.defaults
        do {
            if !LegacyMigration.needsImport(in: defaults) {
                summary = LegacyMigration.pendingSummary(in: defaults)
            } else {
                let locations = TRLegacyLocations()
                if let error = locations["error"] as? String { throw MigrationError.unreadable(error) }
                // No old app means no import, even if stale files or an unfinished
                // journal remain. No Favorites or preference write can block launch.
                guard locations["installed"] as? Bool == true else {
                    summary = nil
                    failure = nil
                    checked = true
                    return
                }
                guard let store = FavoritesStore.shared else { throw FavoritesStore.Failure.unavailable }
                let paths = (locations["preferences"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
                let favorites = (locations["favorites"] as? String).map { URL(fileURLWithPath: $0) }
                summary = try LegacyMigration.run(preferenceURLs: paths, favoritesURL: favorites,
                    oldAppInstalled: locations["installed"] as? Bool ?? false, target: defaults, favoriteStore: store)
            }
            failure = nil
        } catch { failure = error.localizedDescription }
        checked = true
    }
}

private struct LabeledCount: View {
    let title: String
    let count: Int
    var body: some View {
        HStack { Text(title); Spacer(); Text("\(count)").foregroundColor(.secondary) }
    }
}
