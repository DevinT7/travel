import SwiftUI
import SwiftData
import MapKit

struct NewTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var onCreate: (Trip) -> Void

    @State private var search = LocationSearch(kind: .city)
    @State private var destination: ResolvedPlace?
    @State private var name = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: 14, to: .now)!
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 20, to: .now)!
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            Form {
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

                Section("When") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section {
                    TextField("Trip name (optional)", text: $name, prompt: Text(destination.map { "\($0.name) trip" } ?? "e.g. Spring Break"))
                } footer: {
                    Text("You can add flights, where you're staying and things to do next.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Trip")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(destination == nil)
                }
            }
            .onChange(of: startDate) { _, new in if endDate < new { endDate = new } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

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
