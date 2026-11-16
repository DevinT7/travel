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
    @Relationship(deleteRule: .cascade, inverse: \DriveLeg.trip)
    var drives: [DriveLeg]? = []
    /// How the traveler gets between stops on the ground (`GettingAround`).
    var gettingAroundRaw: String = GettingAround.auto.rawValue

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

    var sortedDrives: [DriveLeg] {
        (drives ?? []).sorted { $0.departure < $1.departure }
    }

    var gettingAround: GettingAround {
        get { GettingAround(rawValue: gettingAroundRaw) ?? .auto }
        set { gettingAroundRaw = newValue.rawValue }
    }

    /// Where the traveler is sleeping on a given night, if a stay covers it.
    func stay(on date: Date) -> Stay? {
        sortedStays.first { $0.checkIn <= date && date <= $0.checkOut }
            ?? sortedStays.first { calendar.isDate($0.checkIn, inSameDayAs: date) || calendar.isDate($0.checkOut, inSameDayAs: date) }
    }

    /// Each calendar day of the trip, as the start of that day in the destination time zone.
    /// Today falls between the first and last day of the trip, in the destination's time zone.
    var isUnderway: Bool {
        let cal = calendar
        let today = cal.startOfDay(for: .now)
        return today >= cal.startOfDay(for: startDate) && today <= cal.startOfDay(for: endDate)
    }

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

/// How the traveler gets between plan stops on the ground. "Auto" walks short hops and takes
/// transit (or drives, where there's none) for longer ones.
enum GettingAround: String, CaseIterable, Identifiable, Codable {
    case auto, drive, transit, walk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .drive: "Driving"
        case .transit: "Transit"
        case .walk: "Walking"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath"
        case .drive: "car.fill"
        case .transit: "tram.fill"
        case .walk: "figure.walk"
        }
    }
}

/// One end of a drive: a hotel, an airport, a plan stop or any address.
struct DrivePlace: Codable, Hashable {
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0

    static let empty = DrivePlace()

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var isSet: Bool { latitude != 0 || longitude != 0 }

    init(name: String = "", address: String = "", coordinate: CLLocationCoordinate2D? = nil) {
        self.name = name
        self.address = address
        self.latitude = coordinate?.latitude ?? 0
        self.longitude = coordinate?.longitude ?? 0
    }
}

/// A drive on the trip: a road-trip leg, the ride from the airport, or a day trip out of town.
/// Drive time and distance come from Apple Maps (with traffic for the planned departure) and are
/// stored so the plan and CarPlay can show them without a network request.
@Model
final class DriveLeg {
    var id: UUID = UUID()
    var from: DrivePlace = DrivePlace.empty
    var to: DrivePlace = DrivePlace.empty
    var departure: Date = Date()
    /// Expected drive time from Apple Maps; 0 until the route has been looked up.
    var travelMinutes: Int = 0
    var distanceMeters: Double = 0
    var avoidTolls: Bool = false
    var avoidHighways: Bool = false
    /// Rental car, own car, ride share: free text shown under the route.
    var vehicle: String = ""
    var notes: String = ""
    var routeUpdatedAt: Date?
    var trip: Trip?

    init(from: DrivePlace, to: DrivePlace, departure: Date) {
        self.from = from
        self.to = to
        self.departure = departure
    }

    var arrival: Date { departure.addingTimeInterval(TimeInterval(max(travelMinutes, 0) * 60)) }
    var title: String { "Drive to \(to.name.isEmpty ? "destination" : to.name)" }
}
