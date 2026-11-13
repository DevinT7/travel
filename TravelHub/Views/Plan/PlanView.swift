import SwiftUI
import SwiftData
import MapKit

/// One row on a day's timeline: a plan item, a flight, or a hotel check-in/out.
struct TimelineEntry: Identifiable {
    enum Kind { case plan(PlanItem), flight(FlightSegment, departing: Bool), stay(Stay, checkIn: Bool) }

    let id: String
    let kind: Kind
    let start: Date
    let end: Date?
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D?
    let symbol: String
    let color: Color
    /// Flights show times in the airport's own zone; everything else uses the trip's.
    var timeZone: TimeZone?

    var planItem: PlanItem? { if case .plan(let p) = kind { p } else { nil } }
}

struct PlanView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Bindable var trip: Trip

    /// nil shows the "Ideas" list of unscheduled items.
    @State private var selectedDay: Date?
    @State private var editing: PlanItem?
    @State private var addingCustom = false
    @State private var showingMap = false
    @State private var focusedEntryID: String?

    private var isWide: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    private var ideas: [PlanItem] { (trip.planItems ?? []).filter { !$0.isScheduled }.sorted { $0.title < $1.title } }

    var body: some View {
        VStack(spacing: 0) {
            DayPicker(trip: trip, selectedDay: $selectedDay, ideaCount: ideas.count)
                .padding(.vertical, 8)
            if let day = selectedDay {
                let entries = entries(for: day)
                if isWide {
                    HStack(spacing: 0) {
                        timeline(entries, day: day).frame(minWidth: 360, idealWidth: 440, maxWidth: 500)
                        DayMapView(entries: entries, stays: trip.sortedStays, fallback: trip.coordinate, focusedID: $focusedEntryID)
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                            .padding([.trailing, .bottom], Metrics.gutter)
                            .padding(.top, 4)
                    }
                } else {
                    timeline(entries, day: day)
                }
            } else {
                IdeasListView(trip: trip, ideas: ideas, onEdit: { editing = $0 })
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Plan")
        .inlineTitle()
        .toolbar {
            if !isWide, let day = selectedDay {
                ToolbarItem(placement: .primaryAction) {
                    Button("Map", systemImage: "map") { showingMap = true }
                        .sheet(isPresented: $showingMap) {
                            NavigationStack {
                                DayMapView(entries: entries(for: day), stays: trip.sortedStays, fallback: trip.coordinate,
                                           focusedID: $focusedEntryID)
                                    .ignoresSafeArea(edges: .bottom)
                                    .navigationTitle(day.formatted(Date.FormatStyle(timeZone: trip.timeZone).weekday(.wide).month().day()))
                                    .inlineTitle()
                                    .toolbar {
                                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showingMap = false } }
                                    }
                            }
                            .presentationDetents([.medium, .large])
                        }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add to Plan", systemImage: "plus") { addingCustom = true }
            }
        }
        .onAppear { if selectedDay == nil { selectedDay = initialDay } }
        .sheet(item: $editing) { PlanItemEditor(trip: trip, mode: .edit($0)) }
        .sheet(isPresented: $addingCustom) { PlanItemEditor(trip: trip, mode: .custom(day: selectedDay)) }
    }

    /// Today if the trip is underway, otherwise the first day.
    private var initialDay: Date? {
        let cal = trip.calendar
        return trip.days.first { cal.isDate($0, inSameDayAs: .now) } ?? trip.days.first
    }

    // MARK: Timeline

    @ViewBuilder
    private func timeline(_ entries: [TimelineEntry], day: Date) -> some View {
        #if os(macOS)
        macTimeline(entries, day: day)
        #else
        listTimeline(entries, day: day)
        #endif
    }

    private func dayTitle(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(timeZone: trip.timeZone).weekday(.wide).month(.wide).day())
    }

    private func entryMenu(_ entry: TimelineEntry) -> some View {
        Group {
            if let item = entry.planItem {
                Button("Edit", systemImage: "pencil") { editing = item }
                Button("Move to Ideas", systemImage: "tray.and.arrow.down") { item.isScheduled = false; try? context.save() }
                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item); try? context.save() }
            }
        }
    }

    private var emptyDay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing planned yet").font(.headline)
            Text("Find things to do in Discover, or add your own plans.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Discover \(trip.destinationName)") { app.tripSection = .discover }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    /// Mac: the same rounded card and rows as iOS's inset-grouped list, without a table look.
    private func macTimeline(_ entries: [TimelineEntry], day: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(dayTitle(day)).font(.title3.bold()).padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty { emptyDay }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0, !isFlightLeg(entries[index - 1], entry),
                           let a = entries[index - 1].coordinate, let b = entry.coordinate {
                            TravelRow(from: a, to: b, gap: entry.start.timeIntervalSince(entries[index - 1].end ?? entries[index - 1].start))
                                .padding(.leading, 4)
                        }
                        TimelineRow(entry: entry, tz: entry.timeZone ?? trip.timeZone)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedEntryID = entry.id
                                if let item = entry.planItem { editing = item }
                            }
                            .contextMenu { entryMenu(entry) }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 8)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                if !entries.isEmpty {
                    Text(summary(entries)).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
            }
            .padding(Metrics.gutter)
        }
    }

    private func listTimeline(_ entries: [TimelineEntry], day: Date) -> some View {
        List {
            Section {
                if entries.isEmpty { emptyDay }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0, !isFlightLeg(entries[index - 1], entry),
                       let a = entries[index - 1].coordinate, let b = entry.coordinate {
                        TravelRow(from: a, to: b, gap: entry.start.timeIntervalSince(entries[index - 1].end ?? entries[index - 1].start))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                    }
                    TimelineRow(entry: entry, tz: entry.timeZone ?? trip.timeZone)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            focusedEntryID = entry.id
                            if let item = entry.planItem { editing = item }
                        }
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            if let item = entry.planItem {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(item); try? context.save()
                                }
                                Button("Later", systemImage: "tray.and.arrow.down") {
                                    item.isScheduled = false; try? context.save()
                                }
                                .tint(.orange)
                            }
                        }
                        .contextMenu { entryMenu(entry) }
                }
            } header: {
                Text(dayTitle(day))
            } footer: {
                if !entries.isEmpty { Text(summary(entries)) }
            }
            .headerProminence(.increased)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .environment(\.defaultMinListRowHeight, 20)
        .scrollContentBackground(.hidden)
    }

    /// No ground travel estimate between a flight's departure and its landing.
    private func isFlightLeg(_ a: TimelineEntry, _ b: TimelineEntry) -> Bool {
        if case .flight(_, true) = a.kind, case .flight = b.kind { return true }
        return false
    }

    private func summary(_ entries: [TimelineEntry]) -> String {
        let plans = entries.compactMap(\.planItem)
        guard !plans.isEmpty else { return "" }
        let minutes = plans.reduce(0) { $0 + $1.durationMinutes }
        return "\(plans.count) plan\(plans.count == 1 ? "" : "s") · \(PlanItemEditor.durationLabel(minutes)) of activities"
    }

    private func entries(for day: Date) -> [TimelineEntry] {
        let cal = trip.calendar
        var result: [TimelineEntry] = []
        for p in trip.planItems ?? [] where p.isScheduled && cal.isDate(p.start, inSameDayAs: day) {
            let sub = [p.notes, p.address].first { !$0.isEmpty } ?? ""
            result.append(.init(id: p.id.uuidString, kind: .plan(p), start: p.start, end: p.end, title: p.title,
                                subtitle: sub, coordinate: p.coordinate, symbol: p.category.symbol, color: p.category.color))
        }
        for f in trip.sortedFlights {
            if Self.isSameLocalDay(f.departure.best, in: f.departure.timeZone, as: day, tripCalendar: cal) {
                result.append(.init(id: "dep-\(f.id)", kind: .flight(f, departing: true), start: f.departure.best, end: nil,
                                    title: "\(f.flightNumber) to \(f.arrival.city)",
                                    subtitle: "Departs \(f.departure.iata)" + (f.departure.gate.map { " · Gate \($0)" } ?? ""),
                                    coordinate: f.departure.coordinate, symbol: "airplane.departure", color: .flight,
                                    timeZone: f.departure.timeZone))
            }
            if Self.isSameLocalDay(f.arrival.best, in: f.arrival.timeZone, as: day, tripCalendar: cal) {
                result.append(.init(id: "arr-\(f.id)", kind: .flight(f, departing: false), start: f.arrival.best, end: nil,
                                    title: "Land in \(f.arrival.city)",
                                    subtitle: "\(f.flightNumber) · \(f.arrival.iata)" + (f.arrival.baggageBelt.map { " · Belt \($0)" } ?? ""),
                                    coordinate: f.arrival.coordinate, symbol: "airplane.arrival", color: .flight,
                                    timeZone: f.arrival.timeZone))
            }
        }
        for s in trip.sortedStays {
            if cal.isDate(s.checkIn, inSameDayAs: day) {
                result.append(.init(id: "in-\(s.id)", kind: .stay(s, checkIn: true), start: s.checkIn, end: nil,
                                    title: "Check in · \(s.name)", subtitle: s.address, coordinate: s.coordinate,
                                    symbol: "key.fill", color: .stay))
            }
            if cal.isDate(s.checkOut, inSameDayAs: day) {
                result.append(.init(id: "out-\(s.id)", kind: .stay(s, checkIn: false), start: s.checkOut, end: nil,
                                    title: "Check out · \(s.name)", subtitle: s.address, coordinate: s.coordinate,
                                    symbol: "door.left.hand.open", color: .stay))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// True when `date`, read as a calendar day in `tz`, is the same y/m/d as `day` in the trip's zone.
    static func isSameLocalDay(_ date: Date, in tz: TimeZone, as day: Date, tripCalendar: Calendar) -> Bool {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = tz
        let a = local.dateComponents([.year, .month, .day], from: date)
        let b = tripCalendar.dateComponents([.year, .month, .day], from: day)
        return a.year == b.year && a.month == b.month && a.day == b.day
    }
}


// MARK: - Day picker

private struct DayPicker: View {
    let trip: Trip
    @Binding var selectedDay: Date?
    let ideaCount: Int

    var body: some View {
        ScrollViewReader { proxy in
            HorizontalScroller {
                HStack(spacing: 8) {
                    ForEach(Array(trip.days.enumerated()), id: \.element) { index, day in
                        let selected = selectedDay.map { trip.calendar.isDate($0, inSameDayAs: day) } ?? false
                        chip(selected: selected) {
                            withAnimation(.snappy) { selectedDay = day }
                        } label: {
                            Text("\(day.weekday(in: trip.timeZone)) \(day.dayNumber(in: trip.timeZone))")
                        }
                        .id(day)
                        .accessibilityLabel("Day \(index + 1), \(day.weekdayDayMonth(in: trip.timeZone))")
                    }
                    chip(selected: selectedDay == nil) {
                        withAnimation(.snappy) { selectedDay = nil }
                    } label: {
                        Label("Ideas \(ideaCount)", systemImage: "lightbulb")
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .onAppear { if let d = selectedDay { proxy.scrollTo(d, anchor: .center) } }
        }
    }

    private func chip<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Timeline pieces

/// One compact itinerary row: colored icon, title and place, time on the right.
private struct TimelineRow: View {
    let entry: TimelineEntry
    let tz: TimeZone

    var body: some View {
        HStack(spacing: 12) {
            CircleIcon(symbol: entry.symbol, color: entry.color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
                    if let item = entry.planItem, item.isBooked {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                            .accessibilityLabel("Booked")
                    }
                }
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.start.time(in: tz)).font(.subheadline.weight(.medium)).monospacedDigit()
                if let end = entry.end {
                    Text(end.time(in: tz)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else if case .flight(let f, let departing) = entry.kind {
                    Text(departing ? f.departure.iata : f.arrival.iata).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// Travel time between two stops, shown as a quiet line under the previous row.
private struct TravelRow: View {
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let gap: TimeInterval
    @State private var estimate: TravelEstimate?

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 2, height: 18).padding(.horizontal, 15)
            if let estimate {
                let tight = gap > 0 && TimeInterval(estimate.minutes * 60) > gap
                Image(systemName: estimate.symbol)
                Text(estimate.text + (tight ? " · Tight" : ""))
                    .foregroundStyle(tight ? Color.orange : .secondary)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task(id: "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)") {
            estimate = await DirectionsService.shared.estimate(from: from, to: to)
        }
    }
}

// MARK: - Day map

struct DayMapView: View {
    let entries: [TimelineEntry]
    let stays: [Stay]
    let fallback: CLLocationCoordinate2D
    @Binding var focusedID: String?
    @State private var position: MapCameraPosition = .automatic

    /// The day's plan items, numbered in order. Airports and the hotel are left out of the numbering.
    private var stops: [(Int, TimelineEntry)] {
        entries.filter { $0.planItem != nil && $0.coordinate != nil }
            .enumerated().map { ($0.offset + 1, $0.element) }
    }

    /// Fits the day's stops (or the hotel) with a minimum span so a single stop isn't zoomed to the rooftops.
    private var fittedRegion: MKCoordinateRegion {
        var coords = stops.compactMap { $0.1.coordinate }
        if coords.isEmpty { coords = stays.map(\.coordinate) }
        if coords.isEmpty { coords = [fallback] }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.025, (lats.max()! - lats.min()!) * 1.5),
                                    longitudeDelta: max(0.025, (lons.max()! - lons.min()!) * 1.5))
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        Map(position: $position, selection: $focusedID) {
            if stops.count > 1 {
                MapPolyline(coordinates: stops.compactMap { $0.1.coordinate })
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }
            ForEach(stays) { stay in
                Marker(stay.name, systemImage: "bed.double.fill", coordinate: stay.coordinate).tint(Color.stay)
            }
            ForEach(stops, id: \.1.id) { number, entry in
                Annotation(entry.title, coordinate: entry.coordinate!) {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .scaleEffect(focusedID == entry.id ? 1.3 : 1)
                        .shadow(radius: 2, y: 1)
                }
                .tag(entry.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onAppear { position = .region(fittedRegion) }
        .onChange(of: entries.map(\.id)) { withAnimation { position = .region(fittedRegion) } }
        .overlay {
            if stops.isEmpty && stays.isEmpty {
                Text("Add places to see them on the map")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }
}

// MARK: - Ideas (unscheduled)

private struct IdeasListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let trip: Trip
    let ideas: [PlanItem]
    let onEdit: (PlanItem) -> Void

    var body: some View {
        List {
            Section {
                if ideas.isEmpty {
                    EmptyStateView(symbol: "lightbulb", title: "No saved ideas",
                                   message: "Tap + on anything in Discover to save it here, then give it a time when you're ready.",
                                   actionTitle: "Go to Discover") { app.tripSection = .discover }
                        .listRowBackground(Color.clear)
                }
                ForEach(ideas) { item in
                    HStack(spacing: 12) {
                        PlaceImage(url: item.imageURL, category: item.category, symbolSize: 18)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.body.weight(.semibold)).lineLimit(1)
                            Text(item.notes.isEmpty ? item.category.title : item.notes)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Schedule") { onEdit(item) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(item) }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item); try? context.save() }
                    }
                }
            } header: {
                if !ideas.isEmpty { Text("Saved for later") }
            } footer: {
                if !ideas.isEmpty { Text("Ideas don't have a time yet. Schedule one to add it to a day.") }
            }
            .headerProminence(.increased)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }
}
