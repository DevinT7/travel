import SwiftUI
import SwiftData
import MapKit

/// Schedules a discovered place, creates a custom plan item, or edits an existing one.
struct PlanItemEditor: View {
    enum Mode {
        case fromDiscover(DiscoverItem)
        case custom(day: Date?)
        case edit(PlanItem)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let trip: Trip
    let mode: Mode

    @State private var title = ""
    @State private var category: DiscoverCategory = .other
    @State private var isScheduled = true
    @State private var day: Date
    @State private var time: Date
    @State private var duration = 60
    @State private var notes = ""
    @State private var isBooked = false
    @State private var place: ResolvedPlace?
    @State private var placeQuery = ""
    @State private var placeResults: [DiscoverItem] = []

    private static let durations = [30, 45, 60, 90, 120, 180, 240, 480]

    init(trip: Trip, mode: Mode) {
        self.trip = trip
        self.mode = mode
        let cal = trip.calendar
        let firstDay = trip.days.first ?? cal.startOfDay(for: trip.startDate)
        let defaultTime = cal.date(bySettingHour: 10, minute: 0, second: 0, of: firstDay) ?? firstDay

        switch mode {
        case .fromDiscover(let item):
            _title = State(initialValue: item.title)
            _category = State(initialValue: item.category)
            _duration = State(initialValue: item.category.defaultDurationMinutes)
            let start = item.eventDate ?? defaultTime
            _day = State(initialValue: cal.startOfDay(for: start))
            _time = State(initialValue: start)
        case .custom(let d):
            let base = d ?? firstDay
            _day = State(initialValue: cal.startOfDay(for: base))
            _time = State(initialValue: cal.date(bySettingHour: 10, minute: 0, second: 0, of: base) ?? base)
        case .edit(let p):
            _title = State(initialValue: p.title)
            _category = State(initialValue: p.category)
            _isScheduled = State(initialValue: p.isScheduled)
            _day = State(initialValue: cal.startOfDay(for: p.isScheduled ? p.start : firstDay))
            _time = State(initialValue: p.isScheduled ? p.start : defaultTime)
            _duration = State(initialValue: p.durationMinutes)
            _notes = State(initialValue: p.notes)
            _isBooked = State(initialValue: p.isBooked)
            if let c = p.coordinate {
                _place = State(initialValue: ResolvedPlace(name: p.title, address: p.address, coordinate: c))
            }
        }
    }

    private var isCustom: Bool { if case .custom = mode { true } else { false } }
    private var navTitle: String {
        switch mode {
        case .fromDiscover: "Add to Plan"
        case .custom: "New Plan Item"
        case .edit: "Edit"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if case .fromDiscover(let item) = mode {
                        HStack(spacing: 12) {
                            CategoryIcon(category: item.category, size: 40)
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        TextField("Title", text: $title, prompt: Text("e.g. Dinner reservation"))
                            .font(.headline)
                        Picker("Category", selection: $category) {
                            ForEach(DiscoverCategory.allCases) { c in
                                Label(c.title, systemImage: c.symbol).tag(c)
                            }
                        }
                    }
                }

                if isCustom || place != nil, !isDiscover {
                    placeSection
                }

                Section {
                    Toggle("Pick a time", isOn: $isScheduled.animation())
                    if isScheduled {
                        dayPicker
                        DatePicker("Start", selection: $time, displayedComponents: .hourAndMinute)
                        Picker("Duration", selection: $duration) {
                            ForEach(Self.durations, id: \.self) { m in Text(Self.durationLabel(m)).tag(m) }
                        }
                        if let warning = closedWarning {
                            Label(warning, systemImage: "clock.badge.exclamationmark")
                                .foregroundStyle(.orange)
                        }
                        if let destination {
                            GettingThereRow(trip: trip, destination: destination, start: combinedStart, excluding: editingID)
                        }
                    }
                } footer: {
                    Text(isScheduled ? "Times are in \(trip.destinationName) local time."
                                     : "It'll be saved to your ideas list so you can schedule it later.")
                }

                Section {
                    Toggle("Booked / have tickets", isOn: $isBooked)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
                }

                if case .edit(let item) = mode {
                    Section {
                        Button("Remove from Plan", role: .destructive) {
                            context.delete(item)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .environment(\.timeZone, trip.timeZone)
            .keyboardDismissable()
            .navigationTitle(navTitle)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isDiscover && title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task(id: placeQuery) {
                guard placeQuery.count > 1 else { placeResults = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                placeResults = (try? await MapKitPlacesProvider().search(query: placeQuery, near: trip.coordinate)) ?? []
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var isDiscover: Bool { if case .fromDiscover = mode { true } else { false } }

    /// The place's opening hours, if known, to warn while picking a time it's closed.
    private var hours: PlaceHours? {
        switch mode {
        case .fromDiscover(let item): item.google?.hours
        case .edit(let p): p.openingHours
        case .custom: nil
        }
    }

    private var closedWarning: String? {
        guard category != .events else { return nil }
        return hours?.conflict(start: combinedStart, end: combinedStart.addingTimeInterval(TimeInterval(duration * 60)))
    }

    private var editingID: UUID? { if case .edit(let p) = mode { p.id } else { nil } }

    /// Where this plan is, for the "getting there" estimate.
    private var destination: CLLocationCoordinate2D? {
        if case .fromDiscover(let item) = mode { return item.coordinate }
        return place?.coordinate
    }

    private var placeSection: some View {
        Section("Place") {
            if let place {
                HStack {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading) {
                        Text(place.name)
                        if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Remove") { self.place = nil }.buttonStyle(.borderless)
                }
            } else {
                TextField("Search a place (optional)", text: $placeQuery).autocorrectionDisabled()
                ForEach(placeResults.prefix(5)) { r in
                    Button {
                        place = ResolvedPlace(name: r.title, address: r.address, coordinate: r.coordinate ?? trip.coordinate)
                        if title.isEmpty { title = r.title }
                        if category == .other { category = r.category }
                        placeQuery = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).foregroundStyle(.primary)
                            Text(r.address).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day")
            HorizontalScroller {
                HStack(spacing: 8) {
                    ForEach(trip.days, id: \.self) { d in
                        let selected = trip.calendar.isDate(d, inSameDayAs: day)
                        Button {
                            day = d
                        } label: {
                            VStack(spacing: 2) {
                                Text(d.weekday(in: trip.timeZone)).font(.caption2.weight(.semibold))
                                Text(d.dayNumber(in: trip.timeZone)).font(.headline)
                            }
                            .frame(width: 46, height: 52)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.insetBackground),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    static func durationLabel(_ m: Int) -> String {
        switch m {
        case 240: "Half day"
        case 480: "Full day"
        default: TimeInterval(m * 60).hoursMinutes.replacingOccurrences(of: " 0m", with: "")
        }
    }

    /// Combines the chosen day with the chosen clock time, in the destination time zone.
    private var combinedStart: Date {
        let cal = trip.calendar
        let hm = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: hm.hour ?? 10, minute: hm.minute ?? 0, second: 0, of: day) ?? day
    }

    private func save() {
        let item: PlanItem
        switch mode {
        case .fromDiscover(let d):
            item = PlanItem.from(d, trip: trip)
            context.insert(item)
            item.trip = trip
        case .custom:
            item = PlanItem(title: title, category: category, start: combinedStart)
            context.insert(item)
            item.trip = trip
        case .edit(let existing):
            item = existing
        }
        if !isDiscover {
            item.title = title.trimmingCharacters(in: .whitespaces)
            item.category = category
            item.latitude = place?.coordinate.latitude
            item.longitude = place?.coordinate.longitude
            item.address = place?.address ?? ""
        }
        item.isScheduled = isScheduled
        if isScheduled { item.start = combinedStart }
        item.durationMinutes = duration
        item.notes = notes
        item.isBooked = isBooked
        try? context.save()
        dismiss()
    }
}

/// "35 min drive from Hotel Granvia · leave by 9:25 AM": how to reach a plan from wherever the
/// traveler will be just before it (the previous stop that day, or the hotel).
private struct GettingThereRow: View {
    let trip: Trip
    let destination: CLLocationCoordinate2D
    let start: Date
    let excluding: UUID?
    @State private var estimate: TravelEstimate?

    private var origin: (name: String, coordinate: CLLocationCoordinate2D)? {
        trip.origin(before: start, excluding: excluding)
    }

    var body: some View {
        if let origin {
            HStack(spacing: 10) {
                Image(systemName: estimate?.symbol ?? trip.gettingAround.symbol)
                    .foregroundStyle(Color.drive)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Getting there").font(.caption).foregroundStyle(.secondary)
                    if let estimate {
                        Text("\(estimate.text) from \(origin.name)").lineLimit(2)
                        if estimate.mode != .walk {
                            Text("Leave by \(start.addingTimeInterval(-TimeInterval(estimate.minutes * 60)).time(in: trip.timeZone))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("From \(origin.name)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .task(id: "\(origin.coordinate.latitude),\(origin.coordinate.longitude)>\(destination.latitude),\(destination.longitude)|\(trip.gettingAroundRaw)") {
                estimate = await DirectionsService.shared.estimate(from: origin.coordinate, to: destination, mode: trip.gettingAround)
            }
        }
    }
}
