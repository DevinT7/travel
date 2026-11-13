import Foundation
import CoreLocation
import MapKit

/// A city to browse in Discover other than the trip's destination (a day trip, the next stop).
struct ExplorePlace: Codable, Hashable, Identifiable {
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    /// Nearby suggestions start with an approximate point and are moved to the city center when picked.
    var isApproximate = false

    var id: String { "\(name)|\((latitude * 100).rounded())|\((longitude * 100).rounded())" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(name: String, subtitle: String, coordinate: CLLocationCoordinate2D, isApproximate: Bool = false) {
        self.name = name
        self.subtitle = subtitle
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.isApproximate = isApproximate
    }

    func distance(from c: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }
}

@MainActor
enum ExplorePlaces {
    // MARK: Nearby cities

    private static var nearbyCache: [String: [ExplorePlace]] = [:]

    /// Towns and cities within a couple of hours of `center`, found by looking up points on two rings
    /// around it (about 45 km and 120 km out). Calls `found` as each new one turns up.
    static func nearby(_ center: CLLocationCoordinate2D, excluding name: String,
                       found: ([ExplorePlace]) -> Void) async {
        let key = "\((center.latitude * 10).rounded()),\((center.longitude * 10).rounded())"
        if let cached = nearbyCache[key] { found(cached); return }

        let geocoder = CLGeocoder()
        var results: [ExplorePlace] = []
        var seen: Set<String> = [name.lowercased()]
        for radius in [45_000.0, 120_000.0] {
            for bearing in stride(from: 0.0, to: 360.0, by: 45.0) {
                guard !Task.isCancelled else { return }
                let point = offset(center, bearing: bearing, meters: radius)
                guard let mark = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: point.latitude, longitude: point.longitude)).first,
                      let city = mark.locality, !seen.contains(city.lowercased()) else { continue }
                seen.insert(city.lowercased())
                results.append(ExplorePlace(name: city,
                                            subtitle: [mark.administrativeArea, mark.isoCountryCode == nil ? nil : mark.country]
                                                .compactMap { $0 }.joined(separator: ", "),
                                            coordinate: mark.location?.coordinate ?? point, isApproximate: true))
                results.sort { $0.distance(from: center) < $1.distance(from: center) }
                found(results)
            }
        }
        nearbyCache[key] = results
    }

    /// Moves an approximate suggestion to the city's own center so Discover searches the middle of town.
    static func resolved(_ place: ExplorePlace) async -> ExplorePlace {
        guard place.isApproximate else { return place }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [place.name, place.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        request.resultTypes = .address
        request.region = MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems
            .first(where: { $0.placemark.thoroughfare == nil }) else {
            var p = place; p.isApproximate = false; return p
        }
        return ExplorePlace(name: item.placemark.locality ?? place.name, subtitle: place.subtitle, coordinate: item.placemark.coordinate)
    }

    // MARK: Other stops on the trip

    /// Cities the trip's flights land in, other than the destination (a multi-city trip's other stops).
    static func otherStops(on trip: Trip) -> [ExplorePlace] {
        let home = trip.sortedFlights.first?.departure.iata
        var seen: Set<String> = []
        return trip.sortedFlights.compactMap { f -> ExplorePlace? in
            let a = f.arrival
            guard a.iata != home, !trip.isNearDestination(a), !a.city.isEmpty, seen.insert(a.city).inserted else { return nil }
            return ExplorePlace(name: a.city, subtitle: a.airportName, coordinate: a.coordinate, isApproximate: true)
        }
    }

    // MARK: Recently explored (per trip)

    private static func recentsKey(_ trip: Trip) -> String { "exploreRecents.\(trip.id.uuidString)" }

    static func recents(for trip: Trip) -> [ExplorePlace] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey(trip)) else { return [] }
        return (try? JSONDecoder().decode([ExplorePlace].self, from: data)) ?? []
    }

    static func remember(_ place: ExplorePlace, for trip: Trip) {
        var list = recents(for: trip).filter { $0.name != place.name }
        list.insert(place, at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(6))) {
            UserDefaults.standard.set(data, forKey: recentsKey(trip))
        }
    }

    // MARK: Geometry

    private static func offset(_ c: CLLocationCoordinate2D, bearing: Double, meters: Double) -> CLLocationCoordinate2D {
        let r = 6_371_000.0, d = meters / r, b = bearing * .pi / 180
        let lat1 = c.latitude * .pi / 180, lon1 = c.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
        let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return .init(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
