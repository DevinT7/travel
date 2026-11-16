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
                    flightsSection
                    drivesSection
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
        .alert("Couldn't refresh flights", isPresented: .init(get: { refreshError != nil }, set: { if !$0 { refreshError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(refreshError ?? "") }
    }

    // MARK: Sections

    @ViewBuilder
    private var flightsSection: some View {
        if !trip.sortedFlights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Flights") { SeeAllButton(title: "Add") { showingAddFlight = true } }
                RouteMapCard(trip: trip)
                LazyVGrid(columns: columns(for: trip.sortedFlights.count), spacing: 12) {
                    ForEach(trip.sortedFlights) { flight in
                        FlightCardView(flight: flight,
                                       footer: FlightActivities.canTrack(flight) ? AnyView(liveRow(flight)) : nil)
                            .contextMenu {
                                Button("Refresh Status", systemImage: "arrow.clockwise") {
                                    Task { await refresh(flight) }
                                }
                                if FlightActivities.canTrack(flight) {
                                    trackButton(flight)
                                }
                                Button("Remove Flight", systemImage: "trash", role: .destructive) {
                                    context.delete(flight); try? context.save()
                                    Task { await FlightActivities.syncAll() }
                                }
                            }
                        .id("\(flight.id)-\(trackingRevision)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var drivesSection: some View {
        let drives = trip.sortedDrives
        if !drives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Drives") { SeeAllButton(title: "Add") { showingAddDrive = true } }
                LazyVGrid(columns: columns(for: drives.count), spacing: 12) {
                    ForEach(drives) { leg in
                        DriveCardView(leg: leg, tz: trip.timeZone,
                                      footer: Self.offersStartDrive ? AnyView(driveLiveRow(leg)) : nil)
                            .contentShape(Rectangle())
                            .onTapGesture { editingDrive = leg }
                            .contextMenu {
                                Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                                    DriveService.openDirections(to: leg.to)
                                }
                                Button("Edit", systemImage: "pencil") { editingDrive = leg }
                                Button("Remove Drive", systemImage: "trash", role: .destructive) {
                                    context.delete(leg); try? context.save()
                                    Task { await DriveActivities.syncAll() }
                                }
                            }
                            .id("\(leg.id)-\(trackingRevision)")
                    }
                }
            }
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
