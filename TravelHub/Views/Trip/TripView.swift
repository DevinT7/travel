import SwiftUI

/// iPhone: an open trip, with Overview, Plan and Discover in the tab bar at the bottom and a
/// Trips button at the top left to go back to the list.
struct TripTabs: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tripSection) {
            Tab("Overview", systemImage: "airplane.departure", value: TripSection.overview) {
                NavigationStack { TripDashboardView(trip: trip).backToTrips() }
            }
            Tab("Plan", systemImage: "calendar.day.timeline.left", value: TripSection.plan) {
                NavigationStack { PlanView(trip: trip).backToTrips() }
            }
            Tab("Discover", systemImage: "sparkle.magnifyingglass", value: TripSection.discover) {
                NavigationStack { DiscoverView(trip: trip).backToTrips() }
            }
        }
        .onAppear { model.selectedTripID = trip.id }
    }
}

private struct BackToTrips: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button { model.path = [] } label: {
                    Label("Trips", systemImage: "chevron.backward")
                }
                .accessibilityLabel("All trips")
            }
            #endif
        }
    }
}

extension View {
    /// The "‹ Trips" button that leaves an open trip on iPhone.
    func backToTrips() -> some View { modifier(BackToTrips()) }
}

/// iPad and Mac: one trip next to the sidebar, with Overview, Plan and Discover switched from the
/// control in the toolbar.
struct TripView: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.tripSection {
            case .overview: TripDashboardView(trip: trip)
            case .plan: PlanView(trip: trip)
            case .discover: DiscoverView(trip: trip)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $model.tripSection) {
                    ForEach(TripSection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .onAppear { model.selectedTripID = trip.id }
    }
}

extension Trip {
    /// "Leaves in 9 days", "Leaves tomorrow", "Day 3 of 7", "Completed".
    var countdownText: String {
        let cal = calendar
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        if today < start {
            let days = cal.dateComponents([.day], from: today, to: start).day ?? 0
            return days == 1 ? "Leaves tomorrow" : "Leaves in \(days) days"
        }
        if today <= end {
            let day = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
            return "Day \(day) of \(days.count)"
        }
        return "Completed"
    }

    var isOngoing: Bool {
        let cal = calendar
        let today = cal.startOfDay(for: .now)
        return cal.startOfDay(for: startDate) <= today && today <= cal.startOfDay(for: endDate)
    }

    /// The next thing on the trip, for the home card: a flight, a check-in or a plan.
    var nextUp: (symbol: String, text: String)? {
        let now = Date.now
        var items: [(Date, String, String)] = []
        if let f = sortedFlights.first(where: { $0.departure.best > now }) {
            let to = f.arrival.city.isEmpty ? f.arrival.iata : f.arrival.city
            items.append((f.departure.best, "airplane",
                          "\(f.flightNumber) to \(to) · \(f.departure.best.weekdayDayMonth(in: f.departure.timeZone)), \(f.departure.best.time(in: f.departure.timeZone))"))
        }
        if let s = sortedStays.first(where: { $0.checkIn > now }) {
            items.append((s.checkIn, "bed.double.fill", "Check in at \(s.name) · \(s.checkIn.weekdayDayMonth(in: timeZone))"))
        }
        if let p = (planItems ?? []).filter({ $0.isScheduled && $0.end > now }).min(by: { $0.start < $1.start }) {
            items.append((p.start, p.category.symbol, "\(p.title) · \(p.start.weekdayDayMonth(in: timeZone)), \(p.start.time(in: timeZone))"))
        }
        return items.min(by: { $0.0 < $1.0 }).map { ($0.1, $0.2) }
    }
}
