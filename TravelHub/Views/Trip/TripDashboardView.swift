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
                    QuickAction(title: "Activity", symbol: "plus") { addingActivity = true }
                    QuickAction(title: "Discover", symbol: "mappin.and.ellipse") { model.tripSection = .discover }
                }
                .padding(.top, -6)

                VStack(alignment: .leading, spacing: 28) {
                    flightsSection
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
