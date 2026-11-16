#if os(iOS)
import CarPlay
import SwiftData
import UIKit

/// TravelHub in CarPlay, as a driving-task app: the day's drives and stops, each with how long the
/// drive takes and when to leave, and one button that starts directions in Maps.
///
/// Design rules this follows (CarPlay Developer Guide, driving task category):
/// - Templates only, two levels deep: a list of today's drives, then one drive's details.
/// - Nothing to set up or type in the car; trips are planned on the phone or Mac.
/// - No message ever asks the driver to pick up the phone.
/// - TravelHub doesn't navigate; "Directions" hands off to Maps on the car's screen.
/// - Data refreshes every 30 seconds (the limit is every 10 seconds).
/// - "Start Drive" opens Maps and keeps a live ETA in the list and on the dashboard.
/// - Lists are capped to what the car allows while moving (as few as 12 rows).
@MainActor
final class CarPlaySceneDelegate: UIResponder, @preconcurrency CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private weak var scene: CPTemplateApplicationScene?
    private var rootTemplate: CPListTemplate?
    private var refreshTimer: Timer?
    private var saveObserver: NSObjectProtocol?
    private var lastRefresh = Date.distantPast

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.scene = scene
        self.interfaceController = interfaceController
        autoStartDueDrive()
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Edits made on the phone show up in the car right away (but not more than every 10 s).
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date.now.timeIntervalSince(self.lastRefresh) > 10 else { return }
                self.refresh()
            }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
        self.interfaceController = nil
        rootTemplate = nil
    }

    // MARK: Content

    /// One thing worth driving to: a planned drive, a plan stop, or the hotel.
    private struct Stop {
        var title: String
        var detail: String
        var symbol: String
        var place: DrivePlace
        var arriveBy: Date?
        var leaveBy: Date?
        var minutes: Int?
        var distance: String
        var from: String?
        /// Where the drive to this stop starts: the previous stop, or the hotel for the first one.
        var origin: CLLocationCoordinate2D?
        /// The saved drive, when this stop is one.
        var legID: UUID?
    }

    private func refresh() {
        lastRefresh = .now
        let context = AppData.container.mainContext
        let trips = (try? context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let selected = UserDefaults.standard.string(forKey: "selectedTripID").flatMap(UUID.init(uuidString:))
        // In the car, "today" means the trip happening now, not whatever was last open on the phone.
        let trip = trips.first(where: \.isOngoing) ?? Trip.current(in: trips, selectedID: selected)

        let title = trip.map { $0.isOngoing ? "Today · \($0.displayName)" : $0.displayName } ?? "TravelHub"
        let rootTemplate = root(titled: title)
        guard let trip else {
            rootTemplate.updateSections([])
            return
        }

        let limit = CPListTemplate.maximumItemCount
        var sections: [CPListSection] = []
        let (next, later) = stops(for: trip)

        if let next {
            sections.append(CPListSection(items: [item(next, tz: trip.timeZone, prominent: true)], header: "Up Next", sectionIndexTitle: nil))
        }
        if !later.isEmpty {
            let items = later.prefix(max(0, limit - sections.count - 2)).map { item($0, tz: trip.timeZone, prominent: false) }
            sections.append(CPListSection(items: items, header: trip.isOngoing ? "Later Today" : "First Day", sectionIndexTitle: nil))
        }
        if let stay = trip.stay(on: .now) ?? trip.sortedStays.first {
            let hotel = Stop(title: stay.name, detail: "Where you're staying", symbol: "bed.double.fill",
                             place: DrivePlace(name: stay.name, address: stay.address, coordinate: stay.coordinate),
                             distance: "", origin: (later.last ?? next)?.place.coordinate)
            sections.append(CPListSection(items: [item(hotel, tz: trip.timeZone, prominent: false)], header: "Hotel", sectionIndexTitle: nil))
        }
        rootTemplate.updateSections(sections)
    }

    private func startTracking(_ stop: Stop, tz: TimeZone) {
        if let id = stop.legID,
           let leg = try? AppData.container.mainContext.fetch(FetchDescriptor<DriveLeg>(predicate: #Predicate { $0.id == id })).first {
            DriveTracker.shared.start(leg)
        } else {
            DriveTracker.shared.start(.init(id: UUID(), destination: stop.place, fromName: "", plannedArrival: stop.arriveBy,
                                            leaveAt: .now, timeZoneIdentifier: tz.identifier))
        }
    }

    /// Getting into the car around the time a planned drive leaves starts its live ETA.
    private func autoStartDueDrive() {
        guard DriveTracker.shared.target == nil else { return }
        let legs = (try? AppData.container.mainContext.fetch(FetchDescriptor<DriveLeg>())) ?? []
        if let due = legs.filter({ $0.trip != nil && $0.to.isSet && abs($0.departure.timeIntervalSinceNow) < 30 * 60 })
            .min(by: { abs($0.departure.timeIntervalSinceNow) < abs($1.departure.timeIntervalSinceNow) }) {
            DriveTracker.shared.start(due)
        }
    }

    /// The list template's title can't change, so a new trip or day gets a new root template.
    private func root(titled title: String) -> CPListTemplate {
        if let rootTemplate, rootTemplate.title == title { return rootTemplate }
        let root = CPListTemplate(title: title, sections: [])
        root.emptyViewTitleVariants = ["Nothing to drive to today"]
        root.emptyViewSubtitleVariants = ["Drives and stops from your trip show up here"]
        rootTemplate = root
        interfaceController?.setRootTemplate(root, animated: false, completion: nil)
        return root
    }

    /// Today's drives and plan stops in order (or the first day's, before the trip starts).
    private func stops(for trip: Trip) -> (next: Stop?, later: [Stop]) {
        let cal = trip.calendar
        let day = trip.isOngoing ? Date.now : (trip.days.first ?? trip.startDate)
        let now = Date.now
        var stops: [(Date, Stop)] = []

        for d in trip.sortedDrives where cal.isDate(d.departure, inSameDayAs: day) && d.arrival > now && d.to.isSet {
            stops.append((d.departure, Stop(
                title: d.to.name, detail: "", symbol: "car.fill", place: d.to,
                arriveBy: d.travelMinutes > 0 ? d.arrival : nil, leaveBy: d.departure,
                minutes: d.travelMinutes > 0 ? d.travelMinutes : nil,
                distance: DriveService.distanceText(d.distanceMeters),
                from: d.from.name.isEmpty ? nil : d.from.name, legID: d.id)))
        }
        for p in (trip.planItems ?? []) where p.isScheduled && cal.isDate(p.start, inSameDayAs: day) && p.end > now {
            guard let c = p.coordinate else { continue }
            stops.append((p.start, Stop(
                title: p.title, detail: "", symbol: p.category.symbol,
                place: DrivePlace(name: p.title, address: p.address, coordinate: c),
                arriveBy: p.start, leaveBy: nil, minutes: nil, distance: "", from: nil)))
        }
        var ordered = stops.sorted { $0.0 < $1.0 }.map(\.1)
        var previous = trip.stay(on: day)?.coordinate
        for i in ordered.indices {
            ordered[i].origin = previous
            previous = ordered[i].place.coordinate
        }
        return (ordered.first, Array(ordered.dropFirst()))
    }

    private func item(_ stop: Stop, tz: TimeZone, prominent: Bool) -> CPListItem {
        let item = CPListItem(text: stop.title, detailText: detailText(stop, tz: tz),
                              image: UIImage(systemName: stop.symbol)?.withTintColor(UIColor(red: 0.42, green: 0.58, blue: 0.78, alpha: 1), renderingMode: .alwaysOriginal))
        item.accessoryType = .disclosureIndicator
        item.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.showDetail(stop, tz: tz)
                completion()
            }
        }
        return item
    }

    /// The drive being followed right now, if it's this stop.
    private func live(for stop: Stop) -> DriveTracker.Live? {
        let tracker = DriveTracker.shared
        guard let target = tracker.target, let live = tracker.live else { return nil }
        let same = stop.legID.map { $0 == target.id }
            ?? (abs(target.destination.latitude - stop.place.latitude) < 0.0005 && abs(target.destination.longitude - stop.place.longitude) < 0.0005)
        return same ? live : nil
    }

    /// "Leave 2:35 PM · 32 min", "Arrive by 10:00 AM", or the live "ETA 3:52 PM · 18 min left".
    private func detailText(_ stop: Stop, tz: TimeZone) -> String {
        if let live = live(for: stop) {
            return "ETA \(live.eta.time(in: tz)) · \(DriveService.durationText(live.remainingMinutes)) left"
        }
        if let leave = stop.leaveBy {
            return ["Leave \(leave.time(in: tz))", stop.minutes.map(DriveService.durationText)].compactMap { $0 }.joined(separator: " · ")
        }
        if let arrive = stop.arriveBy { return "Be there by \(arrive.time(in: tz))" }
        return stop.place.address.isEmpty ? stop.detail : stop.place.address
    }

    /// One stop: drive time and when to leave, with a Directions button. Live ETA from Apple Maps.
    private func showDetail(_ stop: Stop, tz: TimeZone) async {
        guard let interfaceController else { return }
        var minutes = stop.minutes
        var distance = stop.distance
        // Plan stops and the hotel don't have a stored drive; estimate one from the stop before it.
        if minutes == nil, let origin = stop.origin,
           abs(origin.latitude - stop.place.latitude) > 0.0005 || abs(origin.longitude - stop.place.longitude) > 0.0005 {
            if let route = try? await DriveService.shared.route(from: origin, to: stop.place.coordinate) {
                minutes = route.minutes
                distance = DriveService.distanceText(route.meters)
            }
        }

        var items: [CPInformationItem] = []
        if let live = live(for: stop) {
            items.append(CPInformationItem(title: "ETA (live)", detail: live.eta.time(in: tz)))
            items.append(CPInformationItem(title: "Remaining", detail: [DriveService.durationText(live.remainingMinutes),
                                                                        DriveService.distanceText(live.remainingMeters)]
                .filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        if let leave = stop.leaveBy {
            items.append(CPInformationItem(title: "Leave", detail: leave.time(in: tz)))
        } else if let arrive = stop.arriveBy, let minutes {
            items.append(CPInformationItem(title: "Leave by", detail: arrive.addingTimeInterval(-TimeInterval(minutes * 60)).time(in: tz)))
        }
        if let minutes {
            items.append(CPInformationItem(title: "Drive", detail: [DriveService.durationText(minutes), distance].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        if let arrive = stop.arriveBy {
            items.append(CPInformationItem(title: stop.leaveBy != nil ? "Arrive" : "Starts", detail: arrive.time(in: tz)))
        }
        if let from = stop.from { items.append(CPInformationItem(title: "From", detail: from)) }
        if !stop.place.address.isEmpty { items.append(CPInformationItem(title: "Address", detail: stop.place.address)) }

        // Maps does the navigating; TravelHub keeps the ETA live on the dashboard next to it.
        let directions = CPTextButton(title: "Start Drive", textStyle: .confirm) { [weak self] _ in
            self?.startTracking(stop, tz: tz)
            self?.scene?.open(DriveService.mapsURL(to: stop.place), options: nil, completionHandler: nil)
        }
        let template = CPInformationTemplate(title: stop.title, layout: .twoColumn, items: items, actions: [directions])
        // Driving-task apps may stack two templates; replace a detail that's already showing.
        if interfaceController.templates.count > 1 {
            interfaceController.popToRootTemplate(animated: false, completion: nil)
        }
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }
}
#endif
