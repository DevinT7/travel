import SwiftUI

/// Paste a confirmation email or text; the flights in it are found on the device and shown for review.
struct PasteFlightsForm: View {
    let trip: Trip
    let onAdd: ([FlightSegment]) -> Void

    @State private var text = ""
    @State private var found: [FlightSegment] = []
    @State private var unknownAirports: [String] = []
    @State private var isReading = false
    @State private var didRead = false

    private var newFlights: [FlightSegment] { found.filter { !trip.hasFlight($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste the confirmation email or text from your airline. TravelHub finds the flight numbers, airports and times on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("United Flight 837 …\nDeparts: 10:40 AM SFO\nArrives: 2:15 PM DEN")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .autocorrectionDisabled()
                }
                .font(.callout)
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.joined(separator: "\n")
                        Task { @MainActor in
                            text = pasted
                            await read()
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    Spacer()
                    if !text.isEmpty {
                        Button("Clear") { text = ""; found = []; didRead = false }
                            .font(.subheadline)
                    }
                }
            }
            .card(padding: 12)

            Button {
                Task { await read() }
            } label: {
                HStack {
                    if isReading { ProgressView().controlSize(.small) }
                    Text(isReading ? "Reading…" : "Find Flights")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReading)

            if didRead && found.isEmpty {
                NoticeBanner(symbol: "text.magnifyingglass",
                             message: unknownAirports.isEmpty
                                ? "No flights found. The text needs flight numbers, three-letter airport codes (like AUS) and times. You can also enter the flight by hand."
                                : "Couldn't find the airport\(unknownAirports.count == 1 ? "" : "s") \(unknownAirports.joined(separator: ", ")).")
            }

            if !found.isEmpty {
                Text(found.count == 1 ? "Found 1 flight" : "Found \(found.count) flights").font(.headline)
                ForEach(found) { flight in
                    VStack(alignment: .leading, spacing: 6) {
                        if trip.hasFlight(flight) {
                            Label("Already in this trip", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                        FlightCardView(flight: flight)
                            .opacity(trip.hasFlight(flight) ? 0.5 : 1)
                    }
                }
                Button {
                    dismissKeyboard()
                    onAdd(newFlights)
                } label: {
                    Text(newFlights.isEmpty ? "Already Added" : "Add \(newFlights.count) Flight\(newFlights.count == 1 ? "" : "s")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(newFlights.isEmpty)
            }
        }
    }

    private func read() async {
        dismissKeyboard()
        isReading = true
        defer { isReading = false; didRead = true }
        let result = await ConfirmationImporter.build(from: text, trip: trip)
        found = result.flights
        unknownAirports = result.unknownAirports
    }
}
