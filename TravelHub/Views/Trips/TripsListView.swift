import SwiftUI
import SwiftData
import MapKit

struct TripsListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    let trips: [Trip]
    @State private var tripToDelete: Trip?

    private var upcoming: [Trip] { trips.filter { $0.endDate >= Calendar.current.startOfDay(for: .now) } }
    private var past: [Trip] { trips.filter { $0.endDate < Calendar.current.startOfDay(for: .now) }.reversed() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if trips.isEmpty {
                    EmptyStateView(symbol: "suitcase", title: "No trips yet",
                                   message: "Create a trip to start adding flights and plans.",
                                   actionTitle: "New Trip") { model.isPresentingNewTrip = true }
                }
                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Upcoming")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                            ForEach(upcoming) { photoCard($0) }
                        }
                    }
                }
                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Past Trips")
                        VStack(spacing: 0) {
                            ForEach(Array(past.enumerated()), id: \.element.id) { index, trip in
                                pastRow(trip)
                                if index < past.count - 1 { Divider().padding(.leading, 84) }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
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
        .confirmationDialog("Delete \(tripToDelete?.displayName ?? "trip")?", isPresented: .init(
            get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }), titleVisibility: .visible
        ) {
            Button("Delete Trip", role: .destructive) {
                if let trip = tripToDelete {
                    if model.selectedTripID == trip.id { model.selectedTripID = nil }
                    context.delete(trip)
                    try? context.save()
                }
            }
        } message: {
            Text("Its flights, stay and plan will be removed. This can't be undone.")
        }
    }

    private func open(_ trip: Trip) {
        model.selectedTripID = trip.id
        model.selectedTab = .trip
    }

    /// Tall photo card for an upcoming trip.
    private func photoCard(_ trip: Trip) -> some View {
        let isCurrent = trip.id == model.currentTrip(from: trips)?.id
        return Button { open(trip) } label: {
            TripCover(trip: trip)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.75), location: 1)], startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.displayName).font(.title2.bold())
                        Text("\(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone)) · \(countdown(trip))")
                            .font(.subheadline.weight(.medium)).opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .padding(16)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .accessibilityLabel("Selected")
                        }
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Trip", systemImage: "trash", role: .destructive) { tripToDelete = trip }
        }
    }

    /// Compact row with a photo thumbnail for a past trip.
    private func pastRow(_ trip: Trip) -> some View {
        Button { open(trip) } label: {
            HStack(spacing: 12) {
                TripCover(trip: trip)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.displayName).font(.subheadline.weight(.semibold))
                    Text(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone)).font(.caption).foregroundStyle(.secondary)
                    Text(summary(trip)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Trip", systemImage: "trash", role: .destructive) { tripToDelete = trip }
        }
    }

    private func countdown(_ trip: Trip) -> String {
        let cal = trip.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: trip.startDate)).day ?? 0
        if days > 1 { return "in \(days) days" }
        if days == 1 { return "tomorrow" }
        return "now"
    }

    private func summary(_ trip: Trip) -> String {
        let f = trip.flights?.count ?? 0, p = trip.planItems?.count ?? 0
        return "\(f) flight\(f == 1 ? "" : "s") · \(p) plan item\(p == 1 ? "" : "s")"
    }
}
