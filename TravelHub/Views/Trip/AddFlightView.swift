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

    init(trip: Trip) {
        self.trip = trip
        // Default to the trip's first day, or today if the trip has started.
        _date = State(initialValue: max(trip.startDate, .now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if aeroKey.isEmpty {
                        NoticeBanner(symbol: "key.fill",
                                     message: "Flight lookup uses AeroDataBox. Add a free API key in Settings to search real flights.",
                                     actionTitle: "Open Settings") { showingSettings = true }
                    }

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
                .padding(Metrics.gutter)
                .readableWidth(560)
            }
            .background(Color.appBackground)
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

    private func search() async {
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

    private func add(_ flight: FlightSegment) {
        context.insert(flight)
        flight.trip = trip
        try? context.save()
        results.removeAll { $0.id == flight.id }
        if results.isEmpty { dismiss() }
    }
}
