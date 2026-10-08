import Foundation

enum ActivityControlGeometry {
    // Remote widget children can have local frames while their host is on screen.
    static func screenFrame(_ reported: CGRect, host: CGRect?, screen: CGRect) -> CGRect? {
        func valid(_ value: CGRect) -> Bool {
            !value.isEmpty && !value.isNull && !value.isInfinite &&
                [value.minX, value.minY, value.maxX, value.maxY].allSatisfy(\.isFinite)
        }
        guard valid(reported), valid(screen) else { return nil }
        var result = reported
        if let host = host {
            guard valid(host) else { return nil }
            if !host.contains(reported) {
                guard CGRect(origin: .zero, size: host.size).contains(reported) else { return nil }
                result = reported.offsetBy(dx: host.minX, dy: host.minY)
            }
        }
        return screen.contains(result) ? result : nil
    }
}
