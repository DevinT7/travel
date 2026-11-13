import SwiftUI
import SwiftData
import MapKit

struct NewTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Confirmation text pasted before this screen opened (from the welcome screen).
    var initialText: String?
    var onCreate: (Trip) -> Void

    @State private var search = LocationSearch(kind: .city)
    @State private var destination: ResolvedPlace?
    @State private var name = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: 14, to: .now)!
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 20, to: .now)!
    @State private var isResolving = false

    // Starting from a pasted confirmation.
    @State private var pastedText = ""
    @State private var isTyping = false
    @State private var isReading = false
    @State private var draft: TripFromConfirmation.Draft?
    @State private var readFailure: String?

    var body: some View {
        NavigationStack {
            Form {
                pasteSection

                Section("Where to?") {
                    if let destination {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.tint).font(.title2)
                            VStack(alignment: .leading) {
                                Text(destination.name).font(.headline)
                                if !destination.address.isEmpty {
                                    Text(destination.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Change") { self.destination = nil; search.query = "" }
                                .buttonStyle(.borderless)
                        }
                    } else {
                        TextField("Search a city", text: $search.query)
                            .textContentType(.addressCity)
                            .autocorrectionDisabled()
                        ForEach(search.results.prefix(6), id: \.self) { result in
                            Button {
                                Task { await pick(result) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if isResolving { ProgressView() }
                    }
                }

                Section {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                } header: {
                    Text("When")
                } footer: {
                    if let draft, !draft.hasReturn {
                        Text("No flight home in what you pasted, so check the end date.")
                    }
                }

                Section {
                    TextField("Trip name (optional)", text: $name, prompt: Text(destination.map { "\($0.name) trip" } ?? "e.g. Spring Break"))
                } footer: {
                    Text("You can add flights, where you're staying and things to do next.")
                }
            }
            .formStyle(.grouped)
            .keyboardDismissable()
            .navigationTitle("New Trip")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(destination == nil)
                }
            }
            .onChange(of: startDate) { _, new in if endDate < new { endDate = new } }
            .task {
                if let initialText, !initialText.isEmpty, draft == nil {
                    pastedText = initialText
                    await read()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: Paste a confirmation

    @ViewBuilder
    private var pasteSection: some View {
        Section {
            if isReading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading your confirmation…").foregroundStyle(.secondary)
                }
            } else if let draft {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.flights.count == 1 ? "1 flight found" : "\(draft.flights.count) flights found")
                            .font(.headline)
                        Text("Filled in \(draft.destination.name) and your dates. They'll be added to the trip.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                ForEach(draft.flights) { flight in
                    HStack(spacing: 12) {
                        CircleIcon(symbol: "airplane", color: .flight, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(flight.departure.iata) → \(flight.arrival.iata)").font(.subheadline.weight(.semibold))
                            Text("\(flight.flightNumber) · \(flight.departure.scheduled.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: flight.departure.timeZone)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Remove Flights", role: .destructive) { self.draft = nil; pastedText = "" }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Already booked?").font(.headline)
                    Text("Paste your flight confirmation and TravelHub fills in where you're going, your dates and your flights.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.joined(separator: "\n")
                        Task { @MainActor in
                            pastedText = text
                            await read()
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    Spacer()
                    Button(isTyping ? "Hide" : "Type It In") { withAnimation { isTyping.toggle() } }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                }
                if isTyping {
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 110)
                        .font(.callout)
                        .autocorrectionDisabled()
                    Button("Find Flights") { Task { await read() } }
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let readFailure {
                    Label(readFailure, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private func read() async {
        dismissKeyboard()
        isReading = true
        readFailure = nil
        defer { isReading = false }
        switch await TripFromConfirmation.draft(from: pastedText) {
        case .success(let found):
            draft = found
            destination = found.destination
            startDate = found.startDate
            endDate = found.endDate
            isTyping = false
        case .failure(.noFlights(let unknown)):
            draft = nil
            readFailure = unknown.isEmpty
                ? "No flights found. The text needs flight numbers, airport codes (like AUS) and times. You can also fill in the trip below."
                : "Couldn't find the airport\(unknown.count == 1 ? "" : "s") \(unknown.joined(separator: ", "))."
            isTyping = true
        }
    }

    // MARK: Create

    private func pick(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        destination = try? await search.resolve(completion)
    }

    private func create() {
        guard let destination else { return }
        let tz = destination.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let trip = Trip(name: name.trimmingCharacters(in: .whitespaces), destinationName: destination.name,
                        coordinate: destination.coordinate, countryCode: destination.countryCode,
                        timeZoneIdentifier: tz.identifier,
                        startDate: Self.sameDay(startDate, in: tz), endDate: Self.sameDay(endDate, in: tz))
        context.insert(trip)
        for flight in draft?.flights ?? [] {
            context.insert(flight)
            flight.trip = trip
        }
        try? context.save()
        onCreate(trip)
        dismiss()
    }

    /// The picked calendar day (in the user's zone) as midnight in the destination's zone.
    static func sameDay(_ date: Date, in tz: TimeZone) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: comps) ?? date
    }
}
