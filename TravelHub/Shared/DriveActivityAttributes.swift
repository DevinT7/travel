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
    }

    var legID: UUID
    var fromName: String
    var toName: String
    var toAddress: String
    var timeZoneIdentifier: String
}
#endif
