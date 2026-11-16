import SwiftUI
import Combine
import SwiftData
import MapKit

/// Trips first: the app opens on the list of trips, and a trip opens into its own page with
/// Overview, Plan and Discover. iPhone pushes the trip; iPad and Mac show trips in a sidebar.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var didAutoOpen = false

    private var usesSidebar: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if usesSidebar {
                NavigationSplitView {
                    TripsSidebar(trips: trips)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                } detail: {
                    NavigationStack {
                        if let trip = trips.first(where: { $0.id == model.selectedTripID }) {
                            TripView(trip: trip).id(trip.id)
                        } else if trips.isEmpty {
                            WelcomeView()
                        } else {
                            EmptyStateView(symbol: "suitcase", title: "Pick a trip",
                                           message: "Choose a trip from the list, or create a new one.",
                                           actionTitle: "New Trip") { model.isPresentingNewTrip = true }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.appBackground)
                        }
                    }
                }
            } else {
                // iPhone: the Trips list, or an open trip with its own tab bar at the bottom.
                ZStack {
                    if let id = model.path.first, let trip = trips.first(where: { $0.id == id }) {
                        TripTabs(trip: trip)
                            .id(trip.id)
                            .transition(.opacity)
                    } else {
                        NavigationStack { TripsListView(trips: trips) }
                            .transition(.opacity)
                    }
                }
                .animation(.snappy(duration: 0.3), value: model.path)
            }
        }
        .task {
            removeLegacyDemoData()
            NotificationRouter.shared.openTrip = { [model] id in model.open(tripID: id, section: .plan) }
        }
        // Once the trips have loaded: open a trip that's happening today, or pick one for the sidebar.
        .task(id: trips.isEmpty) {
            if !didAutoOpen, !trips.isEmpty {
                didAutoOpen = true
                if usesSidebar, model.selectedTripID == nil || !trips.contains(where: { $0.id == model.selectedTripID }) {
                    model.selectedTripID = model.currentTrip(from: trips)?.id
                }
                model.openOngoingTrip(from: trips)
            }
        }
        // Deleting a drive or flight (or the trip it's in) ends its Live Activity right away.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            Task {
                await DriveActivities.endRemoved()
                await FlightActivities.endRemoved()
            }
            LeaveReminders.scheduleSoon()
        }
        // Keep flight Live Activities current, and start one for a flight leaving soon.
        .task(id: scenePhase) {
            switch scenePhase {
            case .active:
                await FlightActivities.syncAll()
                await DriveActivities.syncAll()
                FlightBackgroundRefresh.schedule()
                LeaveReminders.scheduleSoon()
            case .background: FlightBackgroundRefresh.schedule()
            default: break
            }
        }
        #if DEBUG && os(macOS)
        .task { await DebugSnapshot.runIfRequested(model: model, trips: trips) }
        #endif
        #if DEBUG && os(iOS)
        .task {
            await DebugFlightDemo.runIfRequested(context: context)
            if let demo = await DebugDriveDemo.runIfRequested(context: context) {
                model.open(demo, section: .plan)
            }
            if UserDefaults.standard.string(forKey: "DemoFlight") != nil,
               let id = UserDefaults.standard.string(forKey: "selectedTripID").flatMap(UUID.init(uuidString:)) {
                model.selectedTripID = id
                model.tripSection = .overview
                model.path = [id]
            }
        }
        #endif
        .sheet(isPresented: $model.isPresentingNewTrip, onDismiss: { model.newTripConfirmationText = nil }) {
            NewTripView(initialText: model.newTripConfirmationText) { model.open($0) }
        }
        .sheet(isPresented: $model.isPresentingSettings) {
            NavigationStack { SettingsView() }
        }
    }

    /// Deletes the demo Tokyo trip and its made-up flights from earlier versions.
    private func removeLegacyDemoData() {
        let demos = trips.filter(\.isSample)
        let strayFlights = (try? context.fetch(FetchDescriptor<FlightSegment>(predicate: #Predicate { $0.isSample }))) ?? []
        guard !demos.isEmpty || !strayFlights.isEmpty else { return }
        demos.forEach(context.delete)
        strayFlights.forEach(context.delete)
        try? context.save()
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: .init(latitude: 28, longitude: 20), distance: 17_500_000)),
                    interactionModes: [])
                    .mapStyle(.imagery(elevation: .realistic))
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())
                    .shadow(color: .blue.opacity(0.35), radius: 40)
                    .allowsHitTesting(false)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text("All your travel, in one place").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("Add your flights and hotel, find things to do, and build a day-by-day plan.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button {
                        model.isPresentingNewTrip = true
                    } label: {
                        Text("Plan a Trip").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)

                    // Already booked: start the trip straight from the airline's confirmation.
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.joined(separator: "\n")
                        Task { @MainActor in
                            model.newTripConfirmationText = text
                            model.isPresentingNewTrip = true
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    Text("Already booked? Copy your flight confirmation and paste it to fill in the city, dates and flights.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 360)

                VStack(spacing: 0) {
                    feature("airplane", .blue, "Flights & stays", "Look up a flight number for times, gates and a route map.")
                    Divider().padding(.leading, 58)
                    feature("mappin.and.ellipse", .orange, "Discover", "Sights, food, nightlife and events near where you're going.")
                    Divider().padding(.leading, 58)
                    feature("calendar", .red, "Plan", "A day-by-day itinerary with travel times and a map.")
                }
                .padding(.vertical, 4)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .frame(maxWidth: 460)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            CircleIcon(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
    }
}
