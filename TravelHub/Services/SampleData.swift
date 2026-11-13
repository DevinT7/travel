import Foundation
import SwiftData
import CoreLocation

/// A clearly-labeled demo trip so the app can be explored without API keys.
enum SampleData {
    @MainActor
    @discardableResult
    static func insertTokyoTrip(into context: ModelContext) -> Trip {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo
        let firstDay = cal.startOfDay(for: Date.now.addingTimeInterval(9 * 86_400))

        func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ tz: TimeZone = tokyo) -> Date {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = tz
            let base = cal.date(byAdding: .day, value: day, to: firstDay)!
            var comps = cal.dateComponents([.year, .month, .day], from: base)
            comps.hour = hour
            comps.minute = minute
            return c.date(from: comps)!
        }

        let trip = Trip(name: "Tokyo", destinationName: "Tokyo",
                        coordinate: .init(latitude: 35.6812, longitude: 139.7671),
                        countryCode: "JP", timeZoneIdentifier: tokyo.identifier,
                        startDate: at(0, 0), endDate: at(7, 0))
        trip.isSample = true
        context.insert(trip)

        let sfo = FlightEndpoint(iata: "SFO", airportName: "San Francisco International", city: "San Francisco",
                                 countryCode: "US", latitude: 37.6190, longitude: -122.3749,
                                 timeZoneIdentifier: pacific.identifier, scheduled: Date())
        let hnd = FlightEndpoint(iata: "HND", airportName: "Tokyo Haneda", city: "Tokyo",
                                 countryCode: "JP", latitude: 35.5494, longitude: 139.7798,
                                 timeZoneIdentifier: tokyo.identifier, scheduled: Date())

        var outDep = sfo; outDep.scheduled = at(-1, 11, 0, pacific); outDep.terminal = "I"; outDep.gate = "G94"
        var outArr = hnd; outArr.scheduled = at(0, 15, 25); outArr.terminal = "3"; outArr.baggageBelt = "7"
        let outbound = FlightSegment(flightNumber: "XX 101", airlineName: "Sample Air", airlineCode: "XX",
                                     departure: outDep, arrival: outArr, status: "Scheduled",
                                     aircraftModel: "Boeing 787-9", distanceKm: 8_270)
        var backDep = hnd; backDep.scheduled = at(7, 17, 0); backDep.terminal = "3"; backDep.gate = "112"
        var backArr = sfo; backArr.scheduled = at(7, 10, 10, pacific); backArr.terminal = "I"
        let inbound = FlightSegment(flightNumber: "XX 102", airlineName: "Sample Air", airlineCode: "XX",
                                    departure: backDep, arrival: backArr, status: "Scheduled",
                                    aircraftModel: "Boeing 787-9", distanceKm: 8_270)
        for f in [outbound, inbound] { f.isSample = true; f.trip = trip; context.insert(f) }

        let hotel = Stay(name: "Park Hyatt Tokyo", address: "3-7-1-2 Nishishinjuku, Shinjuku, Tokyo",
                         coordinate: .init(latitude: 35.6856, longitude: 139.6907),
                         checkIn: at(0, 17, 30), checkOut: at(7, 11, 0))
        hotel.trip = trip
        context.insert(hotel)

        let items: [(String, DiscoverCategory, Int?, Int, Int, Int, Double, Double, String)] = [
            ("Tsukiji Outer Market", .food, 1, 8, 30, 90, 35.6654, 139.7707, "Breakfast sushi and tamagoyaki"),
            ("teamLab Planets", .culture, 1, 11, 0, 120, 35.6491, 139.7898, "Tickets booked — bring shorts for the water rooms"),
            ("Sensō-ji", .sights, 1, 15, 0, 90, 35.7148, 139.7967, ""),
            ("Omoide Yokocho", .food, 1, 19, 0, 90, 35.6930, 139.6996, "Yakitori alley by Shinjuku Station"),
            ("Meiji Jingu", .sights, 2, 9, 0, 90, 35.6764, 139.6993, ""),
            ("Takeshita Street", .shopping, 2, 11, 0, 75, 35.6716, 139.7031, ""),
            ("Shibuya Sky", .sights, 2, 17, 0, 90, 35.6585, 139.7022, "Sunset slot"),
            ("Golden Gai", .nightlife, 2, 20, 30, 120, 35.6939, 139.7046, ""),
            ("Shinjuku Gyoen", .outdoors, 3, 10, 0, 120, 35.6852, 139.7100, ""),
            ("Ghibli Museum", .culture, nil, 0, 0, 120, 35.6962, 139.5704, "Tickets go on sale on the 10th"),
            ("Day trip to Kamakura", .outdoors, nil, 0, 0, 480, 35.3192, 139.5467, ""),
        ]
        for (title, cat, day, h, m, dur, lat, lon, notes) in items {
            let item = PlanItem(title: title, category: cat, start: at(day ?? 0, h, m), durationMinutes: dur)
            item.isScheduled = day != nil
            item.latitude = lat
            item.longitude = lon
            item.notes = notes
            item.trip = trip
            context.insert(item)
        }
        try? context.save()
        return trip
    }
}
