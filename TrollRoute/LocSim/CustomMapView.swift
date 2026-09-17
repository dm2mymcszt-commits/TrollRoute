//
//  CustomMapView.swift
//  TrollRoute
//
//  Developed by son3ra1n.
//

import SwiftUI
import MapKit

struct CustomMapView: UIViewRepresentable {
    @Binding var tappedCoordinate: EquatableCoordinate?
    @Binding var moveToRegion: MKCoordinateRegion?
    var routePolyline: MKPolyline?
    var allRoutePolylines: [MKPolyline]
    var selectedRouteIndex: Int
    var movingPosition: CLLocationCoordinate2D?
    var routeETAs: [String]
    var allowsLocationSelection: Bool
    var onSelectRoute: ((Int) -> Void)?
    var fitsRoutes: Bool
    var showsUserLocation: Bool
    var mapStyle: String
    var proposedPosition: CLLocationCoordinate2D?
    var proposalIsRoutePreview: Bool
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?

    init(tappedCoordinate: Binding<EquatableCoordinate?>,
         moveToRegion: Binding<MKCoordinateRegion?>,
         routePolyline: MKPolyline? = nil,
         allRoutePolylines: [MKPolyline] = [],
         selectedRouteIndex: Int = 0,
         movingPosition: CLLocationCoordinate2D? = nil,
         routeETAs: [String] = [],
         allowsLocationSelection: Bool = false,
         onSelectRoute: ((Int) -> Void)? = nil,
         fitsRoutes: Bool = false,
         showsUserLocation: Bool = true,
         mapStyle: String = "standard",
         proposedPosition: CLLocationCoordinate2D? = nil,
         proposalIsRoutePreview: Bool = false,
         onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil) {
        self._tappedCoordinate = tappedCoordinate
        self._moveToRegion = moveToRegion
        self.routePolyline = routePolyline
        self.allRoutePolylines = allRoutePolylines
        self.selectedRouteIndex = selectedRouteIndex
        self.movingPosition = movingPosition
        self.routeETAs = routeETAs
        self.allowsLocationSelection = allowsLocationSelection
        self.onSelectRoute = onSelectRoute
        self.fitsRoutes = fitsRoutes
        self.showsUserLocation = showsUserLocation
        self.mapStyle = mapStyle
        self.proposedPosition = proposedPosition
        self.proposalIsRoutePreview = proposalIsRoutePreview
        self.onLongPress = onLongPress
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        let desiredType: MKMapType = mapStyle == "hybrid" ? .hybrid : .standard
        if mapView.mapType != desiredType { mapView.mapType = desiredType }
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.layer.cornerRadius = 15
        mapView.layer.masksToBounds = true
        context.coordinator.installTapRecognizers(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // A representable is a value: delegates must use the latest bindings and callbacks.
        context.coordinator.parent = self
        context.coordinator.longPress?.isEnabled = onLongPress != nil
        mapView.showsUserLocation = showsUserLocation
        let desiredType: MKMapType = mapStyle == "hybrid" ? .hybrid : .standard
        if mapView.mapType != desiredType { mapView.mapType = desiredType }
        context.coordinator.updateRoutes(on: mapView)
        context.coordinator.updateProposedPosition(on: mapView)
        if let region = moveToRegion {
            mapView.setRegion(region, animated: true)
            DispatchQueue.main.async { self.moveToRegion = nil }
        }
        if let position = movingPosition {
            if let annotation = context.coordinator.movingAnnotation {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    annotation.coordinate = position
                }
            } else {
                let annotation = MovingAnnotation()
                annotation.coordinate = position
                annotation.title = "Simulated Position"
                context.coordinator.movingAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        } else if let annotation = context.coordinator.movingAnnotation {
            mapView.removeAnnotation(annotation)
            context.coordinator.movingAnnotation = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: CustomMapView
        var currentPolylines: [MKPolyline] = []
        var selectedIndex = 0
        var movingAnnotation: MovingAnnotation?
        private(set) var proposedAnnotation: ProposedPositionAnnotation?
        private(set) var singleTap: UITapGestureRecognizer?
        private(set) var doubleTapGuard: UITapGestureRecognizer?
        private(set) var longPress: UILongPressGestureRecognizer?
        private var currentETAs: [String] = []
        private var routeAnnotations: [MKAnnotation] = []
        private let routeColors: [UIColor] = [.systemBlue, .systemOrange, .systemPurple, .systemPink]

        init(_ parent: CustomMapView) { self.parent = parent }

        func installTapRecognizers(on mapView: MKMapView) {
            guard singleTap == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(ignoreDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            for recognizer in [tap, doubleTap] {
                recognizer.delegate = self
                recognizer.cancelsTouchesInView = false
                mapView.addGestureRecognizer(recognizer)
            }
            singleTap = tap
            doubleTapGuard = doubleTap
            tap.require(toFail: doubleTap)
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            press.minimumPressDuration = 0.5
            // Keep MapKit's touch stream intact after the route hold. Cancelling
            // the underlying view's touches disrupts its next double-tap sequence.
            press.cancelsTouchesInView = false
            press.delegate = self
            press.isEnabled = parent.onLongPress != nil
            mapView.addGestureRecognizer(press)
            // A held finger must recognize before touch-up. Only the single tap
            // waits for double-tap failure; a long press is distinguished by duration.
            tap.require(toFail: press)
            // A completed route hold cannot become the first half of a double
            // tap. Otherwise its release can pair with the next tap, leaving
            // the second new tap free to select a location instead of zooming.
            doubleTap.require(toFail: press)
            longPress = press
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            parent.onLongPress?(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }

        // The guard protects even when MapKit creates its zoom recognizers lazily.
        // Simultaneous recognition preserves MapKit's own double-tap zoom.
        @objc private func ignoreDoubleTap(_ gesture: UITapGestureRecognizer) {}

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // MapKit has its own hold recognizer. It must not prevent our route
            // hold; panning still competes normally and cancels a moving finger.
            gestureRecognizer === doubleTapGuard || other === doubleTapGuard
                || (gestureRecognizer === longPress && other is UILongPressGestureRecognizer)
                || (other === longPress && gestureRecognizer is UILongPressGestureRecognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === singleTap, let tap = other as? UITapGestureRecognizer else { return false }
            return tap.numberOfTapsRequired >= 2
        }

        func updateProposedPosition(on mapView: MKMapView) {
            guard let coordinate = parent.proposedPosition else {
                if let annotation = proposedAnnotation { mapView.removeAnnotation(annotation) }
                proposedAnnotation = nil
                return
            }
            if let annotation = proposedAnnotation, annotation.isRoutePreview != parent.proposalIsRoutePreview {
                mapView.removeAnnotation(annotation)
                proposedAnnotation = nil
            }
            if let annotation = proposedAnnotation {
                annotation.coordinate = coordinate
            } else {
                let annotation = ProposedPositionAnnotation(isRoutePreview: parent.proposalIsRoutePreview)
                annotation.coordinate = coordinate
                proposedAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func updateRoutes(on mapView: MKMapView) {
            let polylines = parent.allRoutePolylines.isEmpty
                ? parent.routePolyline.map { [$0] } ?? [] : parent.allRoutePolylines
            let index = min(max(parent.selectedRouteIndex, 0), max(polylines.count - 1, 0))
            let geometryChanged = currentPolylines.map(ObjectIdentifier.init) != polylines.map(ObjectIdentifier.init)
            let selectionChanged = selectedIndex != index
            let labelsChanged = currentETAs != parent.routeETAs
            guard geometryChanged || selectionChanged || labelsChanged else { return }

            // MapKit can ask for a renderer during addOverlay; publish identity/style first.
            currentPolylines = polylines
            selectedIndex = index
            currentETAs = parent.routeETAs
            if geometryChanged || selectionChanged {
                mapView.removeOverlays(mapView.overlays.filter { $0 is MKPolyline })
                for (routeIndex, polyline) in polylines.enumerated() where routeIndex != index {
                    mapView.addOverlay(polyline, level: .aboveRoads)
                }
                if polylines.indices.contains(index) { mapView.addOverlay(polylines[index], level: .aboveRoads) }
            }
            mapView.removeAnnotations(routeAnnotations)
            routeAnnotations = []
            if polylines.indices.contains(index), let start = endpoint(of: polylines[index], first: true),
               let end = endpoint(of: polylines[index], first: false) {
                routeAnnotations.append(RouteEndpointAnnotation(coordinate: start, isStart: true))
                routeAnnotations.append(RouteEndpointAnnotation(coordinate: end, isStart: false))
            }
            for (routeIndex, polyline) in polylines.enumerated() where polyline.pointCount > 0 {
                let eta = currentETAs.indices.contains(routeIndex) ? currentETAs[routeIndex] : "Route \(routeIndex + 1)"
                routeAnnotations.append(RouteBadgeAnnotation(coordinate: polyline.coordinate, routeIndex: routeIndex, eta: eta))
            }
            mapView.addAnnotations(routeAnnotations)
            if geometryChanged && parent.fitsRoutes && !polylines.isEmpty {
                let bounds = polylines.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
                mapView.setVisibleMapRect(bounds,
                    edgePadding: UIEdgeInsets(top: 62, left: 48, bottom: 60, right: 48), animated: false)
            }
            positionBadges(on: mapView)
        }

        private func endpoint(of polyline: MKPolyline, first: Bool) -> CLLocationCoordinate2D? {
            guard polyline.pointCount > 0 else { return nil }
            return polyline.points()[first ? 0 : polyline.pointCount - 1].coordinate
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // UIKit may continue a touch sequence after a held finger. Never
            // reinterpret its second/later tap as a new location-selection tap.
            if gestureRecognizer === singleTap && touch.tapCount > 1 { return false }
            var view = touch.view
            while let candidate = view {
                if candidate is MKAnnotationView || candidate is UIControl { return false }
                view = candidate.superview
            }
            return true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = gesture.view as? MKMapView else { return }
            handleMapTap(at: gesture.location(in: mapView), on: mapView)
        }

        func handleMapTap(at point: CGPoint, on mapView: MKMapView) {
            // Guard annotation frames as well as touch ancestry; their host view differs by iOS version.
            for annotation in mapView.annotations {
                if let view = mapView.view(for: annotation), !view.isHidden,
                   view.convert(view.bounds, to: mapView).insetBy(dx: -6, dy: -6).contains(point) { return }
            }
            var closest: (index: Int, distance: CGFloat)?
            for (index, polyline) in currentPolylines.enumerated() {
                let distance = screenDistance(from: point, to: polyline, on: mapView)
                if distance <= 20 && (closest == nil || distance < closest!.distance - 1 ||
                    (abs(distance - closest!.distance) <= 1 && index == selectedIndex)) {
                    closest = (index, distance)
                }
            }
            if let route = closest {
                parent.onSelectRoute?(route.index)
                return // A route tap must never teleport, including while simulation is running.
            }
            guard parent.allowsLocationSelection else { return }
            parent.tappedCoordinate = EquatableCoordinate(coordinate: mapView.convert(point, toCoordinateFrom: mapView))
        }

        private func screenDistance(from point: CGPoint, to polyline: MKPolyline, on mapView: MKMapView) -> CGFloat {
            guard polyline.pointCount > 1 else { return .greatestFiniteMagnitude }
            let points = polyline.points()
            var previous = mapView.convert(points[0].coordinate, toPointTo: mapView)
            var distance = CGFloat.greatestFiniteMagnitude
            for index in 1..<polyline.pointCount {
                let next = mapView.convert(points[index].coordinate, toPointTo: mapView)
                let dx = next.x - previous.x, dy = next.y - previous.y
                let lengthSquared = dx * dx + dy * dy
                let fraction = lengthSquared > 0
                    ? min(1, max(0, ((point.x - previous.x) * dx + (point.y - previous.y) * dy) / lengthSquared)) : 0
                distance = min(distance, hypot(point.x - previous.x - fraction * dx, point.y - previous.y - fraction * dy))
                previous = next
            }
            return distance
        }

        // Sample by distance: motorways and winding streets can have very different vertex counts.
        private func badgeCandidates(on polyline: MKPolyline) -> [CLLocationCoordinate2D] {
            guard polyline.pointCount > 1 else { return [polyline.coordinate] }
            let points = polyline.points()
            var lengths = [Double](repeating: 0, count: polyline.pointCount)
            for index in 1..<polyline.pointCount {
                lengths[index] = lengths[index - 1] + points[index - 1].distance(to: points[index])
            }
            let total = lengths.last ?? 0
            guard total > 0 else { return [points[0].coordinate] }
            return (2...8).map { step in
                let target = total * Double(step) / 10
                let index = max(1, lengths.firstIndex(where: { $0 >= target }) ?? lengths.count - 1)
                let fraction = (target - lengths[index - 1]) / max(0.001, lengths[index] - lengths[index - 1])
                let a = points[index - 1], b = points[index]
                return MKMapPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction).coordinate
            }
        }

        private func positionBadges(on mapView: MKMapView) {
            guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
            var occupied = routeAnnotations.compactMap { annotation -> CGRect? in
                guard annotation is RouteEndpointAnnotation else { return nil }
                let point = mapView.convert(annotation.coordinate, toPointTo: mapView)
                return CGRect(x: point.x - 42, y: point.y - 48, width: 84, height: 70)
            }
            let badges = routeAnnotations.compactMap { $0 as? RouteBadgeAnnotation }.sorted {
                ($0.routeIndex == selectedIndex ? -1 : $0.routeIndex) < ($1.routeIndex == selectedIndex ? -1 : $1.routeIndex)
            }
            for badge in badges {
                guard currentPolylines.indices.contains(badge.routeIndex) else { continue }
                let candidates = badgeCandidates(on: currentPolylines[badge.routeIndex])
                var best = candidates[0]
                var bestScore = -CGFloat.greatestFiniteMagnitude
                for coordinate in candidates {
                    let point = mapView.convert(coordinate, toPointTo: mapView)
                    let rect = CGRect(x: point.x - 57, y: point.y - 44, width: 114, height: 40)
                    let separation = currentPolylines.enumerated().filter { $0.offset != badge.routeIndex }
                        .map { screenDistance(from: point, to: $0.element, on: mapView) }.min() ?? 40
                    let overlaps = occupied.filter { $0.intersects(rect) }.count
                    let inBounds = mapView.bounds.insetBy(dx: 8, dy: 8).contains(rect)
                    let score = min(separation, 120) - CGFloat(overlaps) * 300 - (inBounds ? 0 : 500)
                    if score > bestScore { bestScore = score; best = coordinate }
                }
                badge.coordinate = best
                let point = mapView.convert(best, toPointTo: mapView)
                occupied.append(CGRect(x: point.x - 61, y: point.y - 48, width: 122, height: 48))
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { positionBadges(on: mapView) }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let badge = view.annotation as? RouteBadgeAnnotation else { return }
            parent.onSelectRoute?(badge.routeIndex)
            mapView.deselectAnnotation(badge, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            let index = currentPolylines.firstIndex(where: { $0 === polyline }) ?? 0
            renderer.strokeColor = routeColors[index % routeColors.count]
            renderer.lineWidth = index == selectedIndex ? 7 : 5
            renderer.alpha = index == selectedIndex ? 1 : 0.85
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let annotation = annotation as? ProposedPositionAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "ProposedPosition") as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "ProposedPosition")
                view.annotation = annotation
                view.markerTintColor = .systemIndigo
                view.glyphText = annotation.isRoutePreview ? nil : "?"
                view.glyphImage = annotation.isRoutePreview ? UIImage(systemName: "play.fill") : nil
                view.titleVisibility = .visible
                view.displayPriority = .required
                view.zPriority = .max
                view.canShowCallout = false
                view.accessibilityLabel = annotation.isRoutePreview ? "Route seek preview" : "Proposed location"
                return view
            }
            if let endpoint = annotation as? RouteEndpointAnnotation {
                let identifier = "RouteEndpoint"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.markerTintColor = endpoint.isStart ? .systemGreen : .systemRed
                view.glyphImage = nil
                view.glyphText = endpoint.isStart ? "A" : "B"
                view.titleVisibility = .visible
                view.subtitleVisibility = .hidden
                view.displayPriority = .required
                view.zPriority = .max
                view.canShowCallout = false
                view.accessibilityLabel = endpoint.title
                return view
            }
            if let badge = annotation as? RouteBadgeAnnotation {
                let identifier = "RouteBadge"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteBadgeAnnotationView
                    ?? RouteBadgeAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.configure(badge: badge, color: routeColors[badge.routeIndex % routeColors.count], selected: badge.routeIndex == selectedIndex)
                return view
            }
            if annotation is MovingAnnotation {
                let identifier = "MovingPosition"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.canShowCallout = false
                view.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
                view.backgroundColor = .systemBlue
                view.layer.cornerRadius = 12
                view.layer.borderWidth = 3
                view.layer.borderColor = UIColor.white.cgColor
                view.layer.shadowColor = UIColor.black.cgColor
                view.layer.shadowOffset = CGSize(width: 0, height: 1)
                view.layer.shadowRadius = 3
                view.layer.shadowOpacity = 0.3
                view.displayPriority = .required
                view.zPriority = .max
                view.accessibilityLabel = "Simulated position"
                return view
            }
            return nil
        }
    }
}

class MovingAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()
    var title: String?
}

final class ProposedPositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()
    let isRoutePreview: Bool
    init(isRoutePreview: Bool = false) { self.isRoutePreview = isRoutePreview }
    var title: String? { isRoutePreview ? "Preview" : "Move here?" }
}

final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let isStart: Bool
    var title: String? { isStart ? "Start" : "Destination" }
    init(coordinate: CLLocationCoordinate2D, isStart: Bool) {
        self.coordinate = coordinate
        self.isStart = isStart
    }
}

final class RouteBadgeAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let routeIndex: Int
    let eta: String
    init(coordinate: CLLocationCoordinate2D, routeIndex: Int, eta: String) {
        self.coordinate = coordinate
        self.routeIndex = routeIndex
        self.eta = eta
    }
}

final class RouteBadgeAnnotationView: MKAnnotationView {
    private let number = UILabel()
    private let eta = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        number.font = .systemFont(ofSize: 12, weight: .bold)
        number.textAlignment = .center
        number.layer.cornerRadius = 10
        number.clipsToBounds = true
        eta.font = .systemFont(ofSize: 13, weight: .semibold)
        addSubview(number)
        addSubview(eta)
        layer.cornerRadius = 10
        layer.borderWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        centerOffset = CGPoint(x: 0, y: -24)
        canShowCallout = false
        displayPriority = .required
        collisionMode = .rectangle
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(badge: RouteBadgeAnnotation, color: UIColor, selected: Bool) {
        number.text = String(badge.routeIndex + 1)
        number.textColor = selected ? color : .white
        number.backgroundColor = selected ? .white : color
        eta.text = badge.eta
        eta.textColor = selected ? .white : .label
        backgroundColor = selected ? color : .systemBackground
        layer.borderColor = color.cgColor
        let width = max(84, eta.intrinsicContentSize.width + 44)
        bounds = CGRect(x: 0, y: 0, width: width, height: 34)
        number.frame = CGRect(x: 7, y: 7, width: 20, height: 20)
        eta.frame = CGRect(x: 33, y: 0, width: width - 40, height: 34)
        zPriority = selected ? .max : .defaultSelected
        accessibilityLabel = "Route \(badge.routeIndex + 1), \(badge.eta)"
        accessibilityTraits = selected ? [.button, .selected] : [.button]
        accessibilityHint = "Select this route"
    }
}
