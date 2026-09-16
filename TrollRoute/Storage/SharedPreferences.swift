import Foundation

/// The new app and its extensions keep preferences in one stable group domain.
/// This also survives the later removal of the app's no-container entitlement.
enum SharedPreferences {
    static let suite = "group.com.dm2mymcszt.trollroute"
    static let defaults: UserDefaults = {
        let group = UserDefaults(suiteName: suite)!
        // Preserve any preferences created by the intermediate new-identity
        // build, before group storage was introduced. This is TrollRoute's own
        // domain, never the old app's domain.
        let ownKeys = ["TSBypass", "isFirstRun", "routeFinishAction",
            "routeFinishDestination", "routeRecentPlaces.v1", "routeSpeedKmh.walking",
            "routeSpeedKmh.cycling", "routeSpeedKmh.driving", "altitudeProfile",
            "mapAppearance", "mapStyle", "mapButtonLabels", "mapHaptics",
            "tapMapToSetLocation", "askBeforeMoving"]
        for key in ownKeys where group.object(forKey: key) == nil {
            if let value = UserDefaults.standard.object(forKey: key) { group.set(value, forKey: key) }
        }
        return group
    }()
}

#if canImport(Darwin)
import Darwin
#endif

/// A stable lock file protects read/modify/atomic-replace across app processes.
/// Never lock the replaced JSON inode: other processes may still hold that inode.
struct SharedStateFile<Value: Codable> {
    let url: URL
    let initial: () -> Value

    func read() throws -> Value { try locked { try load() } }

    @discardableResult
    func update<Result>(_ operation: (inout Value) throws -> Result) throws -> Result {
        try transaction { loaded, persist in
            var value = loaded
            let result = try operation(&value)
            try persist(value)
            return result
        }
    }

    /// Supports a durable checkpoint before an external side effect, with the
    /// same cross-process lock held throughout. A thrown operation does not undo
    /// checkpoints already written. The closures must not recursively use this file.
    func transaction<Result>(_ operation: (Value, (Value) throws -> Void) throws -> Result) throws -> Result {
        try locked {
            try operation(load()) { value in
                try JSONEncoder().encode(value).write(to: url, options: .atomic)
            }
        }
    }

    private func load() throws -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else { return initial() }
        // Corruption is an error, never an empty ledger that could replay commands.
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private func locked<Result>(_ operation: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
