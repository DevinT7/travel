#if os(iOS)
import ActivityKit
import Foundation

/// A flight on the Lock Screen and in the Dynamic Island. Shared by the app (which starts and
/// updates it) and the widget extension (which draws it). Keep it small: the whole thing must
/// encode to under 4 KB.
struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case scheduled, inAir, landed, canceled }

        /// Best-known times (revised if the airline published new ones).
        var departs: Date
        var arrives: Date
        var phase: Phase
        var delayMinutes: Int
        var terminal: String?
        var gate: String?
        var arrivalTerminal: String?
        var baggageBelt: String?
        var updatedAt: Date
    }

    var flightID: UUID
    var flightNumber: String
    var airlineName: String
    var fromCode: String
    var toCode: String
    var fromCity: String
    var toCity: String
    var fromTimeZone: String
    var toTimeZone: String
}
#endif
