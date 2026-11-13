import SwiftUI
import SwiftData
import MapKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    var body: some View {
        @Bindable var model = model
        let trip = model.currentTrip(from: trips)

        TabView(selection: $model.selectedTab) {
            Tab("Trip", systemImage: "airplane.departure", value: AppTab.trip) {
                NavigationStack {
                    if let trip { TripDashboardView(trip: trip).tripTitleMenu(trips: trips) } else { welcome }
                }
            }
            Tab("Discover", systemImage: "sparkle.magnifyingglass", value: AppTab.discover) {
                NavigationStack {
                    if let trip { DiscoverView(trip: trip).id(trip.id).tripTitleMenu(trips: trips) } else { welcome }
                }
            }
            Tab("Plan", systemImage: "calendar.day.timeline.left", value: AppTab.plan) {
                NavigationStack {
                    if let trip { PlanView(trip: trip).id(trip.id).tripTitleMenu(trips: trips) } else { welcome }
                }
            }
            Tab("Trips", systemImage: "suitcase.fill", value: AppTab.trips) {
                NavigationStack { TripsListView(trips: trips) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(isPresented: $model.isPresentingNewTrip) {
            NewTripView { newTrip in model.selectedTripID = newTrip.id; model.selectedTab = .trip }
        }
        .sheet(isPresented: $model.isPresentingSettings) {
            NavigationStack { SettingsView() }
        }
    }

    private var welcome: some View {
        WelcomeView()
            .navigationTitle("TravelHub")
    }
}

/// Turns the navigation title into a menu for switching trips.
private struct TripTitleMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let trips: [Trip]

    func body(content: Content) -> some View {
        content.toolbarTitleMenu {
            ForEach(trips) { trip in
                Button {
                    model.selectedTripID = trip.id
                } label: {
                    Label("\(trip.displayName) · \(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone))",
                          systemImage: trip.id == model.currentTrip(from: trips)?.id ? "checkmark" : "suitcase")
                }
            }
            Divider()
            Button("New Trip…", systemImage: "plus") { model.isPresentingNewTrip = true }
        }
    }
}

extension View {
    func tripTitleMenu(trips: [Trip]) -> some View { modifier(TripTitleMenu(trips: trips)) }
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

                    Button("Explore a Sample Trip") {
                        let trip = SampleData.insertTokyoTrip(into: context)
                        model.selectedTripID = trip.id
                    }
                    .font(.body.weight(.semibold))
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
