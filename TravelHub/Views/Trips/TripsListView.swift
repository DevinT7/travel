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
        List {
            if trips.isEmpty {
                EmptyStateView(symbol: "suitcase", title: "No trips yet",
                               message: "Create a trip to start adding flights and plans.",
                               actionTitle: "New Trip") { model.isPresentingNewTrip = true }
                    .listRowBackground(Color.clear)
            }
            if !upcoming.isEmpty {
                Section("Upcoming") { ForEach(upcoming) { row($0) } }
            }
            if !past.isEmpty {
                Section("Past") { ForEach(past) { row($0) } }
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

    private func row(_ trip: Trip) -> some View {
        let isCurrent = trip.id == model.currentTrip(from: trips)?.id
        return Button {
            model.selectedTripID = trip.id
            model.selectedTab = .trip
        } label: {
            HStack(spacing: 14) {
                Map(initialPosition: .region(MKCoordinateRegion(center: trip.coordinate,
                                                                span: .init(latitudeDelta: 0.4, longitudeDelta: 0.4))),
                    interactionModes: [])
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(trip.displayName).font(.headline)
                        if trip.isSample { StatusPill(text: "Sample", color: .orange) }
                    }
                    Text(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(summary(trip)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { tripToDelete = trip }
        }
        .contextMenu {
            Button("Delete Trip", systemImage: "trash", role: .destructive) { tripToDelete = trip }
        }
    }

    private func summary(_ trip: Trip) -> String {
        let f = trip.flights?.count ?? 0, p = trip.planItems?.count ?? 0
        return "\(f) flight\(f == 1 ? "" : "s") · \(p) plan item\(p == 1 ? "" : "s")"
    }
}
