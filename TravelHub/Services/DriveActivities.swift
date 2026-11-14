import Foundation
import SwiftData
#if os(iOS)
import ActivityKit
#endif

/// Starts, updates and ends drive Live Activities. They show on the Lock Screen, in the Dynamic
/// Island and, on iOS 26, on the CarPlay dashboard. iPhone only; on Mac every call is a no-op.
@MainActor
enum DriveActivities {
    /// Drives leaving within this window start on their own when the app is opened.
    static let autoStartWindow: TimeInterval = 2 * 3600
    private static let autoStartOffKey = "driveActivityAutoStartOff"

    static var isSupported: Bool {
        #if os(iOS)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    static func isTracking(_ leg: DriveLeg) -> Bool {
        #if os(iOS)
        return activity(for: leg) != nil
        #else
        return false
        #endif
    }

    /// Not finished, and leaving within a day (a Live Activity lasts at most about 12 hours).
    static func canTrack(_ leg: DriveLeg) -> Bool {
        isSupported && leg.to.isSet && leg.arrival > .now.addingTimeInterval(-15 * 60)
            && leg.departure < .now.addingTimeInterval(12 * 3600)
    }

    static func start(_ leg: DriveLeg) {
        #if os(iOS)
        guard isSupported, activity(for: leg) == nil else { return }
        UserDefaults.standard.removeObject(forKey: autoStartOffKey + leg.id.uuidString)
        let attributes = DriveActivityAttributes(
            legID: leg.id, fromName: leg.from.name, toName: leg.to.name, toAddress: leg.to.address,
            timeZoneIdentifier: leg.trip?.timeZone.identifier ?? TimeZone.current.identifier)
        _ = try? Activity.request(attributes: attributes, content: content(for: leg), pushType: nil)
        #endif
    }

    static func stop(_ leg: DriveLeg) async {
        #if os(iOS)
        UserDefaults.standard.set(true, forKey: autoStartOffKey + leg.id.uuidString)
        await activity(for: leg)?.end(nil, dismissalPolicy: .immediate)
        #endif
    }

    /// Re-checks traffic for drives about to start, updates running activities, ends finished or
    /// deleted ones and starts drives leaving soon.
    static func syncAll() async {
        #if os(iOS)
        guard isSupported else { return }
        let context = AppData.container.mainContext
        let legs = ((try? context.fetch(FetchDescriptor<DriveLeg>())) ?? []).filter { $0.trip != nil }
        for leg in legs where abs(leg.departure.timeIntervalSinceNow) < 3 * 3600
            && Date.now.timeIntervalSince(leg.routeUpdatedAt ?? .distantPast) > 10 * 60 {
            await DriveService.shared.refresh(leg)
        }
        try? context.save()

        let byID = Dictionary(legs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for activity in Activity<DriveActivityAttributes>.activities {
            guard let leg = byID[activity.attributes.legID] else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let content = content(for: leg)
            if leg.arrival < .now.addingTimeInterval(-15 * 60) {
                await activity.end(content, dismissalPolicy: .immediate)
            } else if activity.content.state != content.state {
                await activity.update(content)
            }
        }
        for leg in legs where shouldAutoStart(leg) { start(leg) }
        #endif
    }

    #if os(iOS)
    private static func shouldAutoStart(_ leg: DriveLeg) -> Bool {
        let untilDeparture = leg.departure.timeIntervalSinceNow
        return untilDeparture > -15 * 60 && untilDeparture < autoStartWindow && leg.to.isSet
            && !UserDefaults.standard.bool(forKey: autoStartOffKey + leg.id.uuidString)
            && activity(for: leg) == nil
    }

    private static func activity(for leg: DriveLeg) -> Activity<DriveActivityAttributes>? {
        Activity<DriveActivityAttributes>.activities.first { $0.attributes.legID == leg.id }
    }

    private static func content(for leg: DriveLeg) -> ActivityContent<DriveActivityAttributes.ContentState> {
        let state = DriveActivityAttributes.ContentState(
            leaveAt: leg.departure, arriveAt: leg.arrival, minutes: leg.travelMinutes,
            distanceText: DriveService.distanceText(leg.distanceMeters), updatedAt: leg.routeUpdatedAt ?? .now)
        let relevance = max(0, 100 - abs(leg.departure.timeIntervalSinceNow) / 3600)
        // The widget moves from "leave in" to "on the road" to "arrived" on its own at these times.
        let stale = leg.departure > .now ? leg.departure : leg.arrival
        return ActivityContent(state: state, staleDate: stale, relevanceScore: relevance)
    }
    #endif
}
