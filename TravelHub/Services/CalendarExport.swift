import Foundation
import EventKit
import CoreLocation

/// Adds a trip's flights, stays and scheduled plans to the user's calendar.
///
/// Uses write-only access: TravelHub can add events but never sees what else is in the calendar.
/// Because it can't read events back, it remembers which items it already added (on this device)
/// so running it again only adds what's new.
@MainActor
enum CalendarExport {
    enum Failure: LocalizedError {
        case denied
        var errorDescription: String? {
            "TravelHub doesn't have permission to add events. Turn it on in Settings → Apps → TravelHub → Calendars."
        }
    }

    private static let store = EKEventStore()
    private static let defaultsKey = "calendarExportedItemIDs"

    /// Returns how many new events were added.
    @discardableResult
    static func add(_ trip: Trip) async throws -> Int {
        guard try await store.requestWriteOnlyAccessToEvents() else { throw Failure.denied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw Failure.denied }

        var exported = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        var added = 0

        func save(id: UUID, configure: (EKEvent) -> Void) throws {
            guard !exported.contains(id.uuidString) else { return }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            configure(event)
            try store.save(event, span: .thisEvent, commit: false)
            exported.insert(id.uuidString)
            added += 1
        }

        for flight in trip.sortedFlights {
            try save(id: flight.id) { e in
                e.title = "✈️ \(flight.flightNumber) \(flight.departure.iata) → \(flight.arrival.iata)"
                e.startDate = flight.departure.best
                e.endDate = max(flight.arrival.best, flight.departure.best.addingTimeInterval(1800))
                e.timeZone = flight.departure.timeZone
                e.location = flight.departure.airportName
                var notes = ["\(flight.airlineName) \(flight.flightNumber)",
                             "\(flight.departure.airportName) → \(flight.arrival.airportName)"]
                if let t = flight.departure.terminal { notes.append("Terminal \(t)") }
                if let g = flight.departure.gate { notes.append("Gate \(g)") }
                e.notes = notes.joined(separator: "\n")
                e.addAlarm(EKAlarm(relativeOffset: -3 * 3600))
            }
        }

        for stay in trip.sortedStays {
            try save(id: stay.id) { e in
                e.title = "🛏 \(stay.name)"
                e.startDate = stay.checkIn
                e.endDate = max(stay.checkOut, stay.checkIn.addingTimeInterval(3600))
                e.timeZone = trip.timeZone
                e.location = stay.address.isEmpty ? stay.name : "\(stay.name), \(stay.address)"
                e.notes = [stay.confirmationNumber.isEmpty ? nil : "Confirmation: \(stay.confirmationNumber)",
                           stay.notes.isEmpty ? nil : stay.notes].compactMap { $0 }.joined(separator: "\n")
            }
        }

        for item in (trip.planItems ?? []).filter(\.isScheduled).sorted(by: { $0.start < $1.start }) {
            try save(id: item.id) { e in
                e.title = item.title
                e.startDate = item.start
                e.endDate = item.end
                e.timeZone = trip.timeZone
                e.location = item.address.isEmpty ? nil : item.address
                e.notes = item.notes.isEmpty ? nil : item.notes
                e.url = item.externalURL
                if let c = item.coordinate {
                    let location = EKStructuredLocation(title: item.address.isEmpty ? item.title : item.address)
                    location.geoLocation = CLLocation(latitude: c.latitude, longitude: c.longitude)
                    e.structuredLocation = location
                }
            }
        }

        if added > 0 { try store.commit() }
        UserDefaults.standard.set(Array(exported), forKey: defaultsKey)
        return added
    }
}
