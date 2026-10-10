import Foundation
import Darwin
@main struct OwnershipTests {
    struct Value: Codable { var number = 0 }
    static func main() throws {
        precondition(geteuid() == 0)
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = SharedStateFile<Value>(url: dir.appendingPathComponent("state.json"), initial: { Value() })
        try store.update { $0.number = 1 }
        try store.update { $0.number = 2 }
        for url in [dir, store.url, store.url.appendingPathExtension("lock")] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            precondition((attributes[.ownerAccountID] as? NSNumber)?.intValue == 501)
            precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == (url == dir ? 0o700 : 0o600))
        }
        // Drop all root credentials, then actually rewrite with mobile's identity.
        precondition(setgid(501) == 0 && setuid(501) == 0)
        try store.update { $0.number = 3 }
        let final = try store.read(); precondition(final.number == 3)
        print("PASS: root atomic replacements and lock remain writable as mobile")
    }
}
