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
    @State private var refreshError: String?

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TripHeroView(trip: trip)

                VStack(alignment: .leading, spacing: 28) {
                    if trip.isSample {
                        NoticeBanner(symbol: "sparkles",
                                     message: "This is a sample trip with made-up flights. Create your own trip to look up real flights.",
                                     actionTitle: "New Trip") { model.isPresentingNewTrip = true }
                    }
                    flightsSection
                    staySection
                    weatherSection
                    goodToKnowSection
                    upNextSection
                }
                .padding(.horizontal, Metrics.gutter)
                .readableWidth()
            }
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle(trip.displayName)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Flight", systemImage: "airplane") { showingAddFlight = true }
                    Button("Add Stay", systemImage: "bed.double") { showingAddStay = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .refreshable { await refreshAll() }
        .task(id: trip.id) { await loadInfo() }
        .sheet(isPresented: $showingAddFlight) { AddFlightView(trip: trip) }
        .sheet(isPresented: $showingAddStay) { StayEditorView(trip: trip, stay: nil) }
        .sheet(item: $editingStay) { StayEditorView(trip: trip, stay: $0) }
        .alert("Couldn't refresh flights", isPresented: .init(get: { refreshError != nil }, set: { if !$0 { refreshError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(refreshError ?? "") }
    }

    // MARK: Sections

    private var flightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Flights") {
                Button("Add", systemImage: "plus") { showingAddFlight = true }.labelStyle(.titleAndIcon)
            }
            if trip.sortedFlights.isEmpty {
                addPrompt(symbol: "airplane", title: "Add your flight",
                          text: "Enter a flight number to get times, terminals, gates and a route map.") { showingAddFlight = true }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
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

    private var staySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Where you're staying") {
                Button("Add", systemImage: "plus") { showingAddStay = true }.labelStyle(.titleAndIcon)
            }
            if trip.sortedStays.isEmpty {
                addPrompt(symbol: "bed.double.fill", title: "Add your hotel or rental",
                          text: "It shows on your plan's map and as the start of each day.") { showingAddStay = true }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
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
            SectionHeader("Weather in \(trip.destinationName)")
            WeatherStripView(forecast: forecast, loaded: forecastLoaded, tz: trip.timeZone)
        }
    }

    private var goodToKnowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Good to know")
            LocalInfoView(trip: trip, exchangeRate: exchangeRate)
        }
    }

    @ViewBuilder
    private var upNextSection: some View {
        let reference = max(Date.now, trip.startDate)
        let next = (trip.planItems ?? []).filter { $0.isScheduled && $0.end >= reference }.sorted { $0.start < $1.start }.prefix(4)
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Up next") {
                    Button("Full plan") { model.selectedTab = .plan }
                }
                VStack(spacing: 0) {
                    ForEach(Array(next.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 14) {
                            CategoryIcon(category: item.category, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline).lineLimit(1)
                                Text("\(item.start.weekdayDayMonth(in: trip.timeZone)) · \(item.start.time(in: trip.timeZone))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        if index < next.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .card(padding: 14)
            }
        }
    }

    private func addPrompt(symbol: String, title: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tint)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
