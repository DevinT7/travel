import SwiftUI
import SwiftData
import MapKit

// MARK: - Card

/// A drive on the Overview: route map, leave and arrive times, and a Directions button that hands
/// off to Apple Maps.
struct DriveCardView: View {
    let leg: DriveLeg
    let tz: TimeZone
    var footer: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CircleIcon(symbol: "car.fill", color: .drive, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.title).font(.headline).lineLimit(1)
                    Text(leg.from.name.isEmpty ? leg.to.address : "From \(leg.from.name)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                DirectionsButton(place: leg.to, leg: leg)
            }
            DriveRouteMap(leg: leg, interactive: false)
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(alignment: .top) {
                timeBlock("Leave", leg.departure)
                Spacer()
                Text(leg.summaryText.isEmpty ? "Route not found" : leg.summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.insetBackground, in: Capsule())
                    .padding(.top, 8)
                Spacer()
                timeBlock("Arrive", leg.arrival, trailing: true)
            }
            let extras = [leg.vehicle, leg.notes].filter { !$0.isEmpty }
            if !extras.isEmpty {
                Label(extras.joined(separator: " · "), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let footer {
                Divider()
                footer
            }
        }
        .card()
    }

    private func timeBlock(_ label: String, _ date: Date, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(date.time(in: tz)).font(.title3.weight(.semibold)).monospacedDigit()
            Text(date.weekdayDayMonth(in: tz)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The round "turn" button used for directions everywhere in the app.
struct DirectionsButton: View {
    let place: DrivePlace
    /// A saved drive starts live ETA tracking along with Maps.
    var leg: DriveLeg?
    var mode: GettingAround = .drive

    var body: some View {
        Button {
            if let leg { DriveService.startDrive(leg) } else { DriveService.openDirections(to: place, mode: mode) }
        } label: {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.title2)
                .foregroundStyle(Color.drive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Directions to \(place.name)")
        .disabled(!place.isSet)
    }
}

/// The driving route on a map, looked up from Apple Maps.
struct DriveRouteMap: View {
    let from: DrivePlace
    let to: DrivePlace
    var departure: Date?
    var avoidTolls = false
    var avoidHighways = false
    var interactive = true
    @State private var route: DriveRoute?

    init(leg: DriveLeg, interactive: Bool = true) {
        self.init(from: leg.from, to: leg.to, departure: leg.departure, avoidTolls: leg.avoidTolls,
                  avoidHighways: leg.avoidHighways, interactive: interactive)
    }

    init(from: DrivePlace, to: DrivePlace, departure: Date? = nil, avoidTolls: Bool = false,
         avoidHighways: Bool = false, interactive: Bool = true) {
        self.from = from
        self.to = to
        self.departure = departure
        self.avoidTolls = avoidTolls
        self.avoidHighways = avoidHighways
        self.interactive = interactive
    }

    private var routeKey: String {
        "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)|\(avoidTolls)\(avoidHighways)"
    }

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
            if let route {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Color.drive, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if from.isSet {
                Annotation(from.name, coordinate: from.coordinate, anchor: .center) {
                    Circle().fill(.white).frame(width: 12, height: 12).overlay(Circle().stroke(Color.drive, lineWidth: 3))
                }
            }
            if to.isSet {
                Marker(to.name, systemImage: "flag.checkered", coordinate: to.coordinate).tint(Color.drive)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: true))
        .allowsHitTesting(interactive)
        .task(id: routeKey) {
            guard from.isSet, to.isSet else { return }
            route = try? await DriveService.shared.route(from: from.coordinate, to: to.coordinate, departure: departure,
                                                         avoidTolls: avoidTolls, avoidHighways: avoidHighways)
        }
    }
}

// MARK: - Editor

/// Add or edit a drive, laid out the way people think about it in a car:
/// 1. **Where to?** Trip places come first (the next plan stop, the hotel, the airport); search
///    covers anything else.
/// 2. **From**, which defaults to where you are now, or the hotel on later days.
/// 3. **When**: *Now* (the default during the trip), *Leave at*, or *Arrive by*. Arrive by works
///    out when to leave, which is what you want for a reservation or a flight.
/// One main button finishes: **Start Drive** when leaving now (opens Maps with a live ETA),
/// **Add Drive** otherwise.
struct DriveLegEditor: View {
    enum Timing: String, CaseIterable, Identifiable {
        case now, leaveAt, arriveBy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .now: "Now"
            case .leaveAt: "Leave at"
            case .arriveBy: "Arrive by"
            }
        }
    }

    enum Origin: Equatable {
        case current
        case place(DrivePlace)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let trip: Trip
    let leg: DriveLeg?

    @State private var to: DrivePlace?
    @State private var origin: Origin?
    @State private var timing: Timing
    @State private var time: Date
    @State private var avoidTolls: Bool
    @State private var avoidHighways: Bool
    @State private var vehicle: String
    @State private var notes: String
    @State private var showOptions = false
    @State private var searchingFrom = false

    @State private var currentCoordinate: CLLocationCoordinate2D?
    @State private var locationState: LocationState = .idle
    @State private var route: DriveRoute?
    @State private var routeError: String?
    @State private var loadingRoute = false
    @State private var saving = false

    enum LocationState { case idle, finding, found, unavailable }

    /// - Parameters:
    ///   - from / to: prefill for a new drive (for example from a gap in the plan).
    ///   - departure: leave at this time; `arriveBy`: be there by this time instead.
    init(trip: Trip, leg: DriveLeg?, from: DrivePlace? = nil, to: DrivePlace? = nil,
         departure: Date? = nil, arriveBy: Date? = nil) {
        self.trip = trip
        self.leg = leg
        let now = Date.now
        let duringTrip = trip.calendar.startOfDay(for: trip.startDate) <= now
            && now < trip.calendar.date(byAdding: .day, value: 1, to: trip.calendar.startOfDay(for: trip.endDate))!
        let firstDay = trip.days.first ?? trip.startDate
        let morning = trip.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay) ?? firstDay

        let timing: Timing
        let time: Date
        if let leg {
            timing = .leaveAt; time = leg.departure
        } else if let arriveBy, arriveBy > now {
            timing = .arriveBy; time = arriveBy
        } else if let departure, departure > now.addingTimeInterval(10 * 60) {
            timing = .leaveAt; time = departure
        } else if duringTrip || departure != nil {
            timing = .now; time = now
        } else {
            timing = .leaveAt; time = morning
        }
        _timing = State(initialValue: timing)
        _time = State(initialValue: time)
        _to = State(initialValue: leg?.to ?? to)

        // Leaving now, or the first day of a trip that hasn't started (usually from home): where
        // you are. Other days: the hotel you wake up in.
        let origin: Origin?
        if let leg {
            origin = .place(leg.from)
        } else if let from {
            origin = .place(from)
        } else if CurrentLocation.isAvailable, timing == .now || trip.calendar.isDate(time, inSameDayAs: firstDay) && !duringTrip {
            origin = .current
        } else if let stay = trip.stay(on: time) ?? trip.sortedStays.first {
            origin = .place(DrivePlace(name: stay.name, address: stay.address, coordinate: stay.coordinate))
        } else {
            origin = CurrentLocation.isAvailable ? .current : nil
        }
        _origin = State(initialValue: origin)
        _avoidTolls = State(initialValue: leg?.avoidTolls ?? false)
        _avoidHighways = State(initialValue: leg?.avoidHighways ?? false)
        _vehicle = State(initialValue: leg?.vehicle ?? "")
        _notes = State(initialValue: leg?.notes ?? "")
    }

    // MARK: Derived

    private var fromCoordinate: CLLocationCoordinate2D? {
        switch origin {
        case .current: currentCoordinate
        case .place(let p): p.coordinate
        case nil: nil
        }
    }

    /// When the car leaves: now, the chosen time, or worked back from the arrival time.
    private var departure: Date {
        switch timing {
        case .now: .now
        case .leaveAt: time
        case .arriveBy: time.addingTimeInterval(-TimeInterval((route?.minutes ?? 0) * 60))
        }
    }

    private var arrival: Date? {
        guard let route else { return nil }
        return timing == .arriveBy ? time : departure.addingTimeInterval(TimeInterval(route.minutes * 60))
    }

    private var routeKey: String {
        guard let a = fromCoordinate, let b = to?.coordinate else { return "" }
        // Arrive-by routes are looked up for roughly when they'd leave.
        let when = timing == .now ? 0 : Int(time.timeIntervalSince1970 / 900)
        return "\(a.latitude),\(a.longitude)>\(b.latitude),\(b.longitude)|\(timing.rawValue)|\(when)|\(avoidTolls)|\(avoidHighways)"
    }

    private var canFinish: Bool { to != nil && fromCoordinate != nil && !saving }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                if to != nil {
                    fromSection
                    whenSection
                    previewSection
                    optionsSection
                }
                if let leg {
                    Section {
                        Button("Remove Drive", role: .destructive) {
                            context.delete(leg)
                            try? context.save()
                            Task { await DriveActivities.syncAll() }
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .environment(\.timeZone, trip.timeZone)
            .keyboardDismissable()
            .navigationTitle(leg == nil ? "New Drive" : "Edit Drive")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryTitle) { finish() }.disabled(!canFinish)
                }
                #endif
            }
            #if os(iOS)
            .safeAreaInset(edge: .bottom) { if to != nil { bottomBar } }
            #endif
            .task(id: originIsCurrent) { await locateIfNeeded() }
            .task(id: routeKey) { await loadRoute() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 620)
        #endif
    }

    private var originIsCurrent: Bool { origin == .current }

    // MARK: Sections

    @ViewBuilder
    private var destinationSection: some View {
        if let to {
            Section {
                HStack(spacing: 12) {
                    CircleIcon(symbol: "flag.checkered", color: .drive, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(to.name).font(.headline).lineLimit(1)
                        if !to.address.isEmpty, to.address != to.name {
                            Text(to.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Change") { self.to = nil; route = nil }.buttonStyle(.borderless)
                }
            } header: {
                Text("Where to")
            }
        } else {
            PlaceSearchSection(title: "Where to?", trip: trip, suggestions: DriveSuggestion.destinations(for: trip)) { pick in
                to = pick.place
                // A plan stop with a start time: be there for it.
                if let start = pick.time, start > .now.addingTimeInterval(15 * 60) {
                    timing = .arriveBy
                    time = start
                }
            }
        }
    }

    private var fromSection: some View {
        Section {
            if searchingFrom {
                PlaceSearchSection.field(trip: trip, prompt: "Search a starting point") { place in
                    origin = .place(place)
                    searchingFrom = false
                } cancel: {
                    searchingFrom = false
                }
            } else {
                Menu {
                    if CurrentLocation.isAvailable {
                        Button("Current Location", systemImage: "location.fill") { origin = .current }
                    }
                    let picks = DriveSuggestion.origins(for: trip, excluding: to)
                    if !picks.isEmpty {
                        Section("On this trip") {
                            ForEach(picks) { s in
                                Button(s.place.name, systemImage: s.symbol) { origin = .place(s.place) }
                            }
                        }
                    }
                    Button("Search…", systemImage: "magnifyingglass") { searchingFrom = true }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: originIsCurrent ? "location.fill" : "circle.circle")
                            .foregroundStyle(Color.drive).frame(width: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("From").font(.caption).foregroundStyle(.secondary)
                            Text(originTitle).foregroundStyle(.primary).lineLimit(1)
                            if let detail = originDetail {
                                Text(detail).font(.caption).foregroundStyle(locationState == .unavailable ? .orange : .secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var originTitle: String {
        switch origin {
        case .current: "Current Location"
        case .place(let p): p.name
        case nil: "Choose a starting point"
        }
    }

    private var originDetail: String? {
        guard origin == .current else { return nil }
        switch locationState {
        case .finding: return "Finding you…"
        case .unavailable: return "Location is off for TravelHub. Pick where you're starting from instead."
        default: return nil
        }
    }

    private var whenSection: some View {
        Section {
            Picker("When", selection: $timing.animation()) {
                ForEach(Timing.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: timing) { _, new in
                // Switching from Now: start from a sensible time rather than this second.
                if new != .now, time < .now { time = Self.roundedUp(.now.addingTimeInterval(30 * 60)) }
            }

            if timing != .now {
                DatePicker(timing == .arriveBy ? "Be there by" : "Leave at", selection: $time,
                           displayedComponents: [.date, .hourAndMinute])
                let shortcuts = timeShortcuts.filter { !($0.timing == timing && abs($0.time.timeIntervalSince(time)) < 60) }
                if !shortcuts.isEmpty {
                    HorizontalScroller {
                        HStack(spacing: 8) {
                            ForEach(shortcuts, id: \.label) { s in
                                Button {
                                    withAnimation { timing = s.timing; time = s.time }
                                } label: {
                                    Label(s.label, systemImage: s.symbol)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Color.insetBackground, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("When")
        } footer: {
            if timing != .now { Text("Times are in \(trip.destinationName) time.") }
        }
    }

    /// One-tap times: after a flight lands that day, or in time for a plan stop.
    private var timeShortcuts: [(label: String, symbol: String, timing: Timing, time: Date)] {
        var result: [(String, String, Timing, Date)] = []
        let cal = trip.calendar
        let day = timing == .now ? Date.now : time
        for f in trip.sortedFlights where cal.isDate(f.arrival.best, inSameDayAs: day) && f.arrival.best > .now {
            // Off the plane, bags and the rental counter take about 45 minutes.
            let ready = Self.roundedUp(f.arrival.best.addingTimeInterval(45 * 60))
            result.append(("After landing · \(ready.time(in: trip.timeZone))", "airplane.arrival", .leaveAt, ready))
        }
        if let to, let stop = (trip.planItems ?? []).first(where: {
            $0.isScheduled && $0.start > .now && $0.coordinate.map { abs($0.latitude - to.latitude) < 0.0005 && abs($0.longitude - to.longitude) < 0.0005 } == true
        }) {
            result.append(("By \(stop.start.time(in: trip.timeZone)) for \(stop.title)", "clock", .arriveBy, stop.start))
        }
        return result
    }

    @ViewBuilder
    private var previewSection: some View {
        if let to, let from = fromCoordinate {
            Section {
                DriveRouteMap(from: DrivePlace(name: originTitle, coordinate: from), to: to,
                              departure: timing == .now ? nil : departure,
                              avoidTolls: avoidTolls, avoidHighways: avoidHighways)
                    .id(routeKey)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                #if os(macOS)
                routeSummary
                #endif
            }
        } else if origin == .current, locationState == .finding {
            Section {
                HStack { ProgressView().controlSize(.small); Text("Finding you…").foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private var routeSummary: some View {
        if loadingRoute && route == nil {
            HStack { ProgressView().controlSize(.small); Text("Checking traffic…").foregroundStyle(.secondary) }
        } else if let route {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(DriveService.durationText(route.minutes)).font(.title2.weight(.bold))
                    Text(DriveService.distanceText(route.meters)).foregroundStyle(.secondary)
                    Spacer()
                }
                switch timing {
                case .now:
                    Text("Arrive around \(arrival?.time(in: trip.timeZone) ?? "")").foregroundStyle(.secondary)
                case .leaveAt:
                    Text("Arrive around \(arrival?.time(in: trip.timeZone) ?? "")").foregroundStyle(.secondary)
                case .arriveBy:
                    if departure < .now {
                        Label("You'd need to have left at \(departure.time(in: trip.timeZone))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Leave by \(departure.time(in: trip.timeZone))").fontWeight(.semibold).foregroundStyle(Color.drive)
                    }
                }
            }
        } else if let routeError {
            Label(routeError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var optionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showOptions) {
                Toggle("Avoid Tolls", isOn: $avoidTolls)
                Toggle("Avoid Highways", isOn: $avoidHighways)
                TextField("Car (optional)", text: $vehicle, prompt: Text("e.g. Rental car, Hertz pickup"))
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
            } label: {
                HStack {
                    Text("Route Options")
                    Spacer()
                    if !optionsSummary.isEmpty {
                        Text(optionsSummary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var optionsSummary: String {
        [avoidTolls ? "No tolls" : nil, avoidHighways ? "No highways" : nil, vehicle.isEmpty ? nil : vehicle]
            .compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Finish

    private var primaryTitle: String {
        if leg != nil { return "Save" }
        return timing == .now ? "Start Drive" : "Add Drive"
    }

    /// The answer people open this sheet for, kept in view above the button.
    @ViewBuilder
    private var bottomSummary: some View {
        if loadingRoute && route == nil || origin == .current && locationState == .finding {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking traffic…") }
                .foregroundStyle(.secondary)
        } else if let route {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(DriveService.durationText(route.minutes)).font(.title3.weight(.bold))
                Text(DriveService.distanceText(route.meters)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                switch timing {
                case .now, .leaveAt:
                    Text("Arrive \(arrival?.time(in: trip.timeZone) ?? "")").fontWeight(.medium)
                case .arriveBy:
                    if departure < .now {
                        Label("Leave now, you're \(Int(Date.now.timeIntervalSince(departure) / 60)) min behind", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).fontWeight(.medium)
                    } else {
                        Text("Leave by \(departure.time(in: trip.timeZone))").fontWeight(.semibold).foregroundStyle(Color.drive)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else if let routeError {
            Label(routeError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
        } else if fromCoordinate == nil {
            Text(origin == nil ? "Choose where you're starting from" : "Pick a starting point to see the drive")
                .foregroundStyle(.secondary)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            bottomSummary
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            primaryButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var primaryButton: some View {
        Button(action: finish) {
            Label(primaryTitle, systemImage: timing == .now && leg == nil ? "car.fill" : "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.drive)
        .disabled(!canFinish)
    }

    private func finish() {
        guard let to, let fromCoordinate else { return }
        saving = true
        Task {
            var fromPlace: DrivePlace
            switch origin {
            case .place(let p): fromPlace = p
            default:
                let (name, address) = await CurrentLocation.describe(fromCoordinate)
                fromPlace = DrivePlace(name: name, address: address, coordinate: fromCoordinate)
            }
            let target = leg ?? {
                let new = DriveLeg(from: fromPlace, to: to, departure: departure)
                context.insert(new)
                new.trip = trip
                return new
            }()
            target.from = fromPlace
            target.to = to
            target.departure = departure
            target.avoidTolls = avoidTolls
            target.avoidHighways = avoidHighways
            target.vehicle = vehicle.trimmingCharacters(in: .whitespaces)
            target.notes = notes
            if let route {
                target.travelMinutes = route.minutes
                target.distanceMeters = route.meters
                target.routeUpdatedAt = .now
            }
            try? context.save()
            let startNow = leg == nil && timing == .now
            dismiss()
            if startNow {
                DriveService.startDrive(target)
            } else {
                await DriveActivities.syncAll()
            }
        }
    }

    // MARK: Data

    private func locateIfNeeded() async {
        guard origin == .current, currentCoordinate == nil else { return }
        locationState = .finding
        if let c = await CurrentLocation.fetch() {
            currentCoordinate = c
            locationState = .found
        } else {
            locationState = .unavailable
        }
    }

    private func loadRoute() async {
        guard let a = fromCoordinate, let b = to?.coordinate else { route = nil; return }
        loadingRoute = true
        defer { loadingRoute = false }
        // Arrive by: look the route up for about when they'd set off.
        let when: Date? = switch timing {
        case .now: nil
        case .leaveAt: time
        case .arriveBy: time.addingTimeInterval(-TimeInterval((route?.minutes ?? 30) * 60))
        }
        do {
            route = try await DriveService.shared.route(from: a, to: b, departure: when,
                                                        avoidTolls: avoidTolls, avoidHighways: avoidHighways)
            routeError = nil
        } catch {
            route = nil
            routeError = (error as? LocalizedError)?.errorDescription ?? "Couldn't find a driving route."
        }
    }

    static func roundedUp(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 900).rounded(.up) * 900)
    }
}

// MARK: - Place picking

/// A place on the trip worth driving to or from.
struct DriveSuggestion: Identifiable, Hashable {
    var place: DrivePlace
    var symbol: String
    var detail: String
    /// A plan stop's start time.
    var time: Date?

    var id: String { "\(place.name)|\(place.latitude)|\(place.longitude)" }

    /// Upcoming plan stops first (soonest first), then hotels, then airports.
    static func destinations(for trip: Trip) -> [DriveSuggestion] {
        let tz = trip.timeZone
        let cal = trip.calendar
        var result: [DriveSuggestion] = []
        let stops = (trip.planItems ?? []).filter { $0.isScheduled && $0.coordinate != nil && $0.end > .now }
            .sorted { $0.start < $1.start }
        for p in stops.prefix(6) {
            let day = cal.isDate(p.start, inSameDayAs: .now) ? "Today" : p.start.weekdayDayMonth(in: tz)
            result.append(.init(place: DrivePlace(name: p.title, address: p.address, coordinate: p.coordinate),
                                symbol: p.category.symbol, detail: "\(day), \(p.start.time(in: tz))", time: p.start))
        }
        for s in trip.sortedStays {
            result.append(.init(place: DrivePlace(name: s.name, address: s.address, coordinate: s.coordinate),
                                symbol: "bed.double.fill", detail: "Where you're staying"))
        }
        for f in trip.sortedFlights where f.departure.best > .now && !f.departure.iata.isEmpty {
            result.append(.init(place: DrivePlace(name: "\(f.departure.iata) airport", address: f.departure.airportName,
                                                  coordinate: f.departure.coordinate),
                                symbol: "airplane.departure",
                                detail: "\(f.flightNumber) leaves \(f.departure.best.weekdayDayMonth(in: f.departure.timeZone)), \(f.departure.best.time(in: f.departure.timeZone))"))
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.place.name).inserted }
    }

    /// Hotels and arrival airports, then plan stops.
    static func origins(for trip: Trip, excluding: DrivePlace?) -> [DriveSuggestion] {
        var result: [DriveSuggestion] = []
        for s in trip.sortedStays {
            result.append(.init(place: DrivePlace(name: s.name, address: s.address, coordinate: s.coordinate),
                                symbol: "bed.double.fill", detail: ""))
        }
        for f in trip.sortedFlights where !f.arrival.iata.isEmpty {
            result.append(.init(place: DrivePlace(name: "\(f.arrival.iata) airport", address: f.arrival.airportName,
                                                  coordinate: f.arrival.coordinate), symbol: "airplane.arrival", detail: ""))
        }
        for p in (trip.planItems ?? []).filter({ $0.isScheduled && $0.coordinate != nil }).sorted(by: { $0.start < $1.start }) {
            result.append(.init(place: DrivePlace(name: p.title, address: p.address, coordinate: p.coordinate),
                                symbol: p.category.symbol, detail: ""))
        }
        var seen = Set<String>()
        return result.filter { $0.place.name != excluding?.name && seen.insert($0.place.name).inserted }.prefix(10).map { $0 }
    }
}

/// "Where to?": a search field with the trip's own places listed under it until you type.
struct PlaceSearchSection: View {
    let title: String
    let trip: Trip
    let suggestions: [DriveSuggestion]
    let onPick: (DriveSuggestion) -> Void
    @State private var search: LocationSearch

    init(title: String, trip: Trip, suggestions: [DriveSuggestion], onPick: @escaping (DriveSuggestion) -> Void) {
        self.title = title
        self.trip = trip
        self.suggestions = suggestions
        self.onPick = onPick
        _search = State(initialValue: Self.makeSearch(trip))
    }

    static func makeSearch(_ trip: Trip) -> LocationSearch {
        LocationSearch(kind: .place, near: MKCoordinateRegion(center: trip.coordinate, latitudinalMeters: 400_000,
                                                              longitudinalMeters: 400_000))
    }

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(title, text: $search.query, prompt: Text("Search a place or address"))
                    .autocorrectionDisabled()
                    .font(.body)
            }
            if search.query.isEmpty {
                ForEach(suggestions) { s in
                    Button { onPick(s) } label: { row(symbol: s.symbol, title: s.place.name, detail: s.detail) }
                        .buttonStyle(.plain)
                }
            } else {
                ForEach(search.results.prefix(6), id: \.self) { r in
                    Button {
                        Task {
                            if let p = try? await search.resolve(r) {
                                onPick(DriveSuggestion(place: DrivePlace(name: p.name, address: p.address, coordinate: p.coordinate),
                                                       symbol: "mappin", detail: ""))
                            }
                        }
                    } label: { row(symbol: "mappin", title: r.title, detail: r.subtitle) }
                        .buttonStyle(.plain)
                }
            }
        } header: {
            Text(title)
        } footer: {
            if search.query.isEmpty, !suggestions.isEmpty { Text("Places from this trip. Search for anywhere else.") }
        }
    }

    private func row(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            CircleIcon(symbol: symbol, color: .drive, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(.primary).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    /// A bare search field for picking a starting point.
    static func field(trip: Trip, prompt: String, onPick: @escaping (DrivePlace) -> Void, cancel: @escaping () -> Void) -> some View {
        InlinePlaceSearch(trip: trip, prompt: prompt, onPick: onPick, cancel: cancel)
    }
}

private struct InlinePlaceSearch: View {
    let trip: Trip
    let prompt: String
    let onPick: (DrivePlace) -> Void
    let cancel: () -> Void
    @State private var search: LocationSearch

    init(trip: Trip, prompt: String, onPick: @escaping (DrivePlace) -> Void, cancel: @escaping () -> Void) {
        self.trip = trip
        self.prompt = prompt
        self.onPick = onPick
        self.cancel = cancel
        _search = State(initialValue: PlaceSearchSection.makeSearch(trip))
    }

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $search.query).autocorrectionDisabled()
            Button("Cancel", action: cancel).buttonStyle(.borderless)
        }
        ForEach(search.results.prefix(5), id: \.self) { r in
            Button {
                Task {
                    if let p = try? await search.resolve(r) {
                        onPick(DrivePlace(name: p.name, address: p.address, coordinate: p.coordinate))
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).foregroundStyle(.primary)
                    Text(r.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
