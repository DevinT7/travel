#if DEBUG && os(iOS)
import ActivityKit
import SwiftData
import Foundation

/// Debug-only: launched with `-DemoFlight scheduled|delayed|inAir|landed`, replaces a "Demo Trip"
/// with one flight in that state and starts its Live Activity, so the Lock Screen and Dynamic
/// Island can be checked in the simulator without waiting for a real flight.
@MainActor
enum DebugFlightDemo {
    static func runIfRequested(context: ModelContext) async {
        // `-RunBackgroundRefresh YES` runs the background refresh once, as iOS would.
        defer {
            if UserDefaults.standard.bool(forKey: "RunBackgroundRefresh") {
                Task { await FlightBackgroundRefresh.run() }
            }
        }
        guard let phase = UserDefaults.standard.string(forKey: "DemoFlight") else { return }
        for activity in Activity<FlightActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        let old = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.name == "Demo Trip" }))) ?? []
        old.forEach(context.delete)

        let now = Date.now
        var dep = FlightEndpoint(iata: "AUS", airportName: "Austin-Bergstrom International Airport", city: "Austin",
                                 countryCode: "US", latitude: 30.1975, longitude: -97.6664, timeZoneIdentifier: "America/Chicago")
        var arr = FlightEndpoint(iata: "SEA", airportName: "Seattle-Tacoma International Airport", city: "Seattle",
                                 countryCode: "US", latitude: 47.4502, longitude: -122.3088, timeZoneIdentifier: "America/Los_Angeles")
        dep.terminal = "Barbara Jordan"; dep.gate = "24"; arr.terminal = "S"
        var status = "Expected"
        switch phase {
        case "delayed":
            dep.scheduled = now.addingTimeInterval(40 * 60); dep.revised = now.addingTimeInterval(85 * 60)
            arr.scheduled = dep.scheduled.addingTimeInterval(4 * 3600 + 20 * 60); arr.revised = arr.scheduled.addingTimeInterval(45 * 60)
            status = "Delayed"
        case "inAir":
            dep.scheduled = now.addingTimeInterval(-70 * 60); arr.scheduled = dep.scheduled.addingTimeInterval(4 * 3600 + 20 * 60)
            status = "EnRoute"
        case "landed":
            dep.scheduled = now.addingTimeInterval(-4 * 3600 - 30 * 60); arr.scheduled = now.addingTimeInterval(-10 * 60)
            arr.baggageBelt = "7"; status = "Arrived"
        default:
            dep.scheduled = now.addingTimeInterval(50 * 60); arr.scheduled = dep.scheduled.addingTimeInterval(4 * 3600 + 20 * 60)
        }

        let trip = Trip(name: "Demo Trip", destinationName: "Seattle", coordinate: .init(latitude: 47.6062, longitude: -122.3321),
                        countryCode: "US", timeZoneIdentifier: "America/Los_Angeles",
                        startDate: Calendar.current.startOfDay(for: now), endDate: now.addingTimeInterval(5 * 86400))
        let flight = FlightSegment(flightNumber: "AS 1043", airlineName: "Alaska Airlines", airlineCode: "AS",
                                   departure: dep, arrival: arr, status: status, aircraftModel: "Boeing 737-900",
                                   distanceKm: 2860)
        flight.lastUpdated = now.addingTimeInterval(-3600) // due for a refresh
        context.insert(trip)
        context.insert(flight)
        flight.trip = trip
        try? context.save()
        UserDefaults.standard.set(trip.id.uuidString, forKey: "selectedTripID")
        FlightActivities.start(flight)
    }
}
#endif
