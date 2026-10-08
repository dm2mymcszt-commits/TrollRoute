import Foundation
import CoreGraphics

@main struct GeometryTests {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 393, height: 852)
        // Recorded dark Notification Centre failure, run 37286747237.
        let host = CGRect(x: 14.5, y: 594.8, width: 365, height: 137.7)
        let local = CGRect(x: 14, y: 87.7, width: 162.7, height: 36)
        let mapped = ActivityControlGeometry.screenFrame(local, host: host, screen: screen)!
        precondition(abs(mapped.midX - 109.85) < 0.001)
        precondition(abs(mapped.midY - 700.5) < 0.001)
        precondition(host.contains(mapped), "Tap must land in the visible widget, not on its clock")
        precondition(ActivityControlGeometry.screenFrame(mapped, host: host, screen: screen) == mapped,
                     "Already-global frames must not receive the host offset twice")
        // Recorded expanded Island frame is already in screen coordinates.
        let expanded = CGRect(x: 29.3, y: 121.7, width: 161.3, height: 36)
        precondition(ActivityControlGeometry.screenFrame(expanded, host: nil, screen: screen) == expanded)
        let clipped = CGRect(x: 14, y: 800, width: 365, height: 138)
        precondition(ActivityControlGeometry.screenFrame(local, host: clipped, screen: screen) == nil)
        precondition(ActivityControlGeometry.screenFrame(.zero, host: host, screen: screen) == nil)
        precondition(ActivityControlGeometry.screenFrame(.null, host: host, screen: screen) == nil)
        precondition(ActivityControlGeometry.screenFrame(expanded, host: .infinite, screen: screen) == nil)
        precondition(ActivityControlGeometry.screenFrame(CGRect(x: -20, y: 1, width: 5, height: 5),
                                                          host: host, screen: screen) == nil)
        print("PASS: recorded remote-widget coordinates map to the visible control; global and invalid frames stay safe")
    }
}
