import SwiftUI
import SwiftData
import MapKit

struct StayCardView: View {
    let stay: Stay
    let tz: TimeZone

    private var nights: Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: stay.checkIn), to: cal.startOfDay(for: stay.checkOut)).day ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bed.double.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(stay.name).font(.headline).lineLimit(1)
                    Text(stay.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(nights) night\(nights == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                timeBlock("Check-in", stay.checkIn)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 14)
                Spacer()
                timeBlock("Check-out", stay.checkOut, trailing: true)
            }
            HStack {
                if !stay.confirmationNumber.isEmpty {
                    Label(stay.confirmationNumber, systemImage: "number")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: stay.coordinate))
                    item.name = stay.name
                    item.openInMaps()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .card(padding: 18)
    }

    private func timeBlock(_ label: String, _ date: Date, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(date.weekdayDayMonth(in: tz)).font(.headline)
            Text(date.time(in: tz)).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Add or edit a hotel / rental. Hotel names are searched with Apple Maps near the destination.
struct StayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let trip: Trip
    let stay: Stay?

    @State private var search: LocationSearch
    @State private var place: ResolvedPlace?
    @State private var checkIn: Date
    @State private var checkOut: Date
    @State private var confirmation: String
    @State private var notes: String

    init(trip: Trip, stay: Stay?) {
        self.trip = trip
        self.stay = stay
        let region = MKCoordinateRegion(center: trip.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        _search = State(initialValue: LocationSearch(kind: .hotel, near: region))
        let cal = trip.calendar
        let defaultIn = cal.date(bySettingHour: 15, minute: 0, second: 0, of: trip.startDate) ?? trip.startDate
        let defaultOut = cal.date(bySettingHour: 11, minute: 0, second: 0, of: trip.endDate) ?? trip.endDate
        _place = State(initialValue: stay.map { ResolvedPlace(name: $0.name, address: $0.address, coordinate: $0.coordinate) })
        _checkIn = State(initialValue: stay?.checkIn ?? defaultIn)
        _checkOut = State(initialValue: stay?.checkOut ?? defaultOut)
        _confirmation = State(initialValue: stay?.confirmationNumber ?? "")
        _notes = State(initialValue: stay?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    if let place {
                        HStack {
                            Image(systemName: "bed.double.fill").foregroundStyle(.indigo)
                            VStack(alignment: .leading) {
                                Text(place.name).font(.headline)
                                Text(place.address).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change") { self.place = nil }.buttonStyle(.borderless)
                        }
                    } else {
                        TextField("Search hotels or an address", text: $search.query)
                            .autocorrectionDisabled()
                        ForEach(search.results.prefix(6), id: \.self) { r in
                            Button {
                                Task { place = try? await search.resolve(r) }
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
                }
                Section("Dates (\(trip.timeZone.localizedName(for: .shortGeneric, locale: .current) ?? trip.timeZone.identifier))") {
                    DatePicker("Check-in", selection: $checkIn)
                    DatePicker("Check-out", selection: $checkOut, in: checkIn...)
                }
                Section("Details") {
                    TextField("Confirmation number", text: $confirmation)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .formStyle(.grouped)
            .environment(\.timeZone, trip.timeZone)
            .navigationTitle(stay == nil ? "Add Stay" : "Edit Stay")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(place == nil) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func save() {
        guard let place else { return }
        let target = stay ?? Stay(name: place.name, address: place.address, coordinate: place.coordinate, checkIn: checkIn, checkOut: checkOut)
        target.name = place.name
        target.address = place.address
        target.latitude = place.coordinate.latitude
        target.longitude = place.coordinate.longitude
        target.checkIn = checkIn
        target.checkOut = checkOut
        target.confirmationNumber = confirmation
        target.notes = notes
        if stay == nil {
            context.insert(target)
            target.trip = trip
        }
        try? context.save()
        dismiss()
    }
}
