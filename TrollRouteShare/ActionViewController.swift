import UIKit
import SwiftUI
import UniformTypeIdentifiers
import ObjectiveC
import CoreLocation

final class ActionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let driver = CoreLocationSimulationDriver()
        let mover = DirectLocationMove(lease: .shared,
            profile: { AltitudeSettings().profile }, lookup: ElevationLookup.fetchForShare,
            inject: { driver.inject($0, reason: .jump) }, changed: SharedPlaceSignal.post)
        let content = SharePlaceView(load: { [weak self] in
            guard let items = self?.extensionContext?.inputItems as? [NSExtensionItem] else {
                throw SearchError.message("No location was shared.")
            }
            // Prefer a URL attachment to display text supplied alongside it.
            for type in [UTType.url.identifier, UTType.plainText.identifier] {
                for item in items {
                    for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(type) {
                        let value = try await provider.loadItem(forTypeIdentifier: type, options: nil)
                        let text: String?
                        if let url = value as? URL { text = url.absoluteString }
                        else if let string = value as? String { text = string }
                        else if let attributed = value as? NSAttributedString { text = attributed.string }
                        else if let data = value as? Data { text = String(data: data, encoding: .utf8) }
                        else { text = nil }
                        if let text = text, !text.isEmpty {
                            return try await resolveSharedText(text)
                        }
                    }
                }
            }
            if let text = items.compactMap(\.attributedContentText?.string).first, !text.isEmpty {
                return try await resolveSharedText(text)
            }
            throw SearchError.message("Share a Maps link, address, coordinates or plus code.")
        }, done: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
           openContainingApp: openTrollRoute, goThereNow: { request in
               try await mover.perform(id: request.id,
                   coordinate: CLLocationCoordinate2D(latitude: request.latitude, longitude: request.longitude))
           })
        let host = UIHostingController(rootView: content.tint(.indigo))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

/// Keep attachment provenance even when a different provider resolves its address.
private func resolveSharedText(_ text: String) async throws -> [RoutePlace] {
    let source = SharedPlaceSource.detect(text)
    return try await WorldwidePlaceSearch.resolve(PlaceInput.parse(text)).map { result in
        var place = result
        place.sharedSource = source
        return place
    }
}

/// TrollStore's fixed-bundle LaunchServices mechanism. Do not use the host app's
/// UIApplication or an unsupported action-extension extensionContext.open call.
private func openTrollRoute(_ url: URL) -> Bool {
    guard SharedCommandURL.requestID(url) != nil,
          let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
          let workspace = type.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject else { return false }
    let selector = NSSelectorFromString("openApplicationWithBundleID:")
    guard workspace.responds(to: selector) else { return false }
    typealias Open = @convention(c) (AnyObject, Selector, NSString) -> Bool
    let open = unsafeBitCast(workspace.method(for: selector), to: Open.self)
    // The URL UUID already identifies a durable queued request. Launching by the
    // fixed bundle ID activates its consumer even when it was not running.
    return open(workspace, selector, "com.dm2mymcszt.trollroute")
}
