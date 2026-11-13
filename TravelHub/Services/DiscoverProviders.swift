import Foundation
import MapKit

// MARK: - Apple Maps (free, no key)

/// Restaurants, cafés, bars, museums, parks and shops from Apple Maps.
struct MapKitPlacesProvider {
    func search(category: DiscoverCategory, near center: CLLocationCoordinate2D, radius: CLLocationDistance = 6000) async throws -> [DiscoverItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.mapKitQuery
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        request.resultTypes = .pointOfInterest
        if !category.mapKitCategories.isEmpty {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: category.mapKitCategories)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { Self.item(from: $0, fallback: category) }
    }

    /// Free-text search ("ramen", "rooftop bar", "Louvre") around the destination.
    func search(query: String, near center: CLLocationCoordinate2D, radius: CLLocationDistance = 15000) async throws -> [DiscoverItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        request.resultTypes = [.pointOfInterest, .address]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { Self.item(from: $0, fallback: .other) }
    }

    static func item(from mapItem: MKMapItem, fallback: DiscoverCategory) -> DiscoverItem {
        let mapped = DiscoverCategory(mapKitCategory: mapItem.pointOfInterestCategory)
        let category = mapped == .other ? fallback : mapped
        let placemark = mapItem.placemark
        let area = placemark.subLocality ?? placemark.locality ?? ""
        let kind = mapItem.pointOfInterestCategory.map(Self.displayName) ?? category.title
        let identifier = mapItem.identifier?.rawValue
        return DiscoverItem(
            id: identifier ?? "mk-\(placemark.coordinate.latitude),\(placemark.coordinate.longitude)-\(mapItem.name ?? "")",
            title: mapItem.name ?? "Unnamed place",
            subtitle: [kind, area].filter { !$0.isEmpty }.joined(separator: " · "),
            category: category,
            source: .appleMaps,
            coordinate: placemark.coordinate,
            address: Self.address(placemark),
            externalURL: mapItem.url,
            phone: mapItem.phoneNumber,
            mapItemIdentifier: identifier
        )
    }

    static func address(_ p: MKPlacemark) -> String {
        [p.subThoroughfare.map { "\($0) " + (p.thoroughfare ?? "") } ?? p.thoroughfare, p.locality, p.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// "MKPOICategoryNationalPark" → "National Park"
    static func displayName(_ c: MKPointOfInterestCategory) -> String {
        c.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }
}

// MARK: - Wikipedia (free, no key)

/// Landmarks and sights near the destination, with photos and descriptions, from Wikipedia's geosearch.
struct WikipediaProvider {
    /// A page counts as a sight only if its short description names a kind of attraction…
    private static let attractionWords = [
        "temple", "shrine", "museum", "park", "garden", "tower", "castle", "palace", "bridge", "market", "landmark",
        "monument", "memorial", "cathedral", "church", "basilica", "mosque", "synagogue", "pagoda", "skyscraper",
        "observation", "observatory", "zoo", "aquarium", "gallery", "theatre", "theater", "opera", "concert hall",
        "stadium", "arena", "square", "plaza", "statue", "fountain", "historic", "heritage", "shopping district",
        "entertainment district", "shopping street", "crossing", "beach", "island", "lake", "viewpoint", "gate",
        "amusement", "theme park", "attraction", "library", "monastery", "abbey", "fort", "ruins", "lighthouse",
    ]
    /// …and doesn't describe an event, organization or ordinary building.
    private static let excludedWords = [
        "attack", "disaster", "earthquake", "battle", "incident", "massacre", "bombing", "accident", "election",
        "station", "school", "university", "hospital", "company", "office", "embassy", "hotel", "residence",
        "headquarters", "ministry", "prefecture", "constituency", "list article", "railway", "expressway",
        "demolished", "former", "destroyed", " fire", "école", "grande école",
    ]

    /// Two calls: find attraction pages nearby, rank by article length (a decent proxy for how notable a
    /// place is), then fetch photos for the top results.
    func sights(near c: CLLocationCoordinate2D) async throws -> [DiscoverItem] {
        let api = URL(string: "https://en.wikipedia.org/w/api.php")!
        let nearby: WikiQuery = try await HTTP.get(api.appending(query: [
            "action": "query", "format": "json", "formatversion": "2",
            "generator": "geosearch", "ggscoord": "\(c.latitude)|\(c.longitude)",
            "ggsradius": "10000", "ggslimit": "500",
            "prop": "coordinates|description|info", "colimit": "max", "inprop": "url",
        ]), service: "Wikipedia")

        let ranked = (nearby.query?.pages ?? [])
            .filter { page in
                guard page.coordinates?.first != nil, let d = page.description?.lowercased() else { return false }
                return Self.attractionWords.contains { d.contains($0) } && !Self.excludedWords.contains { d.contains($0) }
            }
            .sorted { ($0.length ?? 0) > ($1.length ?? 0) }
            .prefix(40)
        guard !ranked.isEmpty else { return [] }

        let images: WikiQuery? = try? await HTTP.get(api.appending(query: [
            "action": "query", "format": "json", "formatversion": "2",
            "pageids": ranked.map { String($0.pageid) }.joined(separator: "|"),
            "prop": "pageimages", "piprop": "thumbnail", "pithumbsize": "800", "pilimit": "50",
        ]), service: "Wikipedia")
        var thumbs: [Int: String] = [:]
        for page in images?.query?.pages ?? [] { if let t = page.thumbnail { thumbs[page.pageid] = t.source } }

        return ranked.compactMap { page in
            guard let coord = page.coordinates?.first else { return nil }
            return DiscoverItem(
                id: "wiki-\(page.pageid)",
                title: page.title,
                subtitle: page.description.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Landmark",
                category: .sights,
                source: .wikipedia,
                coordinate: .init(latitude: coord.lat, longitude: coord.lon),
                imageURL: thumbs[page.pageid].flatMap(URL.init(string:)),
                externalURL: page.fullurl.flatMap(URL.init(string:))
            )
        }
    }

    /// The intro paragraph for a page, fetched when a sight is opened.
    func summary(title: String) async throws -> (text: String, image: URL?) {
        let encoded = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? title
        let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")!
        let s: WikiSummary = try await HTTP.get(url, service: "Wikipedia")
        return (s.extract ?? "", (s.originalimage ?? s.thumbnail).flatMap { URL(string: $0.source) })
    }

    private struct WikiQuery: Decodable {
        struct Q: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            struct Coord: Decodable { let lat: Double; let lon: Double }
            struct Thumb: Decodable { let source: String }
            let pageid: Int
            let title: String
            let description: String?
            let coordinates: [Coord]?
            let thumbnail: Thumb?
            let fullurl: String?
            let length: Int?
        }
        let query: Q?
    }

    private struct WikiSummary: Decodable {
        struct Img: Decodable { let source: String }
        let extract: String?
        let thumbnail: Img?
        let originalimage: Img?
    }
}

// MARK: - Ticketmaster (free key, 5,000 calls/day)

/// Concerts, sports, theatre and festivals happening during the trip.
/// Docs: https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/
struct TicketmasterProvider {
    func events(near c: CLLocationCoordinate2D, from start: Date, to end: Date) async throws -> [DiscoverItem] {
        guard let key = APIKeys.ticketmaster else { throw APIError.missingKey("Ticketmaster") }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let from = max(start, .now)
        guard from < end else { return [] }
        let url = URL(string: "https://app.ticketmaster.com/discovery/v2/events.json")!.appending(query: [
            "apikey": key, "latlong": "\(c.latitude),\(c.longitude)", "radius": "40", "unit": "km",
            "startDateTime": iso.string(from: from), "endDateTime": iso.string(from: end),
            "size": "60", "sort": "date,asc",
        ])
        let response: TMResponse = try await HTTP.get(url, service: "Ticketmaster")
        var seen = Set<String>()
        return (response._embedded?.events ?? []).compactMap { e -> DiscoverItem? in
            // Ticketmaster lists each performance separately; keep one card per show name.
            guard seen.insert(e.name).inserted else { return nil }
            let venue = e._embedded?.venues?.first
            let coordinate = venue?.location.flatMap { loc -> CLLocationCoordinate2D? in
                guard let lat = Double(loc.latitude), let lon = Double(loc.longitude) else { return nil }
                return .init(latitude: lat, longitude: lon)
            }
            let image = e.images?.filter { $0.ratio == "16_9" }.max { ($0.width ?? 0) < ($1.width ?? 0) } ?? e.images?.first
            let genre = [e.classifications?.first?.segment?.name, e.classifications?.first?.genre?.name]
                .compactMap { $0 }.filter { $0 != "Undefined" }.joined(separator: " · ")
            let price = e.priceRanges?.first.map { p in
                let f = p.min.map { $0.formatted(.currency(code: p.currency ?? "USD").precision(.fractionLength(0))) }
                return f.map { "From \($0)" }
            } ?? nil
            return DiscoverItem(
                id: "tm-\(e.id)",
                title: e.name,
                subtitle: [venue?.name, genre.isEmpty ? nil : genre].compactMap { $0 }.joined(separator: " · "),
                category: .events,
                source: .ticketmaster,
                coordinate: coordinate,
                address: [venue?.address?.line1, venue?.city?.name].compactMap { $0 }.joined(separator: ", "),
                imageURL: image.flatMap { URL(string: $0.url) },
                summary: e.info ?? e.pleaseNote,
                externalURL: e.url.flatMap(URL.init(string:)),
                eventDate: e.dates?.start?.dateTime.flatMap { iso.date(from: $0) },
                priceText: price
            )
        }
    }

    private struct TMResponse: Decodable {
        struct Embedded: Decodable { let events: [Event]? }
        struct Event: Decodable {
            struct Image: Decodable { let url: String; let ratio: String?; let width: Int? }
            struct Dates: Decodable { struct Start: Decodable { let dateTime: String? }; let start: Start? }
            struct Classification: Decodable {
                struct Named: Decodable { let name: String? }
                let segment: Named?; let genre: Named?
            }
            struct Price: Decodable { let min: Double?; let currency: String? }
            struct VenueEmbed: Decodable { let venues: [Venue]? }
            struct Venue: Decodable {
                struct Loc: Decodable { let latitude: String; let longitude: String }
                struct Addr: Decodable { let line1: String? }
                struct City: Decodable { let name: String? }
                let name: String?; let location: Loc?; let address: Addr?; let city: City?
            }
            let id: String
            let name: String
            let url: String?
            let info: String?
            let pleaseNote: String?
            let images: [Image]?
            let dates: Dates?
            let classifications: [Classification]?
            let priceRanges: [Price]?
            let _embedded: VenueEmbed?
        }
        let _embedded: Embedded?
    }
}
