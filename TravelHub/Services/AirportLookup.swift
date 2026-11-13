import Foundation
import MapKit

/// Turns an airport code like "AUS" into a named airport with coordinates and time zone, using
/// Apple Maps (no key needed). The search region is the whole world so results aren't biased
/// toward the device's location.
enum AirportLookup {
    @MainActor private static var cache: [String: FlightEndpoint] = [:]

    @MainActor
    static func resolve(code raw: String) async -> FlightEndpoint? {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy(\.isLetter) else { return nil }
        if let hit = cache[code] { return hit }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(code) airport"
        request.region = MKCoordinateRegion(.world)
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }

        var endpoint = FlightEndpoint()
        endpoint.iata = code
        endpoint.airportName = item.name ?? code
        endpoint.city = item.placemark.locality ?? item.placemark.administrativeArea ?? ""
        endpoint.countryCode = item.placemark.isoCountryCode ?? ""
        endpoint.latitude = item.placemark.coordinate.latitude
        endpoint.longitude = item.placemark.coordinate.longitude
        endpoint.timeZoneIdentifier = item.timeZone?.identifier ?? TimeZone.current.identifier
        cache[code] = endpoint
        return endpoint
    }

    /// Great-circle distance between two airports in kilometers.
    static func distanceKm(_ a: FlightEndpoint, _ b: FlightEndpoint) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }
}
