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

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TripHeroView(trip: trip)
                    #if os(iOS)
                    .overlay(alignment: .topTrailing) {
                        TripSwitcherMenu {
                            Image(systemName: "suitcase")
                                .font(.body.weight(.medium))
                                .frame(width: 40, height: 40)
                                .background(.regularMaterial, in: Circle())
                        }
                        .padding(.trailing, Metrics.gutter)
                        .padding(.top, 8)
                    }
                    #endif

                HStack(spacing: 8) {
                    QuickAction(title: "Flight", symbol: "airplane") { showingAddFlight = true }
                    QuickAction(title: "Stay", symbol: "bed.double") { showingAddStay = true }
                    QuickAction(title: "Activity", symbol: "plus") { addingActivity = true }
                    QuickAction(title: "Discover", symbol: "mappin.and.ellipse") { model.selectedTab = .discover }
                }
                .padding(.top, -6)

                VStack(alignment: .leading, spacing: 28) {
                    if trip.isSample {
                        NoticeBanner(symbol: "sparkles",
                                     message: "This is a sample trip with made-up flights. Create your own to look up real ones.",
                                     actionTitle: "New Trip") { model.isPresentingNewTrip = true }
                    }
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
        .background(Color.appBackground)
        .navigationTitle(trip.displayName)
        .inlineTitle()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarFade()
        #else
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Flight", systemImage: "airplane") { showingAddFlight = true }
                    Button("Add Stay", systemImage: "bed.double") { showingAddStay = true }
                    Button("Add Activity", systemImage: "plus") { addingActivity = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        #endif
        .refreshable { await refreshAll() }
        .task(id: trip.id) { await loadInfo() }
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
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(trip.sortedFlights) { flight in
                        FlightCardView(flight: flight)
                            .contextMenu {
                                Button("Refresh Status", systemImage: "arrow.clockwise") {
                                    Task { await refresh(flight) }
                                }
                                .disabled(flight.isSample)
                                Button("Remove Flight", systemImage: "trash", role: .destructive) {
                                    context.delete(flight); try? context.save()
                                }
                            }
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
                LazyVGrid(columns: columns, spacing: 12) {
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
            SectionHeader("Itinerary") { SeeAllButton(title: "View All") { model.selectedTab = .plan } }
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

    private func refreshAll() async {
        for flight in trip.sortedFlights where !flight.isSample { await refresh(flight) }
        await loadInfo()
    }

    private func refresh(_ flight: FlightSegment) async {
        do {
            try await FlightService().refresh(flight)
            try? context.save()
        } catch {
            refreshError = error.localizedDescription
        }
    }
}
