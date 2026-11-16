import Foundation
import MapKit
import Observation

/// Live ETA for the drive in progress.
///
/// Apple Maps doesn't share its navigation with other apps, so "Start Drive" does two things at
/// once: it opens Maps for turn-by-turn, and TravelHub follows the phone's location and asks
/// Apple Maps' routing service (with live traffic) for an ETA about once a minute. That ETA goes
/// to the drive's Live Activity, which shows next to Maps on the Lock Screen, in the Dynamic
/// Island and on the CarPlay dashboard. Tracking ends by itself on arrival.
@MainActor
@Observable
final class DriveTracker {
    static let shared = DriveTracker()

    /// Where the drive is headed. `id` is the drive leg's id, or a fresh id for a drive to a plan stop.
    struct Target: Equatable {
        var id: UUID
        var destination: DrivePlace
        var fromName: String
        /// When the plan expects the traveler there (the leg's arrival or the stop's start).
        var plannedArrival: Date?
        var leaveAt: Date
        var timeZoneIdentifier: String
        /// When "Start Drive" was tapped.
        var startedAt = Date.now
        /// Planned route length, so progress counts from the start rather than the first GPS fix.
        var totalMeters: Double?
        /// True for a saved drive, so deleting the drive also ends the live ETA.
        var isSavedDrive = false

        /// A forgotten drive stops following location on its own: two hours after it was due, and
        /// never sooner than three hours after starting.
        var giveUpAt: Date {
            max(startedAt.addingTimeInterval(3 * 3600), (plannedArrival ?? startedAt).addingTimeInterval(2 * 3600))
        }
    }

    struct Live: Equatable {
        var eta: Date
        var remainingMinutes: Int
        var remainingMeters: Double
        /// 0…1 by distance covered.
        var progress: Double
        var arrived: Bool
        var updatedAt: Date

        /// Positive when the ETA is after the planned arrival.
        func minutesLate(for target: Target) -> Int {
            guard let planned = target.plannedArrival else { return 0 }
            return Int((eta.timeIntervalSince(planned) / 60).rounded())
        }
    }

    enum Status: Equatable { case idle, waitingForLocation, live, denied }

    private(set) var target: Target?
    private(set) var live: Live?
    private(set) var status: Status = .idle

    /// Close enough to count as arrived.
    static let arrivalRadius: CLLocationDistance = 150
    /// Ask for a fresh ETA at most this often, unless the car has moved a fair way.
    private static let etaInterval: TimeInterval = 60
    private static let etaDistance: CLLocationDistance = 800

    private var updatesTask: Task<Void, Never>?
    #if os(iOS)
    private var backgroundSession: CLBackgroundActivitySession?
    private var serviceSession: CLServiceSession?
    #endif
    private var startMeters: Double?
    private var lastETAAt = Date.distantPast
    private var lastETALocation: CLLocation?

    func isTracking(_ id: UUID) -> Bool { target?.id == id }

    func start(_ target: Target) {
        stop(endActivity: false)
        self.target = target
        status = .waitingForLocation
        #if os(iOS)
        // Asks for "While Using" the first time; keeps updates coming while Maps is in front.
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        #endif
        DriveActivities.startLive(target)

        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self, !Task.isCancelled else { return }
                    if let target = self.target, Date.now > target.giveUpAt {
                        self.stop()
                        return
                    }
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        self.status = .denied
                        continue
                    }
                    // Skip cached or rough fixes so an old position can't end the drive early.
                    guard let location = update.location, location.horizontalAccuracy >= 0,
                          location.horizontalAccuracy < 500, abs(location.timestamp.timeIntervalSinceNow) < 60 else { continue }
                    await self.handle(location)
                    if self.target == nil { return }
                }
            } catch {}
        }
    }

    func start(_ leg: DriveLeg) {
        start(Target(id: leg.id, destination: leg.to, fromName: leg.from.name,
                     plannedArrival: leg.travelMinutes > 0 ? leg.arrival : nil, leaveAt: leg.departure,
                     timeZoneIdentifier: leg.trip?.timeZone.identifier ?? TimeZone.current.identifier,
                     totalMeters: leg.distanceMeters > 0 ? leg.distanceMeters : nil, isSavedDrive: true))
    }

    /// Stops following the drive. The Live Activity goes too unless `endActivity` is false.
    func stop(endActivity: Bool = true) {
        updatesTask?.cancel()
        updatesTask = nil
        #if os(iOS)
        serviceSession?.invalidate()
        serviceSession = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        #endif
        if endActivity, let target { Task { await DriveActivities.endLive(target.id, arrived: false) } }
        target = nil
        live = nil
        status = .idle
        startMeters = nil
        lastETAAt = .distantPast
        lastETALocation = nil
    }

    private func handle(_ location: CLLocation) async {
        guard let target else { return }
        let destination = CLLocation(latitude: target.destination.latitude, longitude: target.destination.longitude)
        let straight = location.distance(from: destination)

        if straight < Self.arrivalRadius {
            live = Live(eta: .now, remainingMinutes: 0, remainingMeters: 0, progress: 1, arrived: true, updatedAt: .now)
            await DriveActivities.updateLive(target, live!)
            await DriveActivities.endLive(target.id, arrived: true)
            stop(endActivity: false)
            return
        }

        let moved = lastETALocation.map { location.distance(from: $0) } ?? .infinity
        guard Date.now.timeIntervalSince(lastETAAt) >= Self.etaInterval || moved >= Self.etaDistance else { return }
        lastETAAt = .now
        lastETALocation = location

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target.destination.coordinate))
        request.transportType = .automobile
        guard let eta = try? await MKDirections(request: request).calculateETA(), self.target == target else { return }

        let remaining = eta.distance
        if startMeters == nil { startMeters = max(target.totalMeters ?? remaining, remaining, 1) }
        let progress = min(1, max(0, 1 - remaining / (startMeters ?? remaining)))
        live = Live(eta: eta.expectedArrivalDate,
                    remainingMinutes: max(1, Int((eta.expectedTravelTime / 60).rounded())),
                    remainingMeters: remaining, progress: progress, arrived: false, updatedAt: .now)
        status = .live
        await DriveActivities.updateLive(target, live!)
    }
}

extension DriveService {
    /// "Start Drive": turn-by-turn in Maps plus TravelHub's live ETA on the Lock Screen and CarPlay.
    static func startDrive(_ leg: DriveLeg) {
        #if os(iOS)
        DriveTracker.shared.start(leg)
        #endif
        openDirections(to: leg.to, mode: .drive)
    }

    /// Drive to a plan stop that has no saved drive.
    static func startDrive(to place: DrivePlace, from: String, plannedArrival: Date?, timeZone: TimeZone) {
        #if os(iOS)
        DriveTracker.shared.start(.init(id: UUID(), destination: place, fromName: from, plannedArrival: plannedArrival,
                                        leaveAt: .now, timeZoneIdentifier: timeZone.identifier))
        #endif
        openDirections(to: place, mode: .drive)
    }
}
