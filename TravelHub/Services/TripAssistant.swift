import Foundation
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Intelligence for trips: answers questions about your itinerary and turns real
/// nearby places (from Apple Maps / Wikipedia) into short recommendations. Runs on the device with
/// the system model on iOS 26 / macOS 26 with Apple Intelligence on; otherwise callers fall back to
/// plain lists.
@MainActor
enum TripAssistant {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Answers a free-form question ("When do I land?", "What should I do Saturday night?") using the
    /// trip's own data, and a place search for recommendations.
    static func answer(_ question: String, about trip: Trip) async throws -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let tool = NearbyPlacesTool(latitude: trip.destinationLatitude, longitude: trip.destinationLongitude,
                                        destination: trip.destinationName)
            let session = LanguageModelSession(tools: [tool], instructions: """
                You are TravelHub, a friendly travel assistant answering out loud through Siri. \
                Answer in one to three short sentences. Use only the trip details given and places \
                returned by the findPlaces tool; never invent flights, times, bookings or place names. \
                Times are already in the right local time zone. If the answer isn't in the trip details, say so.
                """)
            let prompt = "Trip details:\n\(summary(of: trip))\n\nQuestion: \(question)"
            return try await session.respond(to: prompt).content
        }
        #endif
        return nil
    }

    /// One or two spoken sentences recommending a few of `places`, or nil without Apple Intelligence.
    static func recommend(_ places: [DiscoverItem], kind: String, trip: Trip) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), SystemLanguageModel.default.isAvailable, !places.isEmpty {
            let list = places.prefix(10).map { p in
                [p.title, p.subtitle, p.summary.map { String($0.prefix(160)) }].compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: " — ")
            }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: """
                You recommend things to do on a trip, spoken by Siri. Pick two or three places ONLY from \
                the list given, and say in a few words why each is worth it. Two sentences at most, no lists.
                """)
            let prompt = "Trip to \(trip.destinationName), \(trip.days.count) days. They asked for \(kind).\nPlaces:\n\(list)"
            return try? await session.respond(to: prompt).content
        }
        #endif
        return nil
    }

    /// A plain-text version of the trip for the model, with times in each place's own zone.
    static func summary(of trip: Trip) -> String {
        let tz = trip.timeZone
        func when(_ d: Date, _ zone: TimeZone) -> String {
            d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone).weekday(.wide))
        }
        var lines = [
            "Trip: \(trip.displayName) to \(trip.destinationName)",
            "Dates: \(trip.startDate.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: tz))) to \(trip.endDate.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: tz)))",
            "Right now it is \(when(.now, tz)) in \(trip.destinationName).",
        ]
        let flights = trip.sortedFlights
        if !flights.isEmpty {
            lines.append("Flights:")
            for f in flights {
                var line = "- \(f.flightNumber) (\(f.airlineName)) from \(f.departure.city.isEmpty ? f.departure.iata : f.departure.city) (\(f.departure.iata)) at \(when(f.departure.best, f.departure.timeZone)) local time, landing in \(f.arrival.city.isEmpty ? f.arrival.iata : f.arrival.city) (\(f.arrival.iata)) at \(when(f.arrival.best, f.arrival.timeZone)) local time."
                if let t = f.departure.terminal { line += " Departs terminal \(t)." }
                if let g = f.departure.gate { line += " Gate \(g)." }
                if f.departure.delayMinutes > 0 { line += " Delayed \(f.departure.delayMinutes) minutes." }
                lines.append(line)
            }
        }
        for s in trip.sortedStays {
            lines.append("Staying at \(s.name)\(s.address.isEmpty ? "" : ", \(s.address)"): check in \(when(s.checkIn, tz)), check out \(when(s.checkOut, tz)).")
        }
        let plans = (trip.planItems ?? []).sorted { $0.start < $1.start }
        let scheduled = plans.filter(\.isScheduled)
        if !scheduled.isEmpty {
            lines.append("Plans:")
            for p in scheduled { lines.append("- \(when(p.start, tz)): \(p.title)\(p.address.isEmpty ? "" : " at \(p.address)")") }
        }
        let ideas = plans.filter { !$0.isScheduled }
        if !ideas.isEmpty { lines.append("Saved ideas (not scheduled): \(ideas.map(\.title).joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
/// Lets the model look up real places around the destination instead of making them up.
@available(iOS 26.0, macOS 26.0, *)
struct NearbyPlacesTool: Tool {
    let latitude: Double
    let longitude: Double
    let destination: String

    let name = "findPlaces"
    let description = "Finds real restaurants, sights, bars, cafés, museums, parks and shops near the trip's destination."

    @Generable
    struct Arguments {
        @Guide(description: "What to look for, for example 'ramen', 'museum', 'rooftop bar' or 'park'")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let items = try await MapKitPlacesProvider().search(query: arguments.query, near: center)
        guard !items.isEmpty else { return "No places found for \(arguments.query) near \(destination)." }
        return items.prefix(8).map { "\($0.title) — \($0.subtitle)\($0.address.isEmpty ? "" : ", \($0.address)")" }
            .joined(separator: "\n")
    }
}
#endif
