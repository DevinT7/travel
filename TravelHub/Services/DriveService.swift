import Foundation
import MapKit

/// A driving route from Apple Maps.
struct DriveRoute {
    let minutes: Int
    let meters: Double
    let coordinates: [CLLocationCoordinate2D]
}

/// Driving routes, drive times and hand-off to Apple Maps for turn-by-turn directions.
///
/// TravelHub plans the drive; Maps (on the phone or in CarPlay) does the navigating.
@MainActor
final class DriveService {
    static let shared = DriveService()
    private var cache: [String: DriveRoute] = [:]

    enum Failure: LocalizedError {
        case noRoute
        var errorDescription: String? { "Apple Maps couldn't find a driving route between these places." }
    }

    /// Traffic-aware when the departure is in the future.
    func route(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, departure: Date? = nil,
               avoidTolls: Bool = false, avoidHighways: Bool = false) async throws -> DriveRoute {
        // Departures are bucketed to 15 minutes so small time edits reuse the route.
        let bucket = departure.map { Int($0.timeIntervalSince1970 / 900) } ?? 0
        let key = String(format: "%.4f,%.4f>%.4f,%.4f", a.latitude, a.longitude, b.latitude, b.longitude)
            + "|\(bucket)|\(avoidTolls)|\(avoidHighways)"
        if let hit = cache[key] { return hit }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .automobile
        if let departure, departure > .now { request.departureDate = departure }
        request.tollPreference = avoidTolls ? .avoid : .any
        request.highwayPreference = avoidHighways ? .avoid : .any
        let response = try await MKDirections(request: request).calculate()
        guard let best = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            throw Failure.noRoute
        }
        let route = DriveRoute(minutes: max(1, Int((best.expectedTravelTime / 60).rounded())),
                               meters: best.distance,
                               coordinates: best.polyline.coordinates)
        cache[key] = route
        return route
    }

    func route(for leg: DriveLeg) async throws -> DriveRoute {
        try await route(from: leg.from.coordinate, to: leg.to.coordinate, departure: leg.departure,
                        avoidTolls: leg.avoidTolls, avoidHighways: leg.avoidHighways)
    }

    /// Looks the route up again and stores the new drive time and distance on the leg.
    @discardableResult
    func refresh(_ leg: DriveLeg) async -> DriveRoute? {
        guard leg.from.isSet, leg.to.isSet, let route = try? await route(for: leg) else { return nil }
        leg.travelMinutes = route.minutes
        leg.distanceMeters = route.meters
        leg.routeUpdatedAt = .now
        return route
    }

    // MARK: Hand-off to Maps

    /// Opens Apple Maps with directions from wherever the traveler is now.
    static func openDirections(to place: DrivePlace, mode: GettingAround = .drive) {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        destination.name = place.name.isEmpty ? nil : place.name
        let key = switch mode {
        case .drive: MKLaunchOptionsDirectionsModeDriving
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .walk: MKLaunchOptionsDirectionsModeWalking
        case .auto: MKLaunchOptionsDirectionsModeDefault
        }
        MKMapItem.openMaps(with: [MKMapItem.forCurrentLocation(), destination],
                           launchOptions: [MKLaunchOptionsDirectionsModeKey: key])
    }

    /// A Maps URL for driving directions; CarPlay opens it in Maps on the car's screen.
    nonisolated static func mapsURL(to place: DrivePlace) -> URL {
        var c = URLComponents(string: "maps://")!
        c.queryItems = [URLQueryItem(name: "daddr", value: "\(place.latitude),\(place.longitude)"),
                        URLQueryItem(name: "dirflg", value: "d")]
        if !place.name.isEmpty { c.queryItems?.append(URLQueryItem(name: "q", value: place.name)) }
        return c.url!
    }

    // MARK: Formatting

    /// 135 → "2 h 15 min", 40 → "40 min".
    nonisolated static func durationText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        if minutes < 60 { return "\(minutes) min" }
        let m = minutes % 60
        return m == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(m) min"
    }

    /// In miles or kilometers, following the region's settings.
    nonisolated static func distanceText(_ meters: Double) -> String {
        guard meters > 0 else { return "" }
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = meters < 10_000 ? 1 : 0
        let usesMiles = Locale.current.measurementSystem != .metric
        let value = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: usesMiles ? .miles : .kilometers)
        formatter.unitOptions = .providedUnit
        return formatter.string(from: value)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

extension DriveLeg {
    /// "2 h 15 min · 180 km"
    var summaryText: String {
        [DriveService.durationText(travelMinutes), DriveService.distanceText(distanceMeters)]
            .filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · ")
    }
}
