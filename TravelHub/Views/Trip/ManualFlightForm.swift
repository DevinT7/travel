import SwiftUI
import MapKit

/// Add a flight by hand: flight number, airport codes, and local departure/arrival times.
/// Airports are resolved with Apple Maps, so this works without any API key.
struct ManualFlightForm: View {
    let trip: Trip
    let onAdd: (FlightSegment) -> Void

    @State private var number = ""
    @State private var fromCode = ""
    @State private var toCode = ""
    @State private var from: FlightEndpoint?
    @State private var to: FlightEndpoint?
    @State private var fromState = LookupState.idle
    @State private var toState = LookupState.idle
    /// Wall-clock times, edited in GMT and converted to each airport's zone when saving.
    @State private var departs: Date
    @State private var arrives: Date

    enum LookupState { case idle, loading, found, notFound }

    private static let gmt = TimeZone(secondsFromGMT: 0)!

    init(trip: Trip, onAdd: @escaping (FlightSegment) -> Void) {
        self.trip = trip
        self.onAdd = onAdd
        // The first flight usually leaves on day one; a second one is usually the flight home.
        let day = trip.sortedFlights.isEmpty ? trip.startDate : trip.endDate
        let start = trip.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let wall = Self.wallClock(start, in: trip.timeZone)
        _departs = State(initialValue: wall)
        _arrives = State(initialValue: wall.addingTimeInterval(3 * 3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                field("Flight") {
                    TextField("e.g. UA 837", text: $number)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                }
                if let airline = Airlines.parse(number) {
                    Text(airline.name).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 96).padding(.bottom, 8)
                }
                Divider()
                airportField("From", code: $fromCode, state: fromState, endpoint: from)
                Divider()
                airportField("To", code: $toCode, state: toState, endpoint: to)
            }
            .card(padding: 14)

            VStack(spacing: 0) {
                timeRow("Departs", $departs, endpoint: from)
                Divider()
                timeRow("Arrives", $arrives, endpoint: to)
                if let duration {
                    Divider()
                    HStack {
                        Text("Flight time").foregroundStyle(.secondary)
                        Spacer()
                        Text(duration > 0 ? duration.hoursMinutes : "Arrival is before departure")
                            .foregroundStyle(duration > 0 ? Color.primary : Color.orange)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 10)
                }
            }
            .card(padding: 14)
            .environment(\.timeZone, Self.gmt)

            Button {
                dismissKeyboard()
                if let flight = makeFlight() { onAdd(flight) }
            } label: {
                Text("Add Flight").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(makeFlight() == nil)
        }
        // Moving the departure moves the arrival with it, keeping the same flight length.
        .onChange(of: departs) { old, new in arrives = arrives.addingTimeInterval(new.timeIntervalSince(old)) }
        .onChange(of: fromCode) { _, code in lookup(code, isFrom: true) }
        .onChange(of: toCode) { _, code in lookup(code, isFrom: false) }
    }

    // MARK: Pieces

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            content().font(.body.weight(.semibold))
        }
        .padding(.vertical, 10)
    }

    private func airportField(_ label: String, code: Binding<String>, state: LookupState, endpoint: FlightEndpoint?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            field(label) {
                TextField("Airport code, e.g. AUS", text: code)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                Spacer(minLength: 4)
                switch state {
                case .loading: ProgressView().controlSize(.small)
                case .found: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .notFound: Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                case .idle: EmptyView()
                }
            }
            if let endpoint, state == .found {
                Text("\(endpoint.airportName) · \(endpoint.timeZone.localizedName(for: .shortGeneric, locale: .current) ?? endpoint.timeZoneIdentifier)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 96).padding(.bottom, 8)
            } else if state == .notFound {
                Text("No airport found for that code.").font(.caption).foregroundStyle(.orange)
                    .padding(.leading, 96).padding(.bottom, 8)
            }
        }
    }

    private func timeRow(_ label: String, _ date: Binding<Date>, endpoint: FlightEndpoint?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            DatePicker(label, selection: date)
            Text(endpoint.map { "Local time in \($0.city.isEmpty ? $0.iata : $0.city)" } ?? "Local time at the airport")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: Logic

    private func lookup(_ code: String, isFrom: Bool) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if isFrom { from = nil; fromState = .idle } else { to = nil; toState = .idle }
        guard trimmed.count == 3 else { return }
        if isFrom { fromState = .loading } else { toState = .loading }
        Task {
            let result = await AirportLookup.resolve(code: trimmed)
            // Ignore stale answers if the code changed while we were searching.
            guard (isFrom ? fromCode : toCode).trimmingCharacters(in: .whitespaces) == trimmed else { return }
            if isFrom { from = result; fromState = result == nil ? .notFound : .found }
            else { to = result; toState = result == nil ? .notFound : .found }
        }
    }

    private var duration: TimeInterval? {
        guard let from, let to else { return nil }
        return Self.realDate(arrives, in: to.timeZone).timeIntervalSince(Self.realDate(departs, in: from.timeZone))
    }

    private func makeFlight() -> FlightSegment? {
        guard let airline = Airlines.parse(number), var dep = from, var arr = to, let d = duration, d > 0 else { return nil }
        dep.scheduled = Self.realDate(departs, in: dep.timeZone)
        arr.scheduled = Self.realDate(arrives, in: arr.timeZone)
        // Apple Maps names the suburb an airport sits in ("SeaTac"); near the destination, use its name.
        if trip.isNearDestination(dep) { dep.city = trip.destinationName }
        if trip.isNearDestination(arr) { arr.city = trip.destinationName }
        return FlightSegment(flightNumber: airline.flightNumber, airlineName: airline.name, airlineCode: airline.code,
                             departure: dep, arrival: arr, status: "Scheduled", aircraftModel: nil,
                             distanceKm: AirportLookup.distanceKm(dep, arr))
    }

    /// The same wall-clock time, re-expressed in GMT so pickers show it unchanged.
    static func wallClock(_ date: Date, in tz: TimeZone) -> Date {
        var source = Calendar(identifier: .gregorian); source.timeZone = tz
        var target = Calendar(identifier: .gregorian); target.timeZone = gmt
        let c = source.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return target.date(from: c) ?? date
    }

    /// A GMT wall-clock time read as local time in `tz`.
    static func realDate(_ wall: Date, in tz: TimeZone) -> Date {
        var source = Calendar(identifier: .gregorian); source.timeZone = gmt
        var target = Calendar(identifier: .gregorian); target.timeZone = tz
        let c = source.dateComponents([.year, .month, .day, .hour, .minute], from: wall)
        return target.date(from: c) ?? wall
    }
}
