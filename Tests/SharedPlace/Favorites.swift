import Foundation

func expect(_ value: Bool, _ message: String) { precondition(value, message) }
@main struct FavoritesTests {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count > 2, args[1] == "--save-favorite" {
            let store = FavoritesStore(url: URL(fileURLWithPath: args[2]))
            let favorite = FavoritesStore.Favorite(id: UUID(uuidString: args[3])!, name: args[4], latitude: 44, longitude: -0.6)
            try store.save(favorite)
            exit(0)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("favorites-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("collection.json")
        let legacy: [[String: Any]] = [["name": "Original", "lat": 39.9087, "long": 116.3975]]
        let store = FavoritesStore(url: url, legacy: { legacy })
        let initial = try store.read()
        expect(initial.count == 1 && initial[0].longitude == 116.3975, "Preserve WGS-84")
        var children: [Process] = []
        let same = UUID()
        for index in 0..<16 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = ["--save-favorite", url.path, index < 8 ? same.uuidString : UUID().uuidString,
                                 index < 8 ? "Same request" : "Place \(index)"]
            try process.run(); children.append(process)
        }
        for child in children { child.waitUntilExit(); expect(child.terminationStatus == 0, "Concurrent favorite save failed") }
        let saved = try store.read()
        expect(saved.count == 10, "One original, one duplicate request, eight distinct places")
        try store.remove(ids: [same, initial[0].id])
        let retry = FavoritesStore.Favorite(id: same, name: "Same request", latitude: 44, longitude: -0.6)
        expect(try store.save(retry) == false, "Deleted shared request must not replay")
        let reopened = FavoritesStore(url: url, legacy: { legacy })
        expect(try reopened.read().count == 8, "Deleted legacy favorite must not reimport")
        do {
            _ = try reopened.save(.init(id: same, name: "Changed request", latitude: 44, longitude: -0.6))
            fatalError("Conflicting save should fail")
        } catch FavoritesStore.Failure.conflictingRequest { }
        let imported = try reopened.mergeImported([["name": "Imported later", "lat": 45.0, "long": 2.0]])
        let afterImport = try reopened.read()
        expect(imported == 1 && afterImport.count == 9, "Later old-app migration preserves extension saves")
        expect(try reopened.mergeImported([["name": "Imported later", "lat": 45.0, "long": 2.0]]) == 0, "Migration retry deduplicates")
        try Data("broken".utf8).write(to: url)
        do { _ = try reopened.save(.init(name: "Must not replace corrupt data", latitude: 0, longitude: 0)); fatalError("Expected corruption failure") }
        catch { }
        expect(try Data(contentsOf: url) == Data("broken".utf8), "Corruption must not reset Favorites")
        print("PASS: simultaneous cross-process saves, duplicate/relaunch/deleted receipts, ID-based removal, WGS-84 migration, later import, conflicts and corruption")
    }
}
