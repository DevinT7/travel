import SwiftUI
import SwiftData
import MapKit

/// The home screen on iPhone: the trip happening now (or the next one) as a big card, then the
/// rest of the upcoming trips and past trips. Tapping a trip opens it.
struct TripsListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    let trips: [Trip]
    @State private var tripToDelete: Trip?

    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }
    private var upcoming: [Trip] { trips.filter { $0.endDate >= startOfToday } }
    private var past: [Trip] { trips.filter { $0.endDate < startOfToday }.reversed() }
    /// The ongoing trip, or else the soonest upcoming one.
    private var featured: Trip? { upcoming.first(where: \.isOngoing) ?? upcoming.first }
    private var otherUpcoming: [Trip] { upcoming.filter { $0.id != featured?.id } }

    var body: some View {
        if trips.isEmpty {
            WelcomeView()
                .navigationTitle("Trips")
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let featured {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(featured.isOngoing ? "Now" : "Next Trip")
                        FeaturedTripCard(trip: featured) { model.open(featured) } onPlan: {
                            model.open(featured, section: .plan)
                        } onDiscover: {
                            model.open(featured, section: .discover)
                        }
                        .contextMenu { deleteButton(featured) }
                    }
                }
                if !otherUpcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Upcoming")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                            ForEach(otherUpcoming) { photoCard($0) }
                        }
                    }
                }
                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Past Trips")
                        VStack(spacing: 0) {
                            ForEach(Array(past.enumerated()), id: \.element.id) { index, trip in
                                TripRow(trip: trip) { model.open(trip) }
                                    .contextMenu { deleteButton(trip) }
                                if index < past.count - 1 { Divider().padding(.leading, 84) }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 4)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Trips")
        .largeTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Trip", systemImage: "plus") { model.isPresentingNewTrip = true }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { model.isPresentingSettings = true }
            }
            #endif
        }
        .deleteTripDialog($tripToDelete)
    }

    private func deleteButton(_ trip: Trip) -> some View {
        Button("Delete Trip", systemImage: "trash", role: .destructive) { tripToDelete = trip }
    }

    /// Photo card for another upcoming trip.
    private func photoCard(_ trip: Trip) -> some View {
        Button { model.open(trip) } label: {
            TripCover(trip: trip)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.75), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.displayName).font(.title3.bold())
                        Text("\(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone)) · \(trip.countdownText)")
                            .font(.subheadline.weight(.medium)).opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .padding(14)
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { deleteButton(trip) }
    }
}

/// The big card at the top of the home screen: photo, name, countdown, the next thing on the
/// trip, and shortcuts into Plan and Discover.
struct FeaturedTripCard: View {
    let trip: Trip
    let onOpen: () -> Void
    let onPlan: () -> Void
    let onDiscover: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                TripCover(trip: trip)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.8), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.countdownText.uppercased())
                                .font(.caption.weight(.bold)).tracking(0.5)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                            Text(trip.displayName).font(.largeTitle.bold()).lineLimit(2)
                            Text(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone))
                                .font(.subheadline.weight(.medium)).opacity(0.9)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 6)
                        .padding(16)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let next = trip.nextUp {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        CircleIcon(symbol: next.symbol, color: .accentColor, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Up next").font(.caption).foregroundStyle(.secondary)
                            Text(next.text).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, Metrics.gutter)
            }

            HStack(spacing: 0) {
                shortcut("Plan", symbol: "calendar.day.timeline.left", action: onPlan)
                Divider().frame(height: 22)
                shortcut("Discover", symbol: "mappin.and.ellipse", action: onDiscover)
            }
            .padding(.vertical, 4)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func shortcut(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}

/// Compact row with a photo thumbnail, used for past trips and in the iPad / Mac sidebar.
struct TripRow: View {
    let trip: Trip
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { content.padding(.horizontal, Metrics.gutter).padding(.vertical, 10).contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            TripCover(trip: trip)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone)).font(.caption).foregroundStyle(.secondary)
                Text(trip.endDate < Calendar.current.startOfDay(for: .now) ? summary : trip.countdownText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }

    private var summary: String {
        let f = trip.flights?.count ?? 0, p = trip.planItems?.count ?? 0
        return "\(f) flight\(f == 1 ? "" : "s") · \(p) plan item\(p == 1 ? "" : "s")"
    }
}

/// The trip list in the iPad / Mac sidebar.
struct TripsSidebar: View {
    @Environment(AppModel.self) private var model
    let trips: [Trip]
    @State private var tripToDelete: Trip?

    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedTripID) {
            let upcoming = trips.filter { $0.endDate >= startOfToday }
            let past = trips.filter { $0.endDate < startOfToday }.reversed()
            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { trip in row(trip) }
                }
            }
            if !past.isEmpty {
                Section("Past Trips") {
                    ForEach(Array(past)) { trip in row(trip) }
                }
            }
        }
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Trip", systemImage: "plus") { model.isPresentingNewTrip = true }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { model.isPresentingSettings = true }
            }
            #endif
        }
        .onChange(of: model.selectedTripID) { model.tripSection = .overview }
        .deleteTripDialog($tripToDelete)
    }

    private func row(_ trip: Trip) -> some View {
        TripRow(trip: trip)
            .padding(.vertical, 2)
            .tag(trip.id)
            .contextMenu {
                Button("Delete Trip", systemImage: "trash", role: .destructive) { tripToDelete = trip }
            }
    }
}

extension View {
    /// "Delete Paris?" confirmation shared by the trip list and sidebar.
    func deleteTripDialog(_ trip: Binding<Trip?>) -> some View { modifier(DeleteTripDialog(trip: trip)) }
}

private struct DeleteTripDialog: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Binding var trip: Trip?

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete \(trip?.displayName ?? "trip")?", isPresented: .init(
            get: { trip != nil }, set: { if !$0 { trip = nil } }), titleVisibility: .visible
        ) {
            Button("Delete Trip", role: .destructive) {
                guard let doomed = trip else { return }
                if model.selectedTripID == doomed.id { model.selectedTripID = nil }
                model.path.removeAll { $0 == doomed.id }
                context.delete(doomed)
                try? context.save()
                Task { await FlightActivities.syncAll() }
            }
        } message: {
            Text("Its flights, stay and plan will be removed. This can't be undone.")
        }
    }
}
