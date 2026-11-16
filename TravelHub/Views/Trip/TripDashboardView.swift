import SwiftUI
import SwiftData
import MapKit

struct TripDashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Bindable var trip: Trip

    @State private var forecast: [DailyForecast] = []
    @State private var forecastLoaded = false
    @State private var exchangeRate: Double?
    @State private var showingAddFlight = false
    @State private var showingAddStay = false
    @State private var showingAddDrive = false
    @State private var editingDrive: DriveLeg?
    @State private var editingStay: Stay?
    @State private var addingActivity = false
    @State private var refreshError: String?
    @State private var calendarMessage: String?
    /// Bumped when a Live Activity starts or stops, so the Track buttons redraw.
    @State private var trackingRevision = 0
    /// A flight or drive opened from the Travel list.
    @State private var openedLeg: TravelLeg?
    @State private var editingDriveInSheet: DriveLeg?
    @State private var showingEarlier = false

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)]

    /// A lone card spans the full width on wide screens instead of sitting in half of a two-column grid.
    private func columns(for count: Int) -> [GridItem] {
        count == 1 ? [GridItem(.flexible(), alignment: .top)] : columns
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TripHeroView(trip: trip)

                HStack(spacing: 8) {
                    QuickAction(title: "Flight", symbol: "airplane") { showingAddFlight = true }
                    QuickAction(title: "Stay", symbol: "bed.double") { showingAddStay = true }
                    QuickAction(title: "Drive", symbol: "car") { showingAddDrive = true }
                    QuickAction(title: "Activity", symbol: "plus") { addingActivity = true }
                    QuickAction(title: "Discover", symbol: "mappin.and.ellipse") { model.tripSection = .discover }
                }
                .padding(.top, -6)

                VStack(alignment: .leading, spacing: 28) {
                    travelSection
                    upNextSection
                    staySection
                    weatherSection
                    goodToKnowSection
                }
                .padding(.horizontal, Metrics.gutter)
                .readableWidth()
            }
            .padding(.bottom, 32)
        }
        #if os(iOS)
        // The destination photo runs up under the navigation bar.
        .ignoresSafeArea(edges: .top)
        .statusBarFade()
        #endif
        .background(Color.appBackground)
        .navigationTitle(trip.displayName)
        .inlineTitle()
        #if os(iOS)
        // The photo already shows the trip name; keep the bar to its buttons.
        .toolbar(removing: .title)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Flight", systemImage: "airplane") { showingAddFlight = true }
                    Button("Add Stay", systemImage: "bed.double") { showingAddStay = true }
                    Button("Add Drive", systemImage: "car") { showingAddDrive = true }
                    Button("Add Activity", systemImage: "plus") { addingActivity = true }
                    Divider()
                    Button("Add to Calendar", systemImage: "calendar.badge.plus") { addToCalendar() }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .alert(calendarMessage ?? "", isPresented: .init(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .refreshable { await refreshAll() }
        .task(id: trip.id) { await loadInfo() }
        .task(id: trip.id) { await keepLiveFlightsFresh() }
        .sheet(isPresented: $showingAddFlight) { AddFlightView(trip: trip) }
        .sheet(isPresented: $showingAddStay) { StayEditorView(trip: trip, stay: nil) }
        .sheet(isPresented: $showingAddDrive) { DriveLegEditor(trip: trip, leg: nil) }
        .sheet(item: $editingDrive) { DriveLegEditor(trip: trip, leg: $0) }
        .sheet(isPresented: $addingActivity) { PlanItemEditor(trip: trip, mode: .custom(day: nil)) }
        .sheet(item: $editingStay) { StayEditorView(trip: trip, stay: $0) }
        .sheet(item: $openedLeg) { legSheet($0) }
        .alert("Couldn't refresh flights", isPresented: .init(get: { refreshError != nil }, set: { if !$0 { refreshError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(refreshError ?? "") }
    }

    // MARK: Sections

    /// Flights and drives in one place, in order. The next one gets the full card (live status,
    /// Track, Start Drive); later ones are one-line rows that open the full card; finished ones
    /// fold away under "Earlier" so they don't push today's plans down the page.
    @ViewBuilder
    private var travelSection: some View {
        let legs = trip.travelLegs
        if !legs.isEmpty {
            let now = Date.now
            let upcoming = legs.filter { $0.end > now }
            let earlier = legs.filter { $0.end <= now }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Travel") {
                    Menu("Add") {
                        Button("Flight", systemImage: "airplane") { showingAddFlight = true }
                        Button("Drive", systemImage: "car") { showingAddDrive = true }
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .foregroundStyle(.tint)
                }
                if let next = upcoming.first {
                    upNextLabel(next)
                    if case .flight(let flight) = next, FlightProgress.fraction(of: flight) != nil {
                        RouteMapCard(flights: [flight])
                    }
                    fullCard(next, inSheet: false)
                }
                let later = Array(upcoming.dropFirst())
                if !later.isEmpty {
                    legList(later)
                }
                if !earlier.isEmpty {
                    if upcoming.isEmpty {
                        legList(earlier)
                    } else {
                        Button {
                            withAnimation(.snappy) { showingEarlier.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text(showingEarlier ? "Hide earlier" : "Earlier · \(earlier.count)")
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .rotationEffect(.degrees(showingEarlier ? 180 : 0))
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if showingEarlier {
                            legList(earlier).opacity(0.75)
                        }
                    }
                }
            }
        }
    }

    /// "UP NEXT  Tomorrow" / "IN THE AIR" above the featured card.
    private func upNextLabel(_ leg: TravelLeg) -> some View {
        let now = Date.now
        let underway = leg.start <= now
        let title: String = underway ? (leg.isFlight ? "In the air" : "On the road") : "Up next"
        var when = ""
        if !underway {
            let cal = trip.calendar
            let hours = leg.start.timeIntervalSince(now) / 3600
            if hours < 12 {
                let minutes = Int(leg.start.timeIntervalSince(now) / 60)
                when = minutes < 60 ? "in \(max(minutes, 1)) min"
                    : minutes % 60 == 0 ? "in \(minutes / 60)h" : "in " + leg.start.timeIntervalSince(now).hoursMinutes
            } else if cal.isDate(leg.start, inSameDayAs: now) {
                when = "Today"
            } else if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(leg.start, inSameDayAs: tomorrow) {
                when = "Tomorrow"
            } else {
                when = leg.start.weekdayDayMonth(in: trip.timeZone)
            }
        }
        return HStack(spacing: 8) {
            if underway { Circle().fill(.green).frame(width: 8, height: 8) }
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(underway ? Color.green : Color.accentColor)
            if !when.isEmpty { Text(when).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, -4)
    }

    /// The full flight or drive card with its live controls.
    @ViewBuilder
    private func fullCard(_ leg: TravelLeg, inSheet: Bool) -> some View {
        switch leg {
        case .flight(let flight):
            FlightCardView(flight: flight, footer: FlightActivities.canTrack(flight) ? AnyView(liveRow(flight)) : nil)
                .contextMenu {
                    Button("Refresh Status", systemImage: "arrow.clockwise") { Task { await refresh(flight) } }
                    if FlightActivities.canTrack(flight) { trackButton(flight) }
                    Button("Remove Flight", systemImage: "trash", role: .destructive) { remove(.flight(flight)) }
                }
                .id("\(flight.id)-\(trackingRevision)")
        case .drive(let drive):
            DriveCardView(leg: drive, tz: trip.timeZone,
                          footer: Self.offersStartDrive ? AnyView(driveLiveRow(drive)) : nil)
                .contentShape(Rectangle())
                .onTapGesture { if inSheet { editingDriveInSheet = drive } else { editingDrive = drive } }
                .contextMenu {
                    Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        DriveService.openDirections(to: drive.to)
                    }
                    Button("Edit", systemImage: "pencil") {
                        if inSheet { editingDriveInSheet = drive } else { editingDrive = drive }
                    }
                    Button("Remove Drive", systemImage: "trash", role: .destructive) { remove(.drive(drive)) }
                }
                .id("\(drive.id)-\(trackingRevision)")
        }
    }

    /// One-line rows in a single card; tapping one opens its full card.
    private func legList(_ legs: [TravelLeg]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                Button { openedLeg = leg } label: { legRow(leg) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { remove(leg) }
                    }
                if index < legs.count - 1 { Divider().padding(.leading, 62) }
            }
        }
        .padding(.vertical, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func legRow(_ leg: TravelLeg) -> some View {
        let (title, detail, time, day): (String, String, String, String) = switch leg {
        case .flight(let f):
            ("\(f.departure.city.isEmpty ? f.departure.iata : f.departure.city) → \(f.arrival.city.isEmpty ? f.arrival.iata : f.arrival.city)",
             [f.flightNumber, f.duration.hoursMinutes].filter { !$0.isEmpty }.joined(separator: " · "),
             f.departure.best.time(in: f.departure.timeZone), f.departure.best.weekdayDayMonth(in: f.departure.timeZone))
        case .drive(let d):
            (d.title,
             [d.from.name.isEmpty ? nil : "From \(d.from.name)", d.summaryText.isEmpty ? nil : d.summaryText]
                .compactMap { $0 }.joined(separator: " · "),
             d.departure.time(in: trip.timeZone), d.departure.weekdayDayMonth(in: trip.timeZone))
        }
        return HStack(spacing: 12) {
            CircleIcon(symbol: leg.isFlight ? "airplane" : "car.fill", color: leg.isFlight ? .flight : .drive, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(time).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(day).font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// A flight or drive from the list, with its full card and actions.
    private func legSheet(_ leg: TravelLeg) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if case .flight(let flight) = leg { RouteMapCard(flights: [flight]) }
                    fullCard(leg, inSheet: true)
                    VStack(spacing: 0) {
                        switch leg {
                        case .flight(let flight):
                            sheetAction("Refresh Status", "arrow.clockwise") { Task { await refresh(flight) } }
                        case .drive(let drive):
                            sheetAction("Directions", "arrow.triangle.turn.up.right.diamond") { DriveService.openDirections(to: drive.to) }
                            Divider().padding(.leading, 52)
                            sheetAction("Edit Drive", "pencil") { editingDriveInSheet = drive }
                        }
                        Divider().padding(.leading, 52)
                        sheetAction(leg.isFlight ? "Remove Flight" : "Remove Drive", "trash", role: .destructive) { remove(leg) }
                    }
                    .padding(.vertical, 4)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                }
                .padding(Metrics.gutter)
            }
            .background(Color.appBackground)
            .navigationTitle(leg.isFlight ? "Flight" : "Drive")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { openedLeg = nil }
                }
            }
            .sheet(item: $editingDriveInSheet) { DriveLegEditor(trip: trip, leg: $0) }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 520)
        #endif
    }

    private func sheetAction(_ title: String, _ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24)
                Text(title)
                Spacer()
            }
            .font(.body)
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func remove(_ leg: TravelLeg) {
        if openedLeg?.id == leg.id { openedLeg = nil }
        switch leg {
        case .flight(let flight):
            context.delete(flight); try? context.save()
            Task { await FlightActivities.syncAll() }
        case .drive(let drive):
            context.delete(drive); try? context.save()
            Task { await DriveActivities.syncAll() }
        }
    }

    /// Start Drive is on every drive on iPhone, whenever it is: plans change, and tapping it just
    /// means "I'm driving there now". The Mac has no live ETA, so it keeps the Directions button only.
    private static var offersStartDrive: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Today: what it does. Another day: when to use it.
    private func startDriveHint(_ leg: DriveLeg) -> String {
        if trip.calendar.isDate(leg.departure, inSameDayAs: .now) || leg.departure < .now {
            return "Opens Maps and keeps your ETA live on the Lock Screen and CarPlay"
        }
        return "Tap when you head out on \(leg.departure.weekdayDayMonth(in: trip.timeZone)) for Maps and a live ETA"
    }

    /// Bottom row of a drive card: "Start Drive" (Maps plus a live ETA on the Lock Screen and
    /// CarPlay), or the live ETA while the drive is under way.
    @ViewBuilder
    private func driveLiveRow(_ leg: DriveLeg) -> some View {
        let tracker = DriveTracker.shared
        if tracker.isTracking(leg.id) {
            HStack(spacing: 8) {
                Image(systemName: tracker.status == .denied ? "location.slash.fill" : "location.fill")
                    .foregroundStyle(tracker.status == .denied ? Color.orange : Color.green)
                VStack(alignment: .leading, spacing: 1) {
                    switch tracker.status {
                    case .denied:
                        Text("Location is off for TravelHub").font(.subheadline.weight(.medium))
                        Text("Turn it on in Settings to see a live ETA.").font(.caption).foregroundStyle(.secondary)
                    case .live:
                        if let live = tracker.live {
                            Text("ETA \(live.eta.time(in: trip.timeZone)) · \(DriveService.durationText(live.remainingMinutes)) left")
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                            let late = tracker.target.map { live.minutesLate(for: $0) } ?? 0
                            Text(late >= 5 ? "\(late) min behind plan" : "On time")
                                .font(.caption).foregroundStyle(late >= 5 ? Color.orange : .secondary)
                        }
                    default:
                        Text("Finding your location…").font(.subheadline.weight(.medium))
                    }
                }
                Spacer()
                Button("End") { tracker.stop(); trackingRevision += 1 }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        } else {
            Button {
                DriveService.startDrive(leg)
                trackingRevision += 1
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "car.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Start Drive").font(.subheadline.weight(.semibold))
                        Text(startDriveHint(leg))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.drive)
        }
    }

    @ViewBuilder
    private var staySection: some View {
        if !trip.sortedStays.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Stay") { SeeAllButton(title: "Add") { showingAddStay = true } }
                LazyVGrid(columns: columns(for: trip.sortedStays.count), spacing: 12) {
                    ForEach(trip.sortedStays) { stay in
                        StayCardView(stay: stay, tz: trip.timeZone)
                            .onTapGesture { editingStay = stay }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editingStay = stay }
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    context.delete(stay); try? context.save()
                                }
                            }
                    }
                }
            }
        }
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Weather")
            WeatherStripView(forecast: forecast, loaded: forecastLoaded, tz: trip.timeZone)
        }
    }

    private var goodToKnowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Good to Know")
            LocalInfoView(trip: trip, exchangeRate: exchangeRate)
        }
    }

    @ViewBuilder
    private var upNextSection: some View {
        let reference = max(Date.now, trip.startDate)
        let next = Array((trip.planItems ?? []).filter { $0.isScheduled && $0.end >= reference }.sorted { $0.start < $1.start }.prefix(4))
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Itinerary") { SeeAllButton(title: "View All") { model.tripSection = .plan } }
            VStack(spacing: 0) {
                if next.isEmpty {
                    HStack {
                        Text("Nothing scheduled yet. Save places in Discover, then give them a time.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(Metrics.gutter)
                }
                ForEach(Array(next.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        CategoryIcon(category: item.category, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(item.start.weekdayDayMonth(in: trip.timeZone)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(item.start.time(in: trip.timeZone)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 11)
                    if index < next.count - 1 { Divider().padding(.leading, 58) }
                }
            }
            .padding(.vertical, 4)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    // MARK: Data

    private func loadInfo() async {
        forecast = (try? await WeatherService().forecast(for: trip)) ?? []
        forecastLoaded = true
        let home = Locale.current.currency?.identifier ?? "USD"
        if let dest = CurrencyService.currency(forCountry: trip.countryCode), dest != home {
            exchangeRate = try? await CurrencyService().rate(from: home, to: dest)
        }
    }

    private func addToCalendar() {
        Task {
            do {
                let added = try await CalendarExport.add(trip)
                calendarMessage = added == 0 ? "Everything in \(trip.displayName) is already in your calendar."
                    : "Added \(added) event\(added == 1 ? "" : "s") to your calendar: flights, where you're staying and your plans."
            } catch {
                calendarMessage = error.localizedDescription
            }
        }
    }

    /// Bottom row of a flight card: "Live on Lock Screen · Stop", or a button to start tracking.
    private func liveRow(_ flight: FlightSegment) -> some View {
        HStack(spacing: 8) {
            if FlightActivities.isTracking(flight) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Live on Lock Screen").font(.subheadline.weight(.medium))
                Spacer()
                Button("Stop") {
                    Task { await FlightActivities.stop(flight); trackingRevision += 1 }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            } else {
                Button {
                    FlightActivities.start(flight)
                    trackingRevision += 1
                } label: {
                    HStack {
                        Label("Track Live on Lock Screen", systemImage: "livephoto")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline.weight(.medium))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.flight)
            }
        }
    }

    /// Start or stop the flight's Live Activity (Lock Screen and Dynamic Island).
    private func trackButton(_ flight: FlightSegment) -> some View {
        let tracking = FlightActivities.isTracking(flight)
        return Button(tracking ? "Stop Live Tracking" : "Track Live on Lock Screen",
                      systemImage: tracking ? "stop.circle" : "livephoto") {
            Task {
                if tracking { await FlightActivities.stop(flight) } else { FlightActivities.start(flight) }
                trackingRevision += 1
            }
        }
    }

    private func refreshAll() async {
        for flight in trip.sortedFlights { await refresh(flight) }
        await loadInfo()
    }

    private func refresh(_ flight: FlightSegment, quietly: Bool = false) async {
        do {
            try await FlightService().refresh(flight)
            try? context.save()
            await FlightActivities.syncAll()
        } catch {
            if !quietly { refreshError = error.localizedDescription }
        }
    }

    /// While the trip is on screen, refreshes flights that are about to leave, in the air, or just
    /// landed every 10 minutes. Each refresh is one AeroDataBox request, so it stays off otherwise.
    private func keepLiveFlightsFresh() async {
        while !Task.isCancelled {
            if APIKeys.aeroDataBox != nil {
                for flight in trip.sortedFlights where FlightProgress.isInLiveWindow(flight) && Date.now.timeIntervalSince(flight.lastUpdated) > 10 * 60 {
                    await refresh(flight, quietly: true)
                }
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

}

/// A flight or a drive: the ways of getting between places on a trip.
enum TravelLeg: Identifiable {
    case flight(FlightSegment)
    case drive(DriveLeg)

    var id: UUID {
        switch self {
        case .flight(let f): f.id
        case .drive(let d): d.id
        }
    }

    var isFlight: Bool { if case .flight = self { true } else { false } }

    var start: Date {
        switch self {
        case .flight(let f): f.departure.best
        case .drive(let d): d.departure
        }
    }

    /// When it's over. A drive whose route hasn't been looked up yet counts as an hour long.
    var end: Date {
        switch self {
        case .flight(let f): f.arrival.best
        case .drive(let d): max(d.arrival, d.departure.addingTimeInterval(3600))
        }
    }
}

extension Trip {
    /// Flights and drives together, in the order they happen.
    var travelLegs: [TravelLeg] {
        (sortedFlights.map(TravelLeg.flight) + sortedDrives.map(TravelLeg.drive)).sorted { $0.start < $1.start }
    }
}
