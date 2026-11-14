import SwiftUI
import SwiftData
import MapKit

// MARK: - Card

/// A drive on the Overview: route map, leave and arrive times, and a Directions button that hands
/// off to Apple Maps.
struct DriveCardView: View {
    let leg: DriveLeg
    let tz: TimeZone
    var footer: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CircleIcon(symbol: "car.fill", color: .drive, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.title).font(.headline).lineLimit(1)
                    Text(leg.from.name.isEmpty ? leg.to.address : "From \(leg.from.name)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                DirectionsButton(place: leg.to)
            }
            DriveRouteMap(leg: leg, interactive: false)
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(alignment: .top) {
                timeBlock("Leave", leg.departure)
                Spacer()
                Text(leg.summaryText.isEmpty ? "Route not found" : leg.summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.insetBackground, in: Capsule())
                    .padding(.top, 8)
                Spacer()
                timeBlock("Arrive", leg.arrival, trailing: true)
            }
            let extras = [leg.vehicle, leg.notes].filter { !$0.isEmpty }
            if !extras.isEmpty {
                Label(extras.joined(separator: " · "), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let footer {
                Divider()
                footer
            }
        }
        .card()
    }

    private func timeBlock(_ label: String, _ date: Date, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(date.time(in: tz)).font(.title3.weight(.semibold)).monospacedDigit()
            Text(date.weekdayDayMonth(in: tz)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The round "turn" button used for directions everywhere in the app.
struct DirectionsButton: View {
    let place: DrivePlace
    var mode: GettingAround = .drive

    var body: some View {
        Button {
            DriveService.openDirections(to: place, mode: mode)
        } label: {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.title2)
                .foregroundStyle(Color.drive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Directions to \(place.name)")
        .disabled(!place.isSet)
    }
}

/// The driving route on a map, looked up from Apple Maps.
struct DriveRouteMap: View {
    let from: DrivePlace
    let to: DrivePlace
    var departure: Date?
    var avoidTolls = false
    var avoidHighways = false
    var interactive = true
    @State private var route: DriveRoute?

    init(leg: DriveLeg, interactive: Bool = true) {
        self.init(from: leg.from, to: leg.to, departure: leg.departure, avoidTolls: leg.avoidTolls,
                  avoidHighways: leg.avoidHighways, interactive: interactive)
    }

    init(from: DrivePlace, to: DrivePlace, departure: Date? = nil, avoidTolls: Bool = false,
         avoidHighways: Bool = false, interactive: Bool = true) {
        self.from = from
        self.to = to
        self.departure = departure
        self.avoidTolls = avoidTolls
        self.avoidHighways = avoidHighways
        self.interactive = interactive
    }

    private var routeKey: String {
        "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)|\(avoidTolls)\(avoidHighways)"
    }

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
            if let route {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Color.drive, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if from.isSet {
                Annotation(from.name, coordinate: from.coordinate, anchor: .center) {
                    Circle().fill(.white).frame(width: 12, height: 12).overlay(Circle().stroke(Color.drive, lineWidth: 3))
                }
            }
            if to.isSet {
                Marker(to.name, systemImage: "flag.checkered", coordinate: to.coordinate).tint(Color.drive)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: true))
        .allowsHitTesting(interactive)
        .task(id: routeKey) {
            guard from.isSet, to.isSet else { return }
            route = try? await DriveService.shared.route(from: from.coordinate, to: to.coordinate, departure: departure,
                                                         avoidTolls: avoidTolls, avoidHighways: avoidHighways)
        }
    }
}

// MARK: - Editor

/// Add or edit a drive: pick where from and to (hotel, airport, plan stops or any address) and
/// when to leave. Apple Maps fills in the drive time and distance as you go.
struct DriveLegEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let trip: Trip
    let leg: DriveLeg?

    @State private var from: DrivePlace?
    @State private var to: DrivePlace?
    @State private var departure: Date
    @State private var avoidTolls: Bool
    @State private var avoidHighways: Bool
    @State private var vehicle: String
    @State private var notes: String
    @State private var route: DriveRoute?
    @State private var routeError: String?
    @State private var loadingRoute = false

    /// - Parameters:
    ///   - from / to / departure: prefill for a new drive (for example from a gap in the plan).
    init(trip: Trip, leg: DriveLeg?, from: DrivePlace? = nil, to: DrivePlace? = nil, departure: Date? = nil) {
        self.trip = trip
        self.leg = leg
        let cal = trip.calendar
        let firstDay = trip.days.first ?? trip.startDate
        let defaultDeparture = cal.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay) ?? firstDay
        // A new drive starts from where they're staying, or the airport they land at.
        let home = trip.sortedStays.first.map { DrivePlace(name: $0.name, address: $0.address, coordinate: $0.coordinate) }
            ?? trip.sortedFlights.first.map { DrivePlace(name: $0.arrival.iata.isEmpty ? $0.arrival.airportName : "\($0.arrival.iata) airport",
                                                         address: $0.arrival.airportName, coordinate: $0.arrival.coordinate) }
        _from = State(initialValue: leg?.from ?? from ?? home)
        _to = State(initialValue: leg?.to ?? to)
        _departure = State(initialValue: leg?.departure ?? departure ?? defaultDeparture)
        _avoidTolls = State(initialValue: leg?.avoidTolls ?? false)
        _avoidHighways = State(initialValue: leg?.avoidHighways ?? false)
        _vehicle = State(initialValue: leg?.vehicle ?? "")
        _notes = State(initialValue: leg?.notes ?? "")
    }

    private var routeKey: String {
        guard let from, let to else { return "" }
        let bucket = Int(departure.timeIntervalSince1970 / 900)
        return "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)|\(bucket)|\(avoidTolls)|\(avoidHighways)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DrivePlacePicker(label: "From", symbol: "circle.circle", trip: trip, place: $from)
                    DrivePlacePicker(label: "To", symbol: "flag.checkered", trip: trip, place: $to)
                    if from != nil || to != nil {
                        Button("Swap Start and Destination", systemImage: "arrow.up.arrow.down") {
                            (from, to) = (to, from)
                        }
                    }
                } header: {
                    Text("Route")
                }

                Section {
                    DatePicker("Leave", selection: $departure, displayedComponents: [.date, .hourAndMinute])
                    if let route {
                        LabeledContent("Arrive around", value: departure.addingTimeInterval(TimeInterval(route.minutes * 60)).time(in: trip.timeZone))
                    }
                } footer: {
                    Text("Times are in \(trip.destinationName) local time. Drive time includes expected traffic for when you leave.")
                }

                if from != nil, to != nil {
                    Section("Preview") {
                        routePreview
                    }
                }

                Section {
                    Toggle("Avoid Tolls", isOn: $avoidTolls)
                    Toggle("Avoid Highways", isOn: $avoidHighways)
                    TextField("Car (optional)", text: $vehicle, prompt: Text("e.g. Rental car, Hertz pickup"))
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }

                if let leg {
                    Section {
                        Button("Remove Drive", role: .destructive) {
                            context.delete(leg)
                            try? context.save()
                            Task { await DriveActivities.syncAll() }
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .environment(\.timeZone, trip.timeZone)
            .keyboardDismissable()
            .navigationTitle(leg == nil ? "Add Drive" : "Edit Drive")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(from == nil || to == nil)
                }
            }
            .task(id: routeKey) { await loadRoute() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 620)
        #endif
    }

    @ViewBuilder
    private var routePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let from, let to {
                DriveRouteMap(from: from, to: to, departure: departure, avoidTolls: avoidTolls, avoidHighways: avoidHighways)
                    .id(routeKey)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack {
                if loadingRoute {
                    ProgressView().controlSize(.small)
                    Text("Finding the best route…").foregroundStyle(.secondary)
                } else if let route {
                    Image(systemName: "car.fill").foregroundStyle(Color.drive)
                    Text(DriveService.durationText(route.minutes)).fontWeight(.semibold)
                    Text(DriveService.distanceText(route.meters)).foregroundStyle(.secondary)
                } else if let routeError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(routeError).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func loadRoute() async {
        guard let from, let to else { route = nil; return }
        loadingRoute = true
        defer { loadingRoute = false }
        do {
            route = try await DriveService.shared.route(from: from.coordinate, to: to.coordinate, departure: departure,
                                                        avoidTolls: avoidTolls, avoidHighways: avoidHighways)
            routeError = nil
        } catch {
            route = nil
            routeError = (error as? LocalizedError)?.errorDescription ?? "Couldn't find a driving route."
        }
    }

    private func save() {
        guard let from, let to else { return }
        let target = leg ?? {
            let new = DriveLeg(from: from, to: to, departure: departure)
            context.insert(new)
            new.trip = trip
            return new
        }()
        target.from = from
        target.to = to
        target.departure = departure
        target.avoidTolls = avoidTolls
        target.avoidHighways = avoidHighways
        target.vehicle = vehicle.trimmingCharacters(in: .whitespaces)
        target.notes = notes
        if let route {
            target.travelMinutes = route.minutes
            target.distanceMeters = route.meters
            target.routeUpdatedAt = .now
        }
        try? context.save()
        Task { await DriveActivities.syncAll() }
        dismiss()
    }
}

/// Picks one end of a drive: places already on the trip first, then any address or place.
struct DrivePlacePicker: View {
    let label: String
    let symbol: String
    let trip: Trip
    @Binding var place: DrivePlace?
    @State private var search: LocationSearch
    @State private var editing = false

    init(label: String, symbol: String, trip: Trip, place: Binding<DrivePlace?>) {
        self.label = label
        self.symbol = symbol
        self.trip = trip
        _place = place
        let region = MKCoordinateRegion(center: trip.coordinate, latitudinalMeters: 400_000, longitudinalMeters: 400_000)
        _search = State(initialValue: LocationSearch(kind: .place, near: region))
    }

    var body: some View {
        if let place, !editing {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Color.drive).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(place.name).lineLimit(1)
                    if !place.address.isEmpty, place.address != place.name {
                        Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Change") { editing = true }.buttonStyle(.borderless)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(Color.drive).frame(width: 22)
                    TextField(label, text: $search.query, prompt: Text("\(label): search a place or address"))
                        .autocorrectionDisabled()
                    if editing {
                        Button("Cancel") { editing = false; search.query = "" }.buttonStyle(.borderless)
                    }
                }
                if search.query.isEmpty {
                    let suggestions = Self.suggestions(for: trip)
                    if !suggestions.isEmpty {
                        HorizontalScroller {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button { choose(s) } label: {
                                        Label(s.name, systemImage: s.symbol)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Color.insetBackground, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                ForEach(search.results.prefix(5), id: \.self) { r in
                    Button {
                        Task {
                            if let resolved = try? await search.resolve(r) {
                                choose(.init(name: resolved.name, address: resolved.address, coordinate: resolved.coordinate, symbol: "mappin"))
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).foregroundStyle(.primary)
                            Text(r.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func choose(_ s: Suggestion) {
        place = DrivePlace(name: s.name, address: s.address, coordinate: s.coordinate)
        search.query = ""
        editing = false
    }

    struct Suggestion: Hashable {
        var name: String
        var address: String
        var latitude: Double
        var longitude: Double
        var symbol: String

        init(name: String, address: String, coordinate: CLLocationCoordinate2D, symbol: String) {
            self.name = name
            self.address = address
            self.latitude = coordinate.latitude
            self.longitude = coordinate.longitude
            self.symbol = symbol
        }

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    /// Hotels, airports and planned stops on this trip.
    static func suggestions(for trip: Trip) -> [Suggestion] {
        var result: [Suggestion] = []
        for s in trip.sortedStays {
            result.append(.init(name: s.name, address: s.address, coordinate: s.coordinate, symbol: "bed.double.fill"))
        }
        for f in trip.sortedFlights {
            for end in [f.arrival, f.departure] where !end.iata.isEmpty {
                result.append(.init(name: "\(end.iata) airport", address: end.airportName, coordinate: end.coordinate, symbol: "airplane"))
            }
        }
        for p in (trip.planItems ?? []).filter({ $0.isScheduled }).sorted(by: { $0.start < $1.start }) {
            if let c = p.coordinate {
                result.append(.init(name: p.title, address: p.address, coordinate: c, symbol: p.category.symbol))
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.name).inserted }.prefix(12).map { $0 }
    }
}
