import Foundation
import MapKit

/// Builds a new trip (destination, dates and flights) from a pasted flight confirmation, so a trip
/// can start from "paste" instead of searching a city and picking dates by hand.
@MainActor
enum TripFromConfirmation {
    struct Draft {
        var destination: ResolvedPlace
        /// Calendar days in the user's calendar, ready for the date pickers.
        var startDate: Date
        var endDate: Date
        var flights: [FlightSegment]
        /// False when the confirmation has no flight home, so the end date is a guess.
        var hasReturn: Bool
        var unknownAirports: [String]
    }

    enum Failure: Error {
        case noFlights(unknownAirports: [String])
    }

    static func draft(from text: String) async -> Result<Draft, Failure> {
        let imported = await ConfirmationImporter.build(from: text, reference: .now)
        let flights = imported.flights.sorted { $0.departure.scheduled < $1.departure.scheduled }
        guard let first = flights.first, let last = flights.last else {
            return .failure(.noFlights(unknownAirports: imported.unknownAirports))
        }

        let origin = first.departure
        let isRoundTrip = flights.count > 1 && distance(last.arrival, origin) < 100_000
        let destinationAirport: FlightEndpoint
        let endDay: Date
        if isRoundTrip {
            // The stay is the longest gap between landing somewhere and taking off again;
            // shorter gaps are connections.
            var stayIndex = 0
            var longest = -Double.infinity
            for i in 0..<(flights.count - 1) {
                let gap = flights[i + 1].departure.scheduled.timeIntervalSince(flights[i].arrival.scheduled)
                if gap > longest { longest = gap; stayIndex = i }
            }
            destinationAirport = flights[stayIndex].arrival
            let leaving = flights[stayIndex + 1].departure
            endDay = localDay(leaving.scheduled, in: leaving.timeZone)
        } else {
            destinationAirport = last.arrival
            let landed = localDay(last.arrival.scheduled, in: last.arrival.timeZone)
            endDay = Calendar.current.date(byAdding: .day, value: 6, to: landed) ?? landed
        }
        let startDay = localDay(first.departure.scheduled, in: first.departure.timeZone)
        let destination = await city(for: destinationAirport)

        // Airports near the destination take its name (Apple Maps says "SeaTac", not "Seattle").
        for flight in flights {
            if near(flight.departure, destination.coordinate) { flight.departure.city = destination.name }
            if near(flight.arrival, destination.coordinate) { flight.arrival.city = destination.name }
        }
        return .success(Draft(destination: destination, startDate: startDay, endDate: max(endDay, startDay),
                              flights: flights, hasReturn: isRoundTrip, unknownAirports: imported.unknownAirports))
    }

    // MARK: Destination city

    /// Airports named after something other than the city they serve, or that sit in a suburb.
    private static let metro: [String: String] = [
        "JFK": "New York", "LGA": "New York", "EWR": "New York", "CDG": "Paris", "ORY": "Paris",
        "LHR": "London", "LGW": "London", "STN": "London", "LTN": "London", "LCY": "London",
        "NRT": "Tokyo", "HND": "Tokyo", "KIX": "Osaka", "ITM": "Osaka", "ICN": "Seoul", "GMP": "Seoul",
        "PEK": "Beijing", "PKX": "Beijing", "PVG": "Shanghai", "SHA": "Shanghai", "FCO": "Rome", "CIA": "Rome",
        "MXP": "Milan", "LIN": "Milan", "BGY": "Milan", "IAD": "Washington", "DCA": "Washington", "BWI": "Baltimore",
        "SEA": "Seattle", "ORD": "Chicago", "MDW": "Chicago", "DFW": "Dallas", "DAL": "Dallas", "IAH": "Houston",
        "HOU": "Houston", "SFO": "San Francisco", "OAK": "Oakland", "SJC": "San Jose", "LAX": "Los Angeles",
        "MCO": "Orlando", "FLL": "Fort Lauderdale", "MIA": "Miami", "ATL": "Atlanta", "BOS": "Boston",
        "DTW": "Detroit", "MSP": "Minneapolis", "DEN": "Denver", "PHX": "Phoenix", "LAS": "Las Vegas",
        "AUS": "Austin", "YYZ": "Toronto", "YUL": "Montreal", "YVR": "Vancouver", "MEX": "Mexico City",
        "CUN": "Cancún", "GRU": "São Paulo", "GIG": "Rio de Janeiro", "EZE": "Buenos Aires",
        "AMS": "Amsterdam", "FRA": "Frankfurt", "MUC": "Munich", "ZRH": "Zurich", "VIE": "Vienna",
        "BCN": "Barcelona", "MAD": "Madrid", "LIS": "Lisbon", "DUB": "Dublin", "CPH": "Copenhagen",
        "ARN": "Stockholm", "OSL": "Oslo", "HEL": "Helsinki", "IST": "Istanbul", "SAW": "Istanbul",
        "ATH": "Athens", "DXB": "Dubai", "DOH": "Doha", "AUH": "Abu Dhabi", "SIN": "Singapore",
        "HKG": "Hong Kong", "BKK": "Bangkok", "DMK": "Bangkok", "KUL": "Kuala Lumpur", "DEL": "Delhi",
        "BOM": "Mumbai", "SYD": "Sydney", "MEL": "Melbourne", "AKL": "Auckland", "HNL": "Honolulu",
        "OGG": "Maui", "SAN": "San Diego", "PDX": "Portland", "MSY": "New Orleans", "BNA": "Nashville",
    ]

    /// The city an airport serves, as a resolved place with its own coordinate and time zone.
    static func city(for airport: FlightEndpoint) async -> ResolvedPlace {
        var candidates: [String] = []
        if let name = metro[airport.iata] { candidates.append(name) }
        if let fromName = cityPart(of: airport.airportName) { candidates.append(fromName) }
        if !airport.city.isEmpty { candidates.append(airport.city) }

        let region = MKCoordinateRegion(center: airport.coordinate, latitudinalMeters: 150_000, longitudinalMeters: 150_000)
        for candidate in candidates {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = candidate
            request.resultTypes = .address
            request.region = region
            guard let items = try? await MKLocalSearch(request: request).start().mapItems else { continue }
            // A city, not a street with the same name, and close enough to the airport to be served by it.
            if let item = items.first(where: { $0.placemark.thoroughfare == nil && $0.placemark.locality != nil
                && distance($0.placemark.coordinate, airport.coordinate) < 90_000 }) {
                let p = item.placemark
                return ResolvedPlace(name: p.locality ?? candidate,
                                     address: [p.administrativeArea, p.country].compactMap { $0 }.joined(separator: ", "),
                                     coordinate: p.coordinate,
                                     countryCode: p.isoCountryCode ?? airport.countryCode,
                                     timeZoneIdentifier: item.timeZone?.identifier ?? airport.timeZoneIdentifier)
            }
        }
        return ResolvedPlace(name: airport.city.isEmpty ? airport.iata : airport.city, address: airport.airportName,
                             coordinate: airport.coordinate, countryCode: airport.countryCode,
                             timeZoneIdentifier: airport.timeZoneIdentifier)
    }

    /// "Seattle–Tacoma International Airport" → "Seattle".
    static func cityPart(of airportName: String) -> String? {
        var name = airportName
        for word in [" International", " Intl", " Airport", " Regional", " Municipal"] {
            if let r = name.range(of: word, options: .caseInsensitive) { name = String(name[..<r.lowerBound]) }
        }
        if let r = name.rangeOfCharacter(from: CharacterSet(charactersIn: "-–/")) { name = String(name[..<r.lowerBound]) }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.count >= 3 ? name : nil
    }

    // MARK: Helpers

    /// The calendar day of `date` at the airport, as midnight in the user's own calendar (for date pickers).
    private static func localDay(_ date: Date, in tz: TimeZone) -> Date {
        var airportCal = Calendar(identifier: .gregorian)
        airportCal.timeZone = tz
        let c = airportCal.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: c) ?? date
    }

    private static func distance(_ a: FlightEndpoint, _ b: FlightEndpoint) -> CLLocationDistance {
        distance(a.coordinate, b.coordinate)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func near(_ e: FlightEndpoint, _ c: CLLocationCoordinate2D) -> Bool { distance(e.coordinate, c) < 60_000 }
}
