import SwiftUI
import MapKit

/// Choose where Discover looks: the trip's destination, another stop on the trip, a nearby city,
/// or any city you search for.
struct ExplorePlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let current: ExplorePlace?
    let onPick: (ExplorePlace?) -> Void

    @State private var search: LocationSearch
    @State private var nearby: [ExplorePlace] = []
    @State private var isLoadingNearby = true
    @State private var resolving: String?

    init(trip: Trip, current: ExplorePlace?, onPick: @escaping (ExplorePlace?) -> Void) {
        self.trip = trip
        self.current = current
        self.onPick = onPick
        _search = State(initialValue: LocationSearch(kind: .city, near: MKCoordinateRegion(
            center: trip.coordinate, latitudinalMeters: 600_000, longitudinalMeters: 600_000)))
    }

    var body: some View {
        NavigationStack {
            List {
                if !search.query.isEmpty {
                    Section("Results") {
                        ForEach(search.results.prefix(8), id: \.self) { result in
                            Button {
                                Task { await pick(result) }
                            } label: {
                                row(result.title, result.subtitle, symbol: "magnifyingglass", isBusy: resolving == result.title)
                            }
                        }
                    }
                } else {
                    Section {
                        Button {
                            choose(nil)
                        } label: {
                            row(trip.destinationName, "Your trip's destination", symbol: "suitcase.fill", isSelected: current == nil)
                        }
                        ForEach(ExplorePlaces.otherStops(on: trip)) { place in
                            placeButton(place, detail: "Also on this trip", symbol: "airplane.arrival")
                        }
                    } header: {
                        Text("This trip")
                    }

                    let recents = ExplorePlaces.recents(for: trip)
                    if !recents.isEmpty {
                        Section("Recently explored") {
                            ForEach(recents) { place in
                                placeButton(place, detail: away(place), symbol: "clock.arrow.circlepath")
                            }
                        }
                    }

                    Section {
                        ForEach(nearby.prefix(12)) { place in
                            placeButton(place, detail: [away(place), place.subtitle].filter { !$0.isEmpty }.joined(separator: " · "),
                                        symbol: "mappin.and.ellipse")
                        }
                        if isLoadingNearby {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text("Finding places nearby…").foregroundStyle(.secondary)
                            }
                        } else if nearby.isEmpty {
                            Text("Search for a city above.").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Near \(trip.destinationName)")
                    } footer: {
                        Text("Things you save from another city go into this trip's Ideas, so you can fit them into your plan.")
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .searchable(text: $search.query, prompt: "Search any city")
            .navigationTitle("Explore")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                await ExplorePlaces.nearby(trip.coordinate, excluding: trip.destinationName) { nearby = $0 }
                isLoadingNearby = false
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private func placeButton(_ place: ExplorePlace, detail: String, symbol: String) -> some View {
        Button {
            Task { await choose(place) }
        } label: {
            row(place.name, detail, symbol: symbol, isSelected: current?.name == place.name, isBusy: resolving == place.name)
        }
    }

    private func row(_ title: String, _ detail: String, symbol: String, isSelected: Bool = false, isBusy: Bool = false) -> some View {
        HStack(spacing: 12) {
            CircleIcon(symbol: symbol, color: .accentColor, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            else if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
        }
        .contentShape(Rectangle())
    }

    private func away(_ place: ExplorePlace) -> String {
        distanceText(place.distance(from: trip.coordinate)).map { "\($0) away" } ?? ""
    }

    private func choose(_ place: ExplorePlace?) {
        onPick(place)
        dismiss()
    }

    private func choose(_ place: ExplorePlace) async {
        resolving = place.name
        let exact = await ExplorePlaces.resolved(place)
        resolving = nil
        ExplorePlaces.remember(exact, for: trip)
        choose(exact as ExplorePlace?)
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        resolving = completion.title
        defer { resolving = nil }
        guard let place = try? await search.resolve(completion) else { return }
        let explore = ExplorePlace(name: place.name, subtitle: place.address, coordinate: place.coordinate)
        ExplorePlaces.remember(explore, for: trip)
        choose(explore as ExplorePlace?)
    }
}
