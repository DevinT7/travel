import Foundation
import SwiftData
import CoreLocation

// All models follow CloudKit rules (every property has a default, relationships are optional,
// no unique constraints) so iCloud sync can be switched on without a migration.

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    var destinationName: String = ""
    var destinationLatitude: Double = 0
    var destinationLongitude: Double = 0
    var countryCode: String?
    var timeZoneIdentifier: String?
    var startDate: Date = Date()
    var endDate: Date = Date()
    var createdAt: Date = Date()
    /// Legacy flag from the removed demo trip; only read to delete old demo data on launch.
    var isSample: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \FlightSegment.trip)
    var flights: [FlightSegment]? = []
    @Relationship(deleteRule: .cascade, inverse: \Stay.trip)
    var stays: [Stay]? = []
    @Relationship(deleteRule: .cascade, inverse: \PlanItem.trip)
    var planItems: [PlanItem]? = []

    init(name: String, destinationName: String, coordinate: CLLocationCoordinate2D,
         countryCode: String?, timeZoneIdentifier: String?, startDate: Date, endDate: Date) {
        self.name = name
        self.destinationName = destinationName
        self.destinationLatitude = coordinate.latitude
        self.destinationLongitude = coordinate.longitude
        self.countryCode = countryCode
        self.timeZoneIdentifier = timeZoneIdentifier
        self.startDate = startDate
        self.endDate = endDate
    }
}

extension Trip {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
    }

    /// Destination time zone. Every time in the plan is shown in this zone.
    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    var sortedFlights: [FlightSegment] {
        (flights ?? []).sorted { $0.departure.scheduled < $1.departure.scheduled }
    }

    var sortedStays: [Stay] {
        (stays ?? []).sorted { $0.checkIn < $1.checkIn }
    }

    /// Each calendar day of the trip, as the start of that day in the destination time zone.
    var days: [Date] {
        let cal = calendar
        let start = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: max(endDate, startDate))
        var result: [Date] = []
        var day = start
        while day <= end, result.count < 60 {
            result.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    var displayName: String { name.isEmpty ? destinationName : name }
}

/// One airport end of a flight. Stored as a Codable value on `FlightSegment`.
struct FlightEndpoint: Codable, Hashable {
    var iata: String = ""
    var airportName: String = ""
    var city: String = ""
    var countryCode: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var scheduled: Date = Date()
    var revised: Date?
    var terminal: String?
    var gate: String?
    var baggageBelt: String?

    static let empty = FlightEndpoint()

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
    /// Best-known time: revised if the airline has published one.
    var best: Date { revised ?? scheduled }
    var delayMinutes: Int {
        guard let revised else { return 0 }
        return Int(revised.timeIntervalSince(scheduled) / 60)
    }
}

@Model
final class FlightSegment {
    var id: UUID = UUID()
    var flightNumber: String = ""
    var airlineName: String = ""
    var airlineCode: String = ""
    var departure: FlightEndpoint = FlightEndpoint.empty
    var arrival: FlightEndpoint = FlightEndpoint.empty
    var status: String = "Scheduled"
    var aircraftModel: String?
    var distanceKm: Double?
    var lastUpdated: Date = Date()
    /// Legacy flag from the removed demo trip; only read to delete old demo data on launch.
    var isSample: Bool = false
    /// Last live position reported by AeroDataBox while the flight is in the air.
    var liveLatitude: Double?
    var liveLongitude: Double?
    var liveAltitudeFeet: Double?
    var liveSpeedKnots: Double?
    var liveHeading: Double?
    var livePositionAt: Date?
    var trip: Trip?

    init(flightNumber: String, airlineName: String, airlineCode: String,
         departure: FlightEndpoint, arrival: FlightEndpoint, status: String,
         aircraftModel: String?, distanceKm: Double?) {
        self.flightNumber = flightNumber
        self.airlineName = airlineName
        self.airlineCode = airlineCode
        self.departure = departure
        self.arrival = arrival
        self.status = status
        self.aircraftModel = aircraftModel
        self.distanceKm = distanceKm
    }

    var duration: TimeInterval { arrival.best.timeIntervalSince(departure.best) }
}

@Model
final class Stay {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var checkIn: Date = Date()
    var checkOut: Date = Date()
    var confirmationNumber: String = ""
    var notes: String = ""
    var trip: Trip?

    init(name: String, address: String, coordinate: CLLocationCoordinate2D, checkIn: Date, checkOut: Date) {
        self.name = name
        self.address = address
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.checkIn = checkIn
        self.checkOut = checkOut
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

@Model
final class PlanItem {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = DiscoverCategory.sights.rawValue
    /// False means the item is saved as an idea but not yet given a time.
    var isScheduled: Bool = true
    var start: Date = Date()
    var durationMinutes: Int = 60
    var latitude: Double?
    var longitude: Double?
    var address: String = ""
    var notes: String = ""
    var imageURLString: String?
    var externalURLString: String?
    /// Stable id from the source (Wikipedia page, MapKit identifier, Ticketmaster id).
    var sourceID: String?
    var isBooked: Bool = false
    var trip: Trip?

    init(title: String, category: DiscoverCategory, start: Date, durationMinutes: Int = 60) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.start = start
        self.durationMinutes = durationMinutes
    }

    var category: DiscoverCategory {
        get { DiscoverCategory(rawValue: categoryRaw) ?? .sights }
        set { categoryRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }
    var externalURL: URL? { externalURLString.flatMap(URL.init(string:)) }
}
