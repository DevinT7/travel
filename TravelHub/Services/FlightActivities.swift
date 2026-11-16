import Foundation
import SwiftData
#if os(iOS)
import ActivityKit
#endif

/// Starts, updates and ends flight Live Activities (Lock Screen + Dynamic Island). iPhone only;
/// on Mac every call is a no-op.
///
/// There's no push server, so the app updates them itself: whenever flights are refreshed and
/// whenever the app comes to the foreground. Between updates the countdowns and progress bar run
/// on the system clock.
@MainActor
enum FlightActivities {
    /// Flights leaving within this window start tracking on their own when the app is opened.
    static let autoStartWindow: TimeInterval = 4 * 3600
    private static let autoStartOffKey = "liveActivityAutoStartOff"

    static var isSupported: Bool {
        #if os(iOS)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    static func isTracking(_ flight: FlightSegment) -> Bool {
        #if os(iOS)
        return activity(for: flight) != nil
        #else
        return false
        #endif
    }

    /// Worth offering "Track Live" for: not landed more than half an hour ago, and not too far off
    /// (a Live Activity lasts at most about 12 hours).
    static func canTrack(_ flight: FlightSegment) -> Bool {
        isSupported && flight.arrival.best > .now.addingTimeInterval(-30 * 60)
            && flight.departure.best < .now.addingTimeInterval(24 * 3600)
    }

    static func start(_ flight: FlightSegment) {
        #if os(iOS)
        guard isSupported, activity(for: flight) == nil else { return }
        UserDefaults.standard.removeObject(forKey: autoStartOffKey + flight.id.uuidString)
        let attributes = FlightActivityAttributes(
            flightID: flight.id, flightNumber: flight.flightNumber, airlineName: flight.airlineName,
            fromCode: flight.departure.iata, toCode: flight.arrival.iata,
            fromCity: flight.departure.city, toCity: flight.arrival.city,
            fromTimeZone: flight.departure.timeZoneIdentifier, toTimeZone: flight.arrival.timeZoneIdentifier)
        _ = try? Activity.request(attributes: attributes, content: content(for: flight), pushType: nil)
        #endif
    }

    static func stop(_ flight: FlightSegment) async {
        #if os(iOS)
        // Don't bring it straight back the next time the app opens.
        UserDefaults.standard.set(true, forKey: autoStartOffKey + flight.id.uuidString)
        await activity(for: flight)?.end(nil, dismissalPolicy: .immediate)
        #endif
    }

    /// Ends the Live Activity of any flight that's been deleted, on its own or with its trip.
    /// Runs after every save; local only, no status fetch.
    static func endRemoved() async {
        #if os(iOS)
        let running = Activity<FlightActivityAttributes>.activities
        guard !running.isEmpty else { return }
        let flights = (try? AppData.container.mainContext.fetch(FetchDescriptor<FlightSegment>())) ?? []
        let saved = Set(flights.filter { $0.trip != nil && !$0.isDeleted }.map(\.id))
        for activity in running where !saved.contains(activity.attributes.flightID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    /// Syncs against every flight in the database.
    static func syncAll() async {
        #if os(iOS)
        let flights = ((try? AppData.container.mainContext.fetch(FetchDescriptor<FlightSegment>())) ?? []).filter { $0.trip != nil }
        await sync(with: flights)
        #endif
    }

    /// Brings every running activity up to date with its flight, ends finished or removed ones, and
    /// starts tracking flights that leave soon.
    static func sync(with flights: [FlightSegment]) async {
        #if os(iOS)
        guard isSupported else { return }
        let byID = Dictionary(flights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for activity in Activity<FlightActivityAttributes>.activities {
            guard let flight = byID[activity.attributes.flightID] else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let content = content(for: flight)
            if flight.arrival.best < .now.addingTimeInterval(-45 * 60) || content.state.phase == .canceled && flight.departure.best < .now {
                await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(30 * 60)))
            } else if activity.content.state != content.state {
                await activity.update(content)
            }
        }
        for flight in flights where shouldAutoStart(flight) { start(flight) }
        #endif
    }

    #if os(iOS)
    private static func shouldAutoStart(_ flight: FlightSegment) -> Bool {
        let untilDeparture = flight.departure.best.timeIntervalSinceNow
        return untilDeparture > -30 * 60 && untilDeparture < autoStartWindow
            && !UserDefaults.standard.bool(forKey: autoStartOffKey + flight.id.uuidString)
            && activity(for: flight) == nil
    }

    private static func activity(for flight: FlightSegment) -> Activity<FlightActivityAttributes>? {
        Activity<FlightActivityAttributes>.activities.first { $0.attributes.flightID == flight.id }
    }

    private static func content(for f: FlightSegment) -> ActivityContent<FlightActivityAttributes.ContentState> {
        let now = Date.now
        let status = f.status.lowercased()
        let phase: FlightActivityAttributes.ContentState.Phase =
            status.contains("cancel") ? .canceled
            : (status.contains("arrived") || status.contains("landed") || now >= f.arrival.best) ? .landed
            : (status.contains("departed") || status.contains("enroute") || status.contains("en route") || now >= f.departure.best) ? .inAir
            : .scheduled
        let state = FlightActivityAttributes.ContentState(
            departs: f.departure.best, arrives: f.arrival.best, phase: phase,
            delayMinutes: max(f.departure.delayMinutes, 0),
            terminal: f.departure.terminal, gate: f.departure.gate,
            arrivalTerminal: f.arrival.terminal, baggageBelt: f.arrival.baggageBelt, updatedAt: f.lastUpdated)
        // The widget moves to the next phase on its own once this passes.
        let stale: Date? = switch phase {
        case .scheduled: f.departure.best
        case .inAir: f.arrival.best
        case .landed, .canceled: nil
        }
        // Rank closer flights higher when more than one is running.
        let relevance = max(0, 100 - abs(f.departure.best.timeIntervalSinceNow) / 3600)
        return ActivityContent(state: state, staleDate: stale, relevanceScore: relevance)
    }
    #endif
}
