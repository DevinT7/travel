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
        if DriveTracker.shared.isTracking(leg.id) { DriveTracker.shared.stop(endActivity: false) }
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

        await endRemoved()
        let byID = Dictionary(legs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for activity in Activity<DriveActivityAttributes>.activities {
            // A drive being followed live is kept up to date by DriveTracker.
            if DriveTracker.shared.isTracking(activity.attributes.legID) { continue }
            guard let leg = byID[activity.attributes.legID] else { continue }
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

    /// Ends the Live Activity (and live ETA) of any drive that's been deleted, on its own or
    /// with its trip. Runs after every save, so it's cheap: one fetch of drive ids.
    static func endRemoved() async {
        #if os(iOS)
        let running = Activity<DriveActivityAttributes>.activities
        guard !running.isEmpty else { return }
        let context = AppData.container.mainContext
        let legs = (try? context.fetch(FetchDescriptor<DriveLeg>())) ?? []
        let saved = Set(legs.filter { $0.trip != nil && !$0.isDeleted }.map(\.id))
        let tracker = DriveTracker.shared
        for activity in running where !saved.contains(activity.attributes.legID) {
            let id = activity.attributes.legID
            // A drive to a plan stop has no saved drive behind it; leave it running.
            if let target = tracker.target, target.id == id, !target.isSavedDrive { continue }
            if tracker.isTracking(id) { tracker.stop(endActivity: false) }
            UserDefaults.standard.set(true, forKey: autoStartOffKey + id.uuidString)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    // MARK: Live ETA

    /// Starts (or takes over) the activity for a drive that's being followed live.
    static func startLive(_ target: DriveTracker.Target) {
        #if os(iOS)
        guard isSupported else { return }
        UserDefaults.standard.removeObject(forKey: autoStartOffKey + target.id.uuidString)
        if let existing = Activity<DriveActivityAttributes>.activities.first(where: { $0.attributes.legID == target.id }) {
            stopTrackingWhenGone(existing)
            return
        }
        let attributes = DriveActivityAttributes(
            legID: target.id, fromName: target.fromName, toName: target.destination.name,
            toAddress: target.destination.address, timeZoneIdentifier: target.timeZoneIdentifier)
        let state = DriveActivityAttributes.ContentState(
            leaveAt: target.leaveAt, arriveAt: target.plannedArrival ?? target.leaveAt.addingTimeInterval(1800),
            minutes: 0, distanceText: "", updatedAt: .now, plannedArrival: target.plannedArrival)
        if let activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil, relevanceScore: 100),
                                                pushType: nil) {
            stopTrackingWhenGone(activity)
        }
        #endif
    }

    #if os(iOS)
    /// Swiping the drive off the Lock Screen (or iOS ending it) also stops following the phone's
    /// location, so the blue location arrow doesn't linger with nothing to show for it.
    private static func stopTrackingWhenGone(_ activity: Activity<DriveActivityAttributes>) {
        let id = activity.attributes.legID
        Task { @MainActor in
            for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
                if DriveTracker.shared.isTracking(id) { DriveTracker.shared.stop(endActivity: false) }
                return
            }
        }
    }
    #endif

    static func updateLive(_ target: DriveTracker.Target, _ live: DriveTracker.Live) async {
        #if os(iOS)
        guard let activity = Activity<DriveActivityAttributes>.activities.first(where: { $0.attributes.legID == target.id }) else { return }
        var state = activity.content.state
        state.etaAt = live.eta
        state.arriveAt = live.eta
        state.leaveAt = target.startedAt
        state.remainingMinutes = live.remainingMinutes
        state.remainingText = DriveService.distanceText(live.remainingMeters)
        state.progress = live.progress
        state.plannedArrival = target.plannedArrival
        state.arrived = live.arrived
        if state.minutes == 0 { state.minutes = live.remainingMinutes }
        if state.distanceText.isEmpty { state.distanceText = DriveService.distanceText(live.remainingMeters) }
        state.updatedAt = live.updatedAt
        // If updates stop (phone off, out of signal), the widget greys the ETA out a few minutes after it.
        await activity.update(ActivityContent(state: state, staleDate: live.eta.addingTimeInterval(10 * 60), relevanceScore: 100))
        #endif
    }

    static func endLive(_ id: UUID, arrived: Bool) async {
        #if os(iOS)
        UserDefaults.standard.set(true, forKey: autoStartOffKey + id.uuidString)
        for activity in Activity<DriveActivityAttributes>.activities where activity.attributes.legID == id {
            // "You've arrived" stays up for a few minutes, then clears.
            await activity.end(nil, dismissalPolicy: arrived ? .after(.now.addingTimeInterval(5 * 60)) : .immediate)
        }
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
