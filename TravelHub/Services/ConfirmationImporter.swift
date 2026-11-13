import Foundation
import CoreLocation

/// Turns parsed confirmation text into real flights: looks up each airport (Apple Maps, no key)
/// and reads the local times in that airport's time zone.
@MainActor
enum ConfirmationImporter {
    struct Result {
        var flights: [FlightSegment] = []
        /// Airport codes Apple Maps couldn't find.
        var unknownAirports: [String] = []
    }

    static func build(from text: String, trip: Trip) async -> Result {
        var result = Result()
        for parsed in ConfirmationParser.parse(text, reference: trip.startDate) {
            guard let fromCode = parsed.fromCode, let toCode = parsed.toCode,
                  let day = parsed.date, let depTime = parsed.departs, let arrTime = parsed.arrives else { continue }
            guard var dep = await AirportLookup.resolve(code: fromCode) else { result.unknownAirports.append(fromCode); continue }
            guard var arr = await AirportLookup.resolve(code: toCode) else { result.unknownAirports.append(toCode); continue }

            guard let departs = date(day, depTime, in: dep.timeZone, plusDays: 0) else { continue }
            var arrives = date(day, arrTime, in: arr.timeZone, plusDays: parsed.arrivalDayOffset ?? 0) ?? departs
            // Without an explicit "+1", an arrival that lands "before" departure is on a later day.
            if parsed.arrivalDayOffset == nil {
                var extra = 0
                while arrives <= departs, extra < 2 {
                    extra += 1
                    arrives = date(day, arrTime, in: arr.timeZone, plusDays: extra) ?? arrives
                }
            }
            dep.scheduled = departs
            arr.scheduled = arrives
            if trip.isNearDestination(dep) { dep.city = trip.destinationName }
            if trip.isNearDestination(arr) { arr.city = trip.destinationName }

            let code = parsed.airlineCode ?? ""
            result.flights.append(FlightSegment(
                flightNumber: parsed.flightNumber, airlineName: Airlines.names[code] ?? code, airlineCode: code,
                departure: dep, arrival: arr, status: "Scheduled", aircraftModel: nil,
                distanceKm: AirportLookup.distanceKm(dep, arr)))
        }
        return result
    }

    private static func date(_ day: DateComponents, _ time: DateComponents, in tz: TimeZone, plusDays: Int) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var c = day
        c.hour = time.hour
        c.minute = time.minute
        guard let base = cal.date(from: c) else { return nil }
        return cal.date(byAdding: .day, value: plusDays, to: base)
    }
}

extension Trip {
    /// Airports near the destination take the destination's name (Apple Maps says "SeaTac", not "Seattle").
    func isNearDestination(_ e: FlightEndpoint) -> Bool {
        CLLocation(latitude: e.latitude, longitude: e.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 60_000
    }

    /// True when the trip already has this flight on the same departure day.
    func hasFlight(_ f: FlightSegment) -> Bool {
        (flights ?? []).contains {
            $0.flightNumber == f.flightNumber && abs($0.departure.scheduled.timeIntervalSince(f.departure.scheduled)) < 12 * 3600
        }
    }
}
