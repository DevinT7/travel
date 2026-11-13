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
            DayStrip(trip: trip, selectedDay: $selectedDay, ideaCount: ideas.count)
                .padding(.vertical, 10)
            Divider()
            if let day = selectedDay {
                let entries = entries(for: day)
                if isWide {
                    HStack(spacing: 0) {
                        timeline(entries, day: day).frame(minWidth: 380, idealWidth: 460, maxWidth: 520)
                        Divider()
                        DayMapView(entries: entries, stays: trip.sortedStays, fallback: trip.coordinate, focusedID: $focusedEntryID)
                    }
                } else {
                    timeline(entries, day: day, mapHeader: true)
                }
            } else {
                IdeasListView(trip: trip, ideas: ideas, onEdit: { editing = $0 })
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Plan")
        .inlineTitle()
        .toolbar {
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
    private func timeline(_ entries: [TimelineEntry], day: Date, mapHeader: Bool = false) -> some View {
        List {
            if mapHeader {
                DayMapView(entries: entries, stays: trip.sortedStays, fallback: trip.coordinate, focusedID: $focusedEntryID)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Text(day.formatted(Date.FormatStyle(timeZone: trip.timeZone).weekday(.wide).month(.wide).day()))
                .font(.title2.bold())
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if entries.isEmpty {
                EmptyStateView(symbol: "sun.max", title: "Nothing planned yet",
                               message: "Find things to do in Discover, or add your own plans.",
                               actionTitle: "Discover \(trip.destinationName)") { app.selectedTab = .discover }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                TimelineRow(entry: entry, tz: entry.timeZone ?? trip.timeZone, isFirst: index == 0, isLast: index == entries.count - 1,
                            isFocused: focusedEntryID == entry.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedEntryID = entry.id
                        if let item = entry.planItem { editing = item }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
                    .contextMenu {
                        if let item = entry.planItem {
                            Button("Edit", systemImage: "pencil") { editing = item }
                            Button("Move to Ideas", systemImage: "tray.and.arrow.down") { item.isScheduled = false; try? context.save() }
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item); try? context.save() }
                        }
                    }

                if index < entries.count - 1, let a = entry.coordinate, let b = entries[index + 1].coordinate {
                    TravelConnector(from: a, to: b, gap: entries[index + 1].start.timeIntervalSince(entry.end ?? entry.start))
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func entries(for day: Date) -> [TimelineEntry] {
        let cal = trip.calendar
        var result: [TimelineEntry] = []
        for p in trip.planItems ?? [] where p.isScheduled && cal.isDate(p.start, inSameDayAs: day) {
            let sub = [p.address, p.notes].first { !$0.isEmpty } ?? p.category.title
            result.append(.init(id: p.id.uuidString, kind: .plan(p), start: p.start, end: p.end, title: p.title,
                                subtitle: sub, coordinate: p.coordinate, symbol: p.category.symbol, color: p.category.color))
        }
        for f in trip.sortedFlights {
            if Self.isSameLocalDay(f.departure.best, in: f.departure.timeZone, as: day, tripCalendar: cal) {
                result.append(.init(id: "dep-\(f.id)", kind: .flight(f, departing: true), start: f.departure.best, end: nil,
                                    title: "\(f.flightNumber) to \(f.arrival.city)",
                                    subtitle: "Departs \(f.departure.iata)" + (f.departure.gate.map { " · Gate \($0)" } ?? ""),
                                    coordinate: f.departure.coordinate, symbol: "airplane.departure", color: .blue,
                                    timeZone: f.departure.timeZone))
            }
            if Self.isSameLocalDay(f.arrival.best, in: f.arrival.timeZone, as: day, tripCalendar: cal) {
                result.append(.init(id: "arr-\(f.id)", kind: .flight(f, departing: false), start: f.arrival.best, end: nil,
                                    title: "Land in \(f.arrival.city)",
                                    subtitle: "\(f.flightNumber) · \(f.arrival.iata)" + (f.arrival.baggageBelt.map { " · Belt \($0)" } ?? ""),
                                    coordinate: f.arrival.coordinate, symbol: "airplane.arrival", color: .blue,
                                    timeZone: f.arrival.timeZone))
            }
        }
        for s in trip.sortedStays {
            if cal.isDate(s.checkIn, inSameDayAs: day) {
                result.append(.init(id: "in-\(s.id)", kind: .stay(s, checkIn: true), start: s.checkIn, end: nil,
                                    title: "Check in · \(s.name)", subtitle: s.address, coordinate: s.coordinate,
                                    symbol: "key.fill", color: .indigo))
            }
            if cal.isDate(s.checkOut, inSameDayAs: day) {
                result.append(.init(id: "out-\(s.id)", kind: .stay(s, checkIn: false), start: s.checkOut, end: nil,
                                    title: "Check out · \(s.name)", subtitle: s.address, coordinate: s.coordinate,
                                    symbol: "door.left.hand.open", color: .indigo))
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

// MARK: - Day selector

private struct DayStrip: View {
    let trip: Trip
    @Binding var selectedDay: Date?
    let ideaCount: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(trip.days.enumerated()), id: \.element) { index, day in
                        let selected = selectedDay.map { trip.calendar.isDate($0, inSameDayAs: day) } ?? false
                        let count = (trip.planItems ?? []).filter { $0.isScheduled && trip.calendar.isDate($0.start, inSameDayAs: day) }.count
                        Button {
                            withAnimation(.snappy) { selectedDay = day }
                        } label: {
                            VStack(spacing: 3) {
                                Text("Day \(index + 1)").font(.caption2.weight(.semibold)).opacity(0.8)
                                Text(day.weekday(in: trip.timeZone)).font(.caption.weight(.bold))
                                Text(day.dayNumber(in: trip.timeZone)).font(.title3.weight(.bold))
                                Circle()
                                    .fill(count > 0 ? (selected ? Color.white : Color.accentColor) : .clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(width: 58, height: 82)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.cardBackground),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(day)
                    }
                    Button {
                        withAnimation(.snappy) { selectedDay = nil }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill").font(.title3)
                            Text("Ideas").font(.caption.weight(.bold))
                            Text("\(ideaCount)").font(.caption2.weight(.semibold)).opacity(0.8)
                        }
                        .frame(width: 64, height: 82)
                        .foregroundStyle(selectedDay == nil ? Color.white : Color.orange)
                        .background(selectedDay == nil ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.orange.opacity(0.12)),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .onAppear { if let d = selectedDay { proxy.scrollTo(d, anchor: .center) } }
        }
    }
}

// MARK: - Timeline pieces

private struct TimelineRow: View {
    let entry: TimelineEntry
    let tz: TimeZone
    let isFirst: Bool
    let isLast: Bool
    let isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.start.time(in: tz)).font(.subheadline.weight(.semibold)).monospacedDigit()
                if case .flight(let f, let departing) = entry.kind {
                    Text(departing ? f.departure.iata : f.arrival.iata)
                        .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                if let end = entry.end {
                    Text(end.time(in: tz)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(width: 70, alignment: .trailing)
            .padding(.top, 14)

            // Rail with the node icon.
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 2)
                    .padding(.top, isFirst ? 22 : 0)
                    .padding(.bottom, isLast ? 0 : 0)
                    .frame(maxHeight: isLast ? 22 : .infinity, alignment: .top)
                Image(systemName: entry.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(entry.color.gradient, in: Circle())
                    .overlay(Circle().stroke(Color.appBackground, lineWidth: 3))
                    .padding(.top, 8)
            }
            .frame(width: 32)
            .frame(maxHeight: .infinity, alignment: .top)

            content
                .padding(.vertical, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(.headline).lineLimit(2)
                Spacer(minLength: 4)
                if let item = entry.planItem, item.isBooked {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).accessibilityLabel("Booked")
                }
            }
            Text(entry.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if let item = entry.planItem {
                Text(PlanItemEditor.durationLabel(item.durationMinutes))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(entry.color.opacity(0.14), in: Capsule())
                    .foregroundStyle(entry.color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: isFocused ? 2 : 0))
    }
}

/// Dashed rail segment between two stops with the estimated travel time.
private struct TravelConnector: View {
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let gap: TimeInterval
    @State private var estimate: TravelEstimate?

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 70)
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 2, height: 34)
                .frame(width: 32)
            if let estimate {
                let tight = gap > 0 && TimeInterval(estimate.minutes * 60) > gap
                Label(estimate.text, systemImage: estimate.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tight ? .orange : .secondary)
                if tight {
                    Text("Tight").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                }
            }
            Spacer()
        }
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
                    .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }
            ForEach(stays) { stay in
                Marker(stay.name, systemImage: "bed.double.fill", coordinate: stay.coordinate).tint(.indigo)
            }
            ForEach(stops, id: \.1.id) { number, entry in
                Annotation(entry.title, coordinate: entry.coordinate!) {
                    Text("\(number)")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(entry.color, in: Circle())
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
                                   actionTitle: "Go to Discover") { app.selectedTab = .discover }
                        .listRowBackground(Color.clear)
                }
                ForEach(ideas) { item in
                    HStack(spacing: 14) {
                        PlaceImage(url: item.imageURL, category: item.category)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline)
                            Text(item.notes.isEmpty ? item.category.title : item.notes)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Schedule") { onEdit(item) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(item) }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item); try? context.save() }
                    }
                }
            } header: {
                if !ideas.isEmpty { Text("Saved for later") }
            }
        }
        .scrollContentBackground(.hidden)
    }
}
