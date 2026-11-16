#if os(iOS)
import ActivityKit
import Foundation

/// The next drive on the Lock Screen, in the Dynamic Island and on the CarPlay dashboard
/// (iOS 26 shows Live Activities in CarPlay through the `.small` family). Shared by the app and the
/// widget extension.
struct DriveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var leaveAt: Date
        var arriveAt: Date
        var minutes: Int
        /// Already formatted ("18 km", "11 mi") so the widget doesn't need the user's unit settings.
        var distanceText: String
        var updatedAt: Date

        // Live ETA while the drive is being followed ("Start Drive"). All optional so activities
        // started before live tracking existed still decode.
        /// Expected arrival from the car's current position, with traffic.
        var etaAt: Date?
        var remainingMinutes: Int?
        var remainingText: String?
        /// 0…1 by distance covered.
        var progress: Double?
        /// When the plan expects them there; the widget compares it with `etaAt`.
        var plannedArrival: Date?
        var arrived: Bool?

        var isLive: Bool { etaAt != nil }

        /// Positive when the live ETA is later than planned.
        var minutesLate: Int {
            guard let etaAt, let plannedArrival else { return 0 }
            return Int((etaAt.timeIntervalSince(plannedArrival) / 60).rounded())
        }
    }

    var legID: UUID
    var fromName: String
    var toName: String
    var toAddress: String
    var timeZoneIdentifier: String
}
#endif
