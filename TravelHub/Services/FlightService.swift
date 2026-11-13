import Foundation

/// Looks up flights by number using AeroDataBox (via RapidAPI, free "Basic" plan).
/// Docs: https://rapidapi.com/aedbx-aedbx/api/aerodatabox
struct FlightService {
    private static let host = "aerodatabox.p.rapidapi.com"

    /// Normalizes "ua 837", "UA-837" → "UA837".
    static func normalize(_ number: String) -> String {
        number.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Returns every leg flying under this number on the given local departure date.
    func lookup(flightNumber: String, date: Date, timeZone: TimeZone = .current) async throws -> [FlightSegment] {
        guard let key = APIKeys.aeroDataBox else { throw APIError.missingKey("AeroDataBox") }
        let number = Self.normalize(flightNumber)
        guard number.count >= 3 else { throw APIError.notFound }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let url = URL(string: "https://\(Self.host)/flights/number/\(number)/\(dateFormatter.string(from: date))")!
            .appending(query: ["withAircraftImage": "false", "withLocation": "true", "dateLocalRole": "Departure"])
        let flights: [ADBFlight] = try await HTTP.get(url, headers: ["X-RapidAPI-Key": key, "X-RapidAPI-Host": Self.host],
                                                      service: "AeroDataBox")
        let segments = flights.compactMap { $0.segment }
        if segments.isEmpty { throw APIError.notFound }
        return segments
    }

    /// Re-fetches live status for a saved flight and copies new times/gates onto it.
    func refresh(_ flight: FlightSegment) async throws {
        let legs = try await lookup(flightNumber: flight.flightNumber, date: flight.departure.scheduled,
                                    timeZone: flight.departure.timeZone)
        guard let match = legs.first(where: { $0.departure.iata == flight.departure.iata }) ?? legs.first else { return }
        flight.departure = match.departure
        flight.arrival = match.arrival
        flight.status = match.status
        flight.aircraftModel = match.aircraftModel ?? flight.aircraftModel
        if match.airlineName.isEmpty == false { flight.airlineName = match.airlineName }
        if match.livePositionAt != nil {
            flight.liveLatitude = match.liveLatitude
            flight.liveLongitude = match.liveLongitude
            flight.liveAltitudeFeet = match.liveAltitudeFeet
            flight.liveSpeedKnots = match.liveSpeedKnots
            flight.liveHeading = match.liveHeading
            flight.livePositionAt = match.livePositionAt
        }
        flight.lastUpdated = .now
    }
}

// MARK: - AeroDataBox response

private struct ADBFlight: Decodable {
    struct Airport: Decodable {
        struct Location: Decodable { let lat: Double; let lon: Double }
        let iata: String?
        let icao: String?
        let name: String?
        let shortName: String?
        let municipalityName: String?
        let countryCode: String?
        let timeZone: String?
        let location: Location?
    }
    struct Time: Decodable { let utc: String?; let local: String? }
    struct Movement: Decodable {
        let airport: Airport
        let scheduledTime: Time?
        let revisedTime: Time?
        let predictedTime: Time?
        let terminal: String?
        let gate: String?
        let baggageBelt: String?
        // Older API versions used flat fields.
        let scheduledTimeUtc: String?
        let actualTimeUtc: String?
    }
    struct Airline: Decodable { let name: String?; let iata: String?; let icao: String? }
    struct Aircraft: Decodable { let model: String? }
    struct Distance: Decodable { let km: Double? }
    /// Real-time position, present while the flight is airborne and tracked.
    struct Live: Decodable {
        struct Feet: Decodable { let feet: Double? }
        struct Speed: Decodable { let kt: Double? }
        struct Degrees: Decodable { let deg: Double? }
        let lat: Double?
        let lon: Double?
        let altitude: Feet?
        let pressureAltitude: Feet?
        let groundSpeed: Speed?
        let trueTrack: Degrees?
        let reportedAtUtc: String?
    }
    /// Decodes a value if it can, and otherwise leaves it nil instead of failing the whole flight.
    struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    let number: String?
    let status: String?
    let departure: Movement
    let arrival: Movement
    let airline: Airline?
    let aircraft: Aircraft?
    let greatCircleDistance: Distance?
    let location: Lenient<Live>?

    var segment: FlightSegment? {
        guard let dep = endpoint(departure), let arr = endpoint(arrival) else { return nil }
        let segment = FlightSegment(
            flightNumber: number ?? "",
            airlineName: airline?.name ?? "",
            airlineCode: airline?.iata ?? airline?.icao ?? "",
            departure: dep, arrival: arr,
            status: Self.prettyStatus(status),
            aircraftModel: aircraft?.model,
            distanceKm: greatCircleDistance?.km
        )
        if let live = location?.value, let lat = live.lat, let lon = live.lon {
            segment.liveLatitude = lat
            segment.liveLongitude = lon
            // `altitude` is often reported as 0 (no geometric reading); pressure altitude is what pilots fly.
            segment.liveAltitudeFeet = [live.pressureAltitude?.feet, live.altitude?.feet].compactMap { $0 }.first { $0 > 0 }
            segment.liveSpeedKnots = live.groundSpeed?.kt
            segment.liveHeading = live.trueTrack?.deg
            segment.livePositionAt = ADBDate.parse(live.reportedAtUtc) ?? .now
        }
        return segment
    }

    private func endpoint(_ m: Movement) -> FlightEndpoint? {
        guard let scheduled = ADBDate.parse(m.scheduledTime?.utc ?? m.scheduledTimeUtc) else { return nil }
        let revised = ADBDate.parse(m.revisedTime?.utc) ?? ADBDate.parse(m.predictedTime?.utc) ?? ADBDate.parse(m.actualTimeUtc)
        return FlightEndpoint(
            iata: m.airport.iata ?? m.airport.icao ?? "—",
            airportName: m.airport.name ?? "",
            city: m.airport.municipalityName ?? m.airport.shortName ?? m.airport.name ?? "",
            countryCode: m.airport.countryCode ?? "",
            latitude: m.airport.location?.lat ?? 0,
            longitude: m.airport.location?.lon ?? 0,
            timeZoneIdentifier: m.airport.timeZone ?? TimeZone.current.identifier,
            scheduled: scheduled,
            revised: revised,
            terminal: m.terminal, gate: m.gate, baggageBelt: m.baggageBelt
        )
    }

    /// AeroDataBox uses CamelCase states like "EnRoute", "CanceledUncertain".
    static func prettyStatus(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, raw != "Unknown" else { return "Scheduled" }
        switch raw {
        case "Expected": return "Scheduled"
        case "EnRoute", "Departed": return "In Air"
        case "Approaching": return "Approaching"
        case "CheckIn": return "Check-in"
        case "GateClosed": return "Gate Closed"
        case "Canceled", "CanceledUncertain": return "Canceled"
        default:
            return raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
    }
}

private enum ADBDate {
    private static let formatters: [DateFormatter] = ["yyyy-MM-dd HH:mmXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX",
                                                      "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mmXXXXX",
                                                      "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = $0
        return f
    }

    private static let utcMinute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        for f in formatters { if let d = f.date(from: string) { return d } }
        // Position reports come as UTC without a zone suffix.
        return utcMinute.date(from: string)
    }
}
