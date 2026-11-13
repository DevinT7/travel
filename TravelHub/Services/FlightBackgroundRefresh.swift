import Foundation
import SwiftData
import os
#if os(iOS)
import BackgroundTasks
#endif

/// Keeps flight status (and the Lock Screen / Dynamic Island) current while TravelHub is closed.
///
/// iOS wakes the app now and then for a background app refresh. It decides exactly when, based on
/// how often you use the app, battery and network, so updates usually arrive every 15 to 60
/// minutes, never on a fixed schedule. Each wake-up is one AeroDataBox request per flight that's
/// about to leave, in the air, or just landed, so it stays well inside the free plan.
/// iPhone only; on Mac it does nothing.
@MainActor
enum FlightBackgroundRefresh {
    static let taskID = "com.devint.travelhub.flight-refresh"
    /// Don't ask for a wake-up more often than this.
    static let interval: TimeInterval = 15 * 60
    private static let log = Logger(subsystem: "com.devint.travelhub", category: "BackgroundRefresh")

    /// Asks iOS for the next wake-up, if any flight needs watching soon. Called when the app goes
    /// to the background and at the end of every background run.
    static func schedule() {
        #if os(iOS)
        guard APIKeys.aeroDataBox != nil, let date = nextRefreshDate() else {
            #if DEBUG
            print("[BackgroundRefresh] nothing to watch (key set: \(APIKeys.aeroDataBox != nil))")
            #endif
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
            log.info("Scheduled flight refresh for \(date, privacy: .public)")
            #if DEBUG
            print("[BackgroundRefresh] scheduled for \(date)")
            #endif
        } catch {
            log.error("Couldn't schedule flight refresh: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[BackgroundRefresh] couldn't schedule: \(error)")
            #endif
        }
        #endif
    }

    /// The background run: refresh flights that matter right now, then update their Live Activities.
    static func run() async {
        defer { schedule() }
        guard APIKeys.aeroDataBox != nil else { return }
        let context = AppData.container.mainContext
        // Only flights that still belong to a trip.
        let flights = ((try? context.fetch(FetchDescriptor<FlightSegment>())) ?? []).filter { $0.trip != nil }
        let due = flights.filter { FlightProgress.isInLiveWindow($0) && Date.now.timeIntervalSince($0.lastUpdated) > 5 * 60 }
        log.info("Background refresh: \(due.count) of \(flights.count) flights due")
        for flight in due {
            guard !Task.isCancelled else { break }
            do {
                try await FlightService().refresh(flight)
                log.info("Refreshed \(flight.flightNumber, privacy: .public): \(flight.status, privacy: .public)")
            } catch {
                log.error("Refresh failed for \(flight.flightNumber, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        try? context.save()
        await FlightActivities.sync(with: flights)
    }

    /// Every 15 minutes while a flight is in its live window; otherwise when the next one enters it
    /// (two hours before departure), as long as that's within the next day.
    private static func nextRefreshDate() -> Date? {
        let flights = ((try? AppData.container.mainContext.fetch(FetchDescriptor<FlightSegment>())) ?? []).filter { $0.trip != nil }
        let now = Date.now
        if flights.contains(where: { FlightProgress.isInLiveWindow($0, at: now) }) {
            return now.addingTimeInterval(interval)
        }
        let nextWindow = flights.map { $0.departure.best.addingTimeInterval(-2 * 3600) }
            .filter { $0 > now }.min()
        guard let nextWindow, nextWindow < now.addingTimeInterval(24 * 3600) else { return nil }
        return max(nextWindow, now.addingTimeInterval(interval))
    }
}
