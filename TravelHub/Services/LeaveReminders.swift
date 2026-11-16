import Foundation
import SwiftData
import CoreLocation
import UserNotifications

extension Trip {
    /// Where the traveler will be just before `start`: the previous stop that day, the end of a drive
    /// that arrives before it, or the hotel.
    func origin(before start: Date, excluding: UUID? = nil) -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let cal = calendar
        let earlier = (planItems ?? [])
            .filter { $0.isScheduled && $0.id != excluding && $0.coordinate != nil && $0.start < start && cal.isDate($0.start, inSameDayAs: start) }
            .max { $0.start < $1.start }
        let drive = sortedDrives.filter { $0.to.isSet && $0.arrival <= start && cal.isDate($0.arrival, inSameDayAs: start) }.last
        if let drive, drive.arrival > (earlier?.end ?? .distantPast) { return (drive.to.name, drive.to.coordinate) }
        if let earlier, let c = earlier.coordinate { return (earlier.title, c) }
        if let stay = stay(on: start) { return (stay.name, stay.coordinate) }
        return nil
    }
}

/// "Leave in 5 min for Dinner at Ichiran": a notification before each plan stop, timed from the
/// travel time between the previous stop (or the hotel) and that stop. Rebuilt whenever the plan
/// changes or the app opens, for the next three days.
@MainActor
enum LeaveReminders {
    static let enabledKey = "leaveReminders.enabled"
    /// Plan shows a one-time offer to turn these on; set once it's been answered.
    static let offerAnsweredKey = "leaveReminders.offerAnswered"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private static let prefix = "leave-"
    private static let headsUp: TimeInterval = 5 * 60
    private static var pending: Task<Void, Never>?

    /// Asks for notification permission the first time. Returns whether alerts are now on.
    @discardableResult
    static func turnOn() async -> Bool {
        UserDefaults.standard.set(true, forKey: offerAnsweredKey)
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        await reschedule()
        return granted
    }

    static func turnOff() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.set(true, forKey: offerAnsweredKey)
        Task { await reschedule() }
    }

    /// Coalesces bursts of saves into one rebuild.
    static func scheduleSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard isOn else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let now = Date.now
        let horizon = now.addingTimeInterval(3 * 86400)
        let trips = (try? AppData.container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
        let upcoming = trips
            .flatMap { trip in
                (trip.planItems ?? [])
                    .filter { $0.isScheduled && $0.coordinate != nil && $0.start > now && $0.start < horizon }
                    .map { (trip, $0) }
            }
            .sorted { $0.1.start < $1.1.start }
            .prefix(40)  // iOS keeps at most 64 pending notifications per app

        for (trip, item) in upcoming {
            guard let destination = item.coordinate,
                  let origin = trip.origin(before: item.start, excluding: item.id),
                  let estimate = await DirectionsService.shared.estimate(from: origin.coordinate, to: destination, mode: trip.gettingAround),
                  estimate.minutes >= 5
            else { continue }
            let leaveBy = item.start.addingTimeInterval(-TimeInterval(estimate.minutes * 60))
            let fire = leaveBy.addingTimeInterval(-headsUp)
            guard fire.timeIntervalSince(now) > 30 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Leave in 5 min for \(item.title)"
            content.body = "\(estimate.text) from \(origin.name) · arrive by \(item.start.time(in: trip.timeZone))"
            if let warning = item.closedWarning { content.body += "\n\(warning)" }
            content.sound = .default
            content.threadIdentifier = trip.id.uuidString
            content.userInfo = ["tripID": trip.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + item.id.uuidString, content: content, trigger: trigger))
        }
    }
}

/// Shows reminders while the app is open, and opens the trip's plan when one is tapped.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Set by the app once it's ready to navigate. A tap that launched the app waits here until then.
    @MainActor var openTrip: ((UUID) -> Void)? {
        didSet { if let id = waiting, let openTrip { waiting = nil; openTrip(id) } }
    }
    @MainActor private var waiting: UUID?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["tripID"] as? String, let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            if let openTrip { openTrip(id) } else { waiting = id }
        }
    }
}
