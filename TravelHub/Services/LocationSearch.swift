import Foundation
import MapKit
import Observation

/// A resolved place: a city for a trip destination, or a hotel for a stay.
struct ResolvedPlace: Hashable {
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var countryCode: String?
    var timeZoneIdentifier: String?

    static func == (l: ResolvedPlace, r: ResolvedPlace) -> Bool {
        l.name == r.name && l.coordinate.latitude == r.coordinate.latitude && l.coordinate.longitude == r.coordinate.longitude
    }
    func hash(into h: inout Hasher) { h.combine(name); h.combine(coordinate.latitude); h.combine(coordinate.longitude) }
}

/// Type-ahead search backed by MKLocalSearchCompleter (cities or hotels).
@MainActor
@Observable
final class LocationSearch: NSObject, MKLocalSearchCompleterDelegate {
    enum Kind { case city, hotel }

    var query = "" { didSet { update() } }
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    private let kind: Kind

    init(kind: Kind, near region: MKCoordinateRegion? = nil) {
        self.kind = kind
        super.init()
        completer.delegate = self
        switch kind {
        case .city:
            completer.resultTypes = .address
        case .hotel:
            completer.resultTypes = [.pointOfInterest, .address]
            completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hotel, .campground, .rvPark])
        }
        if let region { completer.region = region }
    }

    private func update() {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { results = [] } else { completer.queryFragment = q }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        MainActor.assumeIsolated {
            // For cities, hide street addresses (they have a number in the title).
            self.results = kind == .city
                ? results.filter { !$0.title.contains(where: \.isNumber) }
                : results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> ResolvedPlace? {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else { return nil }
        let p = item.placemark
        let name = kind == .city ? (p.locality ?? completion.title) : (item.name ?? completion.title)
        return ResolvedPlace(
            name: name,
            address: kind == .city ? completion.subtitle : MapKitPlacesProvider.address(p),
            coordinate: p.coordinate,
            countryCode: p.isoCountryCode ?? p.countryCode,
            timeZoneIdentifier: item.timeZone?.identifier
        )
    }
}
