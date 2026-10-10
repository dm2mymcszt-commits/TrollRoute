import Foundation

/// Event-driven recovery with bounded retries; the idle safety timer never injects.
/// Injectable scheduling lets tests exercise cancellation and process replacement.
final class KeeperRecovery {
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
    private let identity: () -> String
    private let restore: () throws -> Bool
    private let schedule: Schedule
    private let event: (String, Int) -> Void
    private(set) var observed = ""
    private var generation = 0
    private var stopped = false
    init(identity: @escaping () -> String, restore: @escaping () throws -> Bool,
         schedule: @escaping Schedule, event: @escaping (String, Int) -> Void = { _, _ in }) {
        self.identity = identity; self.restore = restore; self.schedule = schedule; self.event = event
        observed = identity()
    }
    func check() {
        let current = identity()
        if current != observed { processExited() }
    }
    func processExited() {
        guard !stopped else { return }
        generation += 1
        let token = generation
        let previous = observed
        event("service-exit", 0)
        for (attempt, delay) in [0.0, 0.15, 0.5, 1, 2, 4, 8].enumerated() {
            let work = { [weak self] in
                guard let self = self, !self.stopped, self.generation == token else { return }
                let current = self.identity()
                guard !current.isEmpty, current != previous else {
                    self.event("service-wait", attempt + 1); return
                }
                if current != self.observed { self.observed = current; self.event("service-replaced", attempt + 1) }
                do {
                    if try self.restore() { self.event("restore-sent", attempt + 1) }
                    else { self.event("restore-skipped", attempt + 1) }
                } catch { self.event("restore-error", attempt + 1) }
            }
            if delay == 0 { work() } else { schedule(delay, work) }
        }
    }
    func stop() { stopped = true; generation += 1 }
}
#if os(iOS)
import Darwin

struct KeeperRecord: Codable {
    var pid: Int32
    var identity: String
    var executable: String
    var build: String
    var boot: String
    var started: Date
    var error: Int = 0
}

enum KeeperFiles {
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedPreferences.suite) }
    static var executable: String {
        let bundle = Bundle.main.bundleURL
        let app = bundle.pathExtension == "appex" ? bundle.deletingLastPathComponent().deletingLastPathComponent() : bundle
        return app.appendingPathComponent("TrollRoute").path
    }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown" }
    static func directory(_ container: URL) -> URL { container.appendingPathComponent("LocationSession") }
    static func record(_ container: URL) -> URL { directory(container).appendingPathComponent("keeper.json") }
    static func read(_ container: URL) -> KeeperRecord? {
        guard let data = try? Data(contentsOf: record(container)) else { return nil }
        return try? JSONDecoder().decode(KeeperRecord.self, from: data)
    }
    static func lock(_ container: URL) throws -> Int32 {
        let dir = directory(container)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try SharedFileAccess.repair(dir, directory: true)
        let url = dir.appendingPathComponent("keeper.instance.lock")
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw failure(errno) }
        do { try SharedFileAccess.repair(url) } catch { close(fd); throw error }
        return fd
    }
    static func locked(_ container: URL) -> Bool {
        guard let fd = try? lock(container) else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { flock(fd, LOCK_UN); return false }
        return errno == EWOULDBLOCK
    }
    static func failure(_ code: Int32) -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
    static func validContainer(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard url.path.hasPrefix("/private/var/mobile/Containers/Shared/AppGroup/") || url.path.hasPrefix("/var/mobile/Containers/Shared/AppGroup/") else { return nil }
        let metadata = url.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        guard let data = try? Data(contentsOf: metadata),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              dict["MCMMetadataIdentifier"] as? String == SharedPreferences.suite else { return nil }
        return url
    }
}

final class KeeperClient: LocationKeeperLifecycle {
    static let shared = KeeperClient()
    private var lastCheck: TimeInterval = -.infinity
    private var lastSuccess = false
    func ensureRunning() throws {
        #if targetEnvironment(simulator)
        return
        #else
        let now = ProcessInfo.processInfo.systemUptime
        if lastSuccess && now - lastCheck < 30 { return }
        lastCheck = now; lastSuccess = false
        guard let container = KeeperFiles.container else { throw KeeperFiles.failure(ENOENT) }
        if KeeperFiles.locked(container), let record = KeeperFiles.read(container),
           record.build == KeeperFiles.build, record.executable == KeeperFiles.executable,
           record.boot == SystemBootIdentity.current, record.error == 0 {
            lastSuccess = true; return
        }
        try command("start", container: container)
        guard KeeperFiles.locked(container), let record = KeeperFiles.read(container), record.error == 0 else {
            throw KeeperFiles.failure(EIO)
        }
        lastSuccess = true
        #endif
    }
    func stop() throws {
        lastSuccess = false; lastCheck = -.infinity
        guard let container = KeeperFiles.container else { throw KeeperFiles.failure(ENOENT) }
        #if !targetEnvironment(simulator)
        try command("stop", container: container)
        #endif
    }
    func command(_ action: String, container: URL) throws {
        // Run the signed main executable first. An extension does not need persona entitlements.
        let rc = TRSpawn(KeeperFiles.executable, ["--keeper-relay", action, container.path], false, true)
        guard rc == 0 else { throw KeeperFiles.failure(rc) }
    }
    func resumeIfCurrentBoot() {
        guard let state = try? LocationLeaseStore.shared?.read(), state.owner != nil,
              state.snapshot.isActive, state.bootIdentity == SystemBootIdentity.current,
              state.bootIdentity != "unknown" else { return }
        try? ensureRunning()
    }
}

enum KeeperRuntime {
    static func handleCommandLine() -> Bool {
        let args = CommandLine.arguments
        guard args.count > 1, args[1].hasPrefix("--keeper") else { return false }
        guard args.count == 4, let container = KeeperFiles.validContainer(args[3]) else { exit(64) }
        if args[1] == "--keeper-relay" {
            exit(TRSpawn(KeeperFiles.executable, ["--keeper", args[2], container.path], true, true))
        }
        guard args[1] == "--keeper", geteuid() == 0 else { exit(77) }
        do {
            switch args[2] {
            case "start":
                if KeeperFiles.locked(container), let old = KeeperFiles.read(container),
                   old.build == KeeperFiles.build, old.executable == KeeperFiles.executable,
                   old.boot == SystemBootIdentity.current { return true }
                try terminate(container)
                let rc = TRSpawn(KeeperFiles.executable, ["--keeper", "run", container.path], true, false)
                guard rc == 0 else { throw KeeperFiles.failure(rc) }
                for _ in 0..<60 {
                    if KeeperFiles.locked(container), let record = KeeperFiles.read(container),
                       record.build == KeeperFiles.build, record.error == 0 { return true }
                    usleep(25000)
                }
                throw KeeperFiles.failure(ETIMEDOUT)
            case "stop": try terminate(container)
            case "run": try run(container)
            default: exit(64)
            }
            return true
        } catch { exit(1) }
    }
    static func terminate(_ container: URL) throws {
        guard KeeperFiles.locked(container) else { return }
        guard let record = KeeperFiles.read(container), record.boot == SystemBootIdentity.current,
              !record.identity.isEmpty, TRProcessIdentity(record.pid) == record.identity,
              TRProcessPath(record.pid) == record.executable,
              URL(fileURLWithPath: record.executable).lastPathComponent == "TrollRoute" else {
            throw KeeperFiles.failure(ESRCH)
        }
        guard kill(record.pid, SIGTERM) == 0 || errno == ESRCH else { throw KeeperFiles.failure(errno) }
        for _ in 0..<40 {
            if !KeeperFiles.locked(container) { return }
            usleep(25000)
        }
        if TRProcessIdentity(record.pid) == record.identity { _ = kill(record.pid, SIGKILL) }
        for _ in 0..<40 {
            if !KeeperFiles.locked(container) { return }
            usleep(25000)
        }
        throw KeeperFiles.failure(ETIMEDOUT)
    }
    static func run(_ container: URL) throws {
        let fd = try KeeperFiles.lock(container)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return }
        // Kept open for the process lifetime. The kernel releases it even on SIGKILL.
        let lease = LocationLeaseStore(url: KeeperFiles.directory(container).appendingPathComponent("authority.v1.json"))
        let state = try lease.read()
        guard state.owner != nil, state.snapshot.isActive,
              state.bootIdentity == SystemBootIdentity.current, state.bootIdentity != "unknown" else { close(fd); return }
        let protection = TRProtectKeeper()
        let record = KeeperRecord(pid: getpid(), identity: TRProcessIdentity(getpid()),
            executable: KeeperFiles.executable, build: KeeperFiles.build,
            boot: SystemBootIdentity.current, started: Date(), error: Int(protection))
        try JSONEncoder().encode(record).write(to: KeeperFiles.record(container), options: .atomic)
        try SharedFileAccess.repair(KeeperFiles.record(container))
        guard protection == 0 else { close(fd); throw KeeperFiles.failure(protection) }
        let watcher = KeeperProcessWatcher(lease: lease)
        watcher.start()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(2))
        timer.setEventHandler {
            guard FileManager.default.fileExists(atPath: record.executable),
                  let latest = try? lease.read(), latest.owner != nil, latest.snapshot.isActive else { exit(0) }
            watcher.check()
        }
        timer.resume()
        withExtendedLifetime((timer, watcher)) { dispatchMain() }
    }
}

final class KeeperProcessWatcher {
    private var source: DispatchSourceProcess?
    private var watchedIdentity = ""
    private let lease: LocationLeaseStore
    private lazy var recovery = KeeperRecovery(identity: { [weak self] in self?.serviceIdentity() ?? "" },
        restore: { [weak self] in
            guard let self = self else { return false }
            return try self.lease.restoreCurrent { location in
                // A new manager for EVERY attempt; never reuse the old XPC connection.
                CoreLocationSimulationDriver().inject(location, reason: .stateChange)
            }
        }, schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) })
    init(lease: LocationLeaseStore) { self.lease = lease }
    func start() { _ = recovery; attach() }
    func check() { recovery.check(); attach() }
    private func serviceIdentity() -> String {
        let pid = TRLocationPID()
        return pid > 0 ? TRProcessIdentity(pid) : ""
    }
    private func attach() {
        let pid = TRLocationPID(); let identity = TRProcessIdentity(pid)
        guard pid > 0, !identity.isEmpty, identity != watchedIdentity else { return }
        source?.cancel()
        watchedIdentity = identity
        let next = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        next.setEventHandler { [weak self] in
            guard let self = self, self.watchedIdentity == identity else { return }
            self.source?.cancel(); self.source = nil; self.watchedIdentity = ""
            self.recovery.processExited()
            // Discovery while launchd is replacing the service is bounded, not idle polling.
            for delay in [0.0, 0.15, 0.5, 1, 2, 4, 8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.attach() }
            }
        }
        source = next; next.resume()
        if TRProcessIdentity(pid) != identity { recovery.check() }
    }
}
#endif
