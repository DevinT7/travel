import SwiftUI
import SwiftData

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
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 96, height: 96)
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Your whole trip, in one place").font(.title.bold()).multilineTextAlignment(.center)
                    Text("Add your flights, find things to do, and build a day-by-day plan.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 18) {
                    feature("airplane", "Flights & stays", "Look up a flight number for times, gates and a route map.")
                    feature("sparkle.magnifyingglass", "Discover", "Sights, food, nightlife and events near where you're going.")
                    feature("calendar.day.timeline.left", "Plan", "A day-by-day timeline with travel times and a map.")
                }
                .card(padding: 22)
                .frame(maxWidth: 460)

                VStack(spacing: 12) {
                    Button {
                        model.isPresentingNewTrip = true
                    } label: {
                        Text("Plan a Trip").frame(maxWidth: 320)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Explore a sample trip") {
                        let trip = SampleData.insertTokyoTrip(into: context)
                        model.selectedTripID = trip.id
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
