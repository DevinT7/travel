#if DEBUG && os(iOS)
import ActivityKit
import SwiftData
import Foundation

/// Debug-only: launched with `-DemoDrive YES`, replaces a "Demo Road Trip" with a driving day in
/// Los Angeles (a hotel, two stops and a drive leaving soon) and starts the drive's Live Activity,
/// so the Plan, the Lock Screen and CarPlay can be checked in the simulator. `-DemoDriveLive YES`
/// also starts the live ETA.
@MainActor
enum DebugDriveDemo {
    static func runIfRequested(context: ModelContext) async -> Trip? {
        guard UserDefaults.standard.bool(forKey: "DemoDrive") else { return nil }
        for activity in Activity<DriveActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        let old = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.name == "Demo Road Trip" }))) ?? []
        old.forEach(context.delete)

        let now = Date.now
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = la
        let trip = Trip(name: "Demo Road Trip", destinationName: "Los Angeles", coordinate: .init(latitude: 34.0522, longitude: -118.2437),
                        countryCode: "US", timeZoneIdentifier: la.identifier,
                        startDate: cal.startOfDay(for: now), endDate: now.addingTimeInterval(3 * 86400))
        trip.gettingAround = .drive
        context.insert(trip)

        let stay = Stay(name: "Shore Hotel", address: "1515 Ocean Ave, Santa Monica",
                        coordinate: .init(latitude: 34.0138, longitude: -118.4952),
                        checkIn: now.addingTimeInterval(-86400), checkOut: now.addingTimeInterval(2 * 86400))
        context.insert(stay); stay.trip = trip

        func round(_ d: Date) -> Date { Date(timeIntervalSinceReferenceDate: (d.timeIntervalSinceReferenceDate / 900).rounded() * 900) }
        let getty = PlanItem(title: "Getty Center", category: .sights, start: round(now.addingTimeInterval(2 * 3600)), durationMinutes: 120)
        getty.latitude = 34.0780; getty.longitude = -118.4741; getty.address = "1200 Getty Center Dr"
        let griffith = PlanItem(title: "Griffith Observatory", category: .sights, start: round(now.addingTimeInterval(5 * 3600)), durationMinutes: 90)
        griffith.latitude = 34.1184; griffith.longitude = -118.3004; griffith.address = "2800 E Observatory Rd"
        for p in [getty, griffith] { context.insert(p); p.trip = trip }

        let drive = DriveLeg(from: DrivePlace(name: "Shore Hotel", address: stay.address, coordinate: stay.coordinate),
                             to: DrivePlace(name: "Malibu Pier", address: "23000 Pacific Coast Hwy, Malibu",
                                            coordinate: .init(latitude: 34.0378, longitude: -118.6775)),
                             departure: round(now.addingTimeInterval(30 * 60 + Double(UserDefaults.standard.integer(forKey: "DemoDriveDays")) * 86400)))
        drive.vehicle = "Rental car"
        context.insert(drive); drive.trip = trip
        await DriveService.shared.refresh(drive)
        try? context.save()
        UserDefaults.standard.set(trip.id.uuidString, forKey: "selectedTripID")
        DriveActivities.start(drive)
        // `-DemoDriveLive YES` also follows the drive live (pair with `simctl location start`).
        if UserDefaults.standard.bool(forKey: "DemoDriveLive") {
            drive.departure = round(now.addingTimeInterval(-60))
            try? context.save()
            DriveTracker.shared.start(drive)
            // `-DemoDriveDismiss YES` ends the activity from outside the tracker after a few
            // seconds, as a Lock Screen swipe would; the live ETA should stop with it.
            if UserDefaults.standard.bool(forKey: "DemoDriveDismiss") {
                try? await Task.sleep(for: .seconds(8))
                for activity in Activity<DriveActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
                try? await Task.sleep(for: .seconds(1))
                print("DemoDriveDismiss: tracker still running =", DriveTracker.shared.target != nil)
            }
        }
        return trip
    }
}
#endif
