import SwiftUI
import SwiftData

struct AddFlightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(APIKeys.aeroDataBoxKey) private var aeroKey = ""
    let trip: Trip

    @State private var flightNumber = ""
    @State private var date: Date
    @State private var results: [FlightSegment] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var showingSettings = false
    @State private var mode: Mode

    enum Mode: String, CaseIterable { case paste = "Paste", manual = "Enter", lookup = "Look Up" }

    init(trip: Trip) {
        self.trip = trip
        // Default to the trip's first day, or today if the trip has started.
        _date = State(initialValue: max(trip.startDate, .now))
        let hasKey = !(UserDefaults.standard.string(forKey: APIKeys.aeroDataBoxKey) ?? "").isEmpty
        _mode = State(initialValue: hasKey ? .lookup : .paste)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("How", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .paste:
                        PasteFlightsForm(trip: trip) { flights in
                            flights.forEach(insert)
                            dismiss()
                        }
                    case .manual:
                        ManualFlightForm(trip: trip) { add($0) }
                    case .lookup:
                        if aeroKey.isEmpty {
                            NoticeBanner(symbol: "key.fill",
                                         message: "Looking up a flight number fills in times, terminals, gates and delays. It needs a free AeroDataBox key.",
                                         actionTitle: "Add Key in Settings") { showingSettings = true }
                        }
                        lookupForm
                    }
                }
                .padding(Metrics.gutter)
                .readableWidth(560)
            }
            // Tapping empty space or dragging the page down puts the keyboard away.
            .background(Color.appBackground.onTapGesture { dismissKeyboard() })
            .keyboardDismissable()
            .onChange(of: mode) { dismissKeyboard() }
            .navigationTitle("Add Flight")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    @ViewBuilder
    private var lookupForm: some View {
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "airplane").foregroundStyle(.secondary).frame(width: 24)
                            TextField("Flight number, e.g. UA 837", text: $flightNumber)
                                .font(.title3.weight(.semibold))
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.characters)
                                #endif
                                .onSubmit { Task { await search() } }
                        }
                        .padding(.vertical, 12)
                        Divider()
                        DatePicker(selection: $date, displayedComponents: .date) {
                            Label("Departure date", systemImage: "calendar").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                    }
                    .card(padding: 14)

                    Button {
                        Task { await search() }
                    } label: {
                        HStack {
                            if isSearching { ProgressView().controlSize(.small) }
                            Text(isSearching ? "Searching…" : "Find Flight")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(FlightService.normalize(flightNumber).count < 3 || isSearching || aeroKey.isEmpty)

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                    }

                    if !results.isEmpty {
                        Text(results.count == 1 ? "Is this your flight?" : "This flight number has \(results.count) legs. Add the ones you're on.")
                            .font(.headline)
                        ForEach(results) { flight in
                            VStack(spacing: 10) {
                                FlightCardView(flight: flight)
                                Button {
                                    add(flight)
                                } label: {
                                    Label("Add to \(trip.displayName)", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                    }
    }

    private func search() async {
        dismissKeyboard()
        guard FlightService.normalize(flightNumber).count >= 3 else { return }
        isSearching = true
        error = nil
        results = []
        defer { isSearching = false }
        do {
            results = try await FlightService().lookup(flightNumber: flightNumber, date: date)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func insert(_ flight: FlightSegment) {
        context.insert(flight)
        flight.trip = trip
        try? context.save()
    }

    private func add(_ flight: FlightSegment) {
        dismissKeyboard()
        insert(flight)
        results.removeAll { $0.id == flight.id }
        if results.isEmpty { dismiss() }
    }
}
