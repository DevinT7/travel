import AppIntents
import SwiftData
import SwiftUI
import MapKit

// Siri, Shortcuts and Spotlight actions. Siri reads these phrases out of the box; with Apple
// Intelligence, "Ask TravelHub" and "Find things to do" answer with the on-device model.

// MARK: - Trip entity

struct TripEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Trip"
    static var defaultQuery = TripQuery()

    var id: UUID
    var name: String
    var destination: String
    var dates: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(destination) · \(dates)",
                              image: .init(systemName: "suitcase.fill"))
    }

    init(_ trip: Trip) {
        id = trip.id
        name = trip.displayName
        destination = trip.destinationName
        dates = dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone)
    }
}

struct TripQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TripEntity] {
        IntentData.trips().filter { identifiers.contains($0.id) }.map(TripEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TripEntity] {
        IntentData.trips()
            .filter { $0.displayName.localizedCaseInsensitiveContains(string) || $0.destinationName.localizedCaseInsensitiveContains(string) }
            .map(TripEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [TripEntity] {
        IntentData.trips().filter { $0.endDate >= .now }.map(TripEntity.init)
    }
}

/// Reads trips from the app's database for intents.
@MainActor
enum IntentData {
    static var context: ModelContext { AppData.container.mainContext }

    static func trips() -> [Trip] {
        (try? context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
    }

    /// The trip Siri named, or the one open in the app / the next upcoming trip.
    static func trip(_ entity: TripEntity?) throws -> Trip {
        let all = trips()
        if let entity, let trip = all.first(where: { $0.id == entity.id }) { return trip }
        let selected = UserDefaults.standard.string(forKey: "selectedTripID").flatMap(UUID.init(uuidString:))
        guard let trip = Trip.current(in: all, selectedID: selected) else { throw IntentFailure.noTrips }
        return trip
    }
}

enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case noTrips, placeNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noTrips: "You don't have any trips yet. Open TravelHub to plan one."
        case .placeNotFound(let name): "I couldn't find \(name) near your destination."
        }
    }
}

private func when(_ date: Date, in tz: TimeZone) -> String {
    let cal = { var c = Calendar.current; c.timeZone = tz; return c }()
    let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz))
    if cal.isDateInToday(date) { return "today at \(time)" }
    if cal.isDateInTomorrow(date) { return "tomorrow at \(time)" }
    return "\(date.formatted(Date.FormatStyle(timeZone: tz).weekday(.wide).month(.abbreviated).day())) at \(time)"
}

// MARK: - What's next

struct NextUpIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next on My Trip"
    static var description = IntentDescription("Tells you the next flight, check-in or plan on your trip.")

    @Parameter(title: "Trip") var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trip = try IntentData.trip(trip)
        let now = Date.now
        var upcoming: [(Date, String)] = []
        if let f = trip.sortedFlights.first(where: { $0.departure.best > now }) {
            upcoming.append((f.departure.best, "your flight \(f.flightNumber) to \(f.arrival.city.isEmpty ? f.arrival.iata : f.arrival.city) leaves \(when(f.departure.best, in: f.departure.timeZone))"))
        }
        if let s = trip.sortedStays.first(where: { $0.checkIn > now }) {
            upcoming.append((s.checkIn, "you check in at \(s.name) \(when(s.checkIn, in: trip.timeZone))"))
        }
        if let p = (trip.planItems ?? []).filter({ $0.isScheduled && $0.end > now }).min(by: { $0.start < $1.start }) {
            let verb = p.start <= now ? "you're at \(p.title) until \(p.end.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: trip.timeZone)))"
                                      : "\(p.title) \(when(p.start, in: trip.timeZone))"
            upcoming.append((p.start, verb))
        }
        guard let next = upcoming.min(by: { $0.0 < $1.0 }) else {
            return .result(dialog: "Nothing else is planned for \(trip.displayName). Ask me to find things to do there.")
        }
        return .result(dialog: "Next up: \(next.1).")
    }
}

// MARK: - Next flight

struct NextFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "When's My Next Flight"
    static var description = IntentDescription("Tells you when your next flight leaves, with terminal, gate and delays when known.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let flights = IntentData.trips().flatMap { $0.sortedFlights }
            .filter { $0.arrival.best > .now }
            .sorted { $0.departure.best < $1.departure.best }
        guard let f = flights.first else {
            return .result(dialog: "You don't have any upcoming flights in TravelHub.")
        }
        let to = f.arrival.city.isEmpty ? f.arrival.iata : f.arrival.city
        var text = f.departure.best <= .now
            ? "\(f.flightNumber) to \(to) is in the air, landing \(when(f.arrival.best, in: f.arrival.timeZone)) local time."
            : "\(f.flightNumber) to \(to) leaves \(f.departure.iata) \(when(f.departure.best, in: f.departure.timeZone))."
        if f.departure.best > .now {
            if let t = f.departure.terminal, let g = f.departure.gate { text += " Terminal \(t), gate \(g)." }
            else if let t = f.departure.terminal { text += " Terminal \(t)." }
            if f.departure.delayMinutes > 0 { text += " It's running \(f.departure.delayMinutes) minutes late." }
        }
        return .result(dialog: "\(text)")
    }
}

// MARK: - Find things to do

enum ThingsToDoKind: String, AppEnum {
    case sights, food, cafes, nightlife, culture, outdoors, shopping

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kind of Place"
    static var caseDisplayRepresentations: [ThingsToDoKind: DisplayRepresentation] = [
        .sights: "sights", .food: "restaurants", .cafes: "cafés", .nightlife: "nightlife",
        .culture: "museums", .outdoors: "parks and outdoors", .shopping: "shopping",
    ]

    var category: DiscoverCategory {
        switch self {
        case .sights: .sights
        case .food: .food
        case .cafes: .cafes
        case .nightlife: .nightlife
        case .culture: .culture
        case .outdoors: .outdoors
        case .shopping: .shopping
        }
    }
}

struct FindThingsToDoIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Things to Do"
    static var description = IntentDescription("Recommends sights, food, nightlife and more near where you're going.")

    @Parameter(title: "Kind", default: .sights) var kind: ThingsToDoKind
    @Parameter(title: "Trip") var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let trip = try IntentData.trip(trip)
        var places: [DiscoverItem] = []
        if kind == .sights {
            places = (try? await WikipediaProvider().sights(near: trip.coordinate)) ?? []
        }
        if places.isEmpty {
            places = (try? await MapKitPlacesProvider().search(category: kind.category, near: trip.coordinate)) ?? []
        }
        let label = ThingsToDoKind.caseDisplayRepresentations[kind]?.title ?? "places"
        guard !places.isEmpty else {
            return .result(dialog: "I couldn't find \(label) near \(trip.destinationName).", view: PlacesSnippet(places: []))
        }
        let top = Array(places.prefix(5))
        let spoken = await TripAssistant.recommend(places, kind: String(localized: label), trip: trip)
            ?? "Here are some \(String(localized: label)) in \(trip.destinationName): \(top.prefix(3).map(\.title).formatted(.list(type: .and)))."
        return .result(dialog: "\(spoken)", view: PlacesSnippet(places: top))
    }
}

private struct PlacesSnippet: View {
    let places: [DiscoverItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(places) { place in
                HStack(spacing: 10) {
                    Image(systemName: place.category.symbol)
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(place.category.color, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(place.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Save an idea

struct SaveIdeaIntent: AppIntent {
    static var title: LocalizedStringResource = "Save a Place to My Trip"
    static var description = IntentDescription("Finds a place near your destination and saves it to your trip's Ideas.")

    @Parameter(title: "Place", requestValueDialog: "What place should I save?") var place: String
    @Parameter(title: "Trip") var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trip = try IntentData.trip(trip)
        guard let found = try? await MapKitPlacesProvider().search(query: place, near: trip.coordinate).first else {
            throw IntentFailure.placeNotFound(place)
        }
        let item = PlanItem(title: found.title, category: found.category, start: trip.startDate)
        item.isScheduled = false
        item.address = found.address
        item.latitude = found.coordinate?.latitude
        item.longitude = found.coordinate?.longitude
        item.externalURLString = found.externalURL?.absoluteString
        item.sourceID = found.id
        IntentData.context.insert(item)
        item.trip = trip
        try IntentData.context.save()
        return .result(dialog: "Saved \(found.title) to your ideas for \(trip.displayName).")
    }
}

// MARK: - Ask about the trip (Apple Intelligence)

struct AskTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask About My Trip"
    static var description = IntentDescription("Ask anything about your trip, like when you land or what to do tonight. Uses Apple Intelligence on this device.")

    @Parameter(title: "Question", requestValueDialog: "What do you want to know about your trip?") var question: String
    @Parameter(title: "Trip") var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trip = try IntentData.trip(trip)
        guard TripAssistant.isAvailable else {
            return .result(dialog: "Answering questions needs Apple Intelligence turned on. You can still ask what's next or when your flight is.")
        }
        let answer = try await TripAssistant.answer(question, about: trip) ?? "I couldn't answer that."
        return .result(dialog: "\(answer)")
    }
}

// MARK: - Add to Calendar

struct AddTripToCalendarIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Trip to Calendar"
    static var description = IntentDescription("Adds the trip's flights, stays and plans to your calendar.")
    static var openAppWhenRun = true

    @Parameter(title: "Trip") var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trip = try IntentData.trip(trip)
        let added = try await CalendarExport.add(trip)
        return .result(dialog: added == 0 ? "\(trip.displayName) is already in your calendar."
                                          : "Added \(added) event\(added == 1 ? "" : "s") from \(trip.displayName) to your calendar.")
    }
}

// MARK: - Driving

/// The next drive: a saved drive leg, or the next plan stop with a place.
@MainActor
private enum NextDrive {
    struct Target { var place: DrivePlace; var arriveBy: Date?; var leg: DriveLeg?; var from: String; var trip: Trip }

    static func find() -> Target? {
        let now = Date.now
        var options: [(Date, Target)] = []
        for trip in IntentData.trips() {
            if let leg = trip.sortedDrives.first(where: { $0.arrival > now && $0.to.isSet }) {
                options.append((leg.departure, Target(place: leg.to, arriveBy: leg.travelMinutes > 0 ? leg.arrival : nil,
                                                      leg: leg, from: leg.from.name, trip: trip)))
            }
            if let p = (trip.planItems ?? []).filter({ $0.isScheduled && $0.start > now && $0.coordinate != nil })
                .min(by: { $0.start < $1.start }), let c = p.coordinate {
                options.append((p.start, Target(place: DrivePlace(name: p.title, address: p.address, coordinate: c),
                                                arriveBy: p.start, leg: nil, from: "", trip: trip)))
            }
        }
        return options.min(by: { $0.0 < $1.0 })?.1
    }
}

struct LeaveTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "When Should I Leave"
    static var description = IntentDescription("Checks traffic to your next stop and tells you when to leave.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = NextDrive.find() else {
            return .result(dialog: "You don't have anywhere to drive to coming up in TravelHub.")
        }
        let tz = next.trip.timeZone
        let fmt = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz)
        // From the drive's start, or the hotel for a plan stop.
        let origin = next.leg?.from.coordinate ?? next.trip.stay(on: next.arriveBy ?? .now)?.coordinate
        var minutes = next.leg?.travelMinutes ?? 0
        if let origin, let route = try? await DriveService.shared.route(from: origin, to: next.place.coordinate, departure: next.leg?.departure) {
            minutes = route.minutes
        }
        if let leg = next.leg {
            return .result(dialog: "Leave at \(leg.departure.formatted(fmt)) for \(next.place.name). It's about \(DriveService.durationText(minutes)) with traffic.")
        }
        guard let arrive = next.arriveBy, minutes > 0 else {
            return .result(dialog: "Your next stop is \(next.place.name).")
        }
        let leave = arrive.addingTimeInterval(-TimeInterval(minutes * 60))
        return .result(dialog: leave <= .now
            ? "You should head out now for \(next.place.name). It's about \(DriveService.durationText(minutes)) away and starts at \(arrive.formatted(fmt))."
            : "Leave by \(leave.formatted(fmt)) for \(next.place.name). It's about \(DriveService.durationText(minutes)) with traffic.")
    }
}

struct StartDriveIntent: AppIntent {
    static var title: LocalizedStringResource = "Start My Next Drive"
    static var description = IntentDescription("Opens directions in Maps to your next stop and keeps your ETA live on the Lock Screen and CarPlay.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = NextDrive.find() else {
            return .result(dialog: "You don't have anywhere to drive to coming up in TravelHub.")
        }
        if let leg = next.leg {
            DriveService.startDrive(leg)
        } else {
            DriveService.startDrive(to: next.place, from: next.from, plannedArrival: next.arriveBy, timeZone: next.trip.timeZone)
        }
        return .result(dialog: "Starting directions to \(next.place.name).")
    }
}

// MARK: - Siri phrases

struct TravelHubShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextUpIntent(), phrases: [
            "What's next on my \(.applicationName) trip",
            "What's next in \(.applicationName)",
            "What's my plan in \(.applicationName)",
        ], shortTitle: "What's Next", systemImageName: "clock")

        AppShortcut(intent: NextFlightIntent(), phrases: [
            "When's my flight in \(.applicationName)",
            "When does my flight leave in \(.applicationName)",
            "Check my flight in \(.applicationName)",
        ], shortTitle: "Next Flight", systemImageName: "airplane.departure")

        AppShortcut(intent: FindThingsToDoIntent(), phrases: [
            "Find things to do with \(.applicationName)",
            "Find \(\.$kind) with \(.applicationName)",
            "Recommend \(\.$kind) in \(.applicationName)",
            "What should I do on my \(.applicationName) trip",
        ], shortTitle: "Things to Do", systemImageName: "sparkle.magnifyingglass")

        AppShortcut(intent: AskTripIntent(), phrases: [
            "Ask \(.applicationName) about my trip",
            "Ask \(.applicationName) a question",
        ], shortTitle: "Ask About Trip", systemImageName: "bubble.left.and.text.bubble.right")

        AppShortcut(intent: SaveIdeaIntent(), phrases: [
            "Save a place to \(.applicationName)",
            "Add an idea to my \(.applicationName) trip",
        ], shortTitle: "Save a Place", systemImageName: "bookmark")

        AppShortcut(intent: LeaveTimeIntent(), phrases: [
            "When should I leave in \(.applicationName)",
            "When do I need to leave in \(.applicationName)",
            "How long is my drive in \(.applicationName)",
        ], shortTitle: "When to Leave", systemImageName: "car")

        AppShortcut(intent: StartDriveIntent(), phrases: [
            "Start my drive in \(.applicationName)",
            "Take me to my next stop with \(.applicationName)",
        ], shortTitle: "Start Drive", systemImageName: "car.fill")

        AppShortcut(intent: AddTripToCalendarIntent(), phrases: [
            "Add my trip to my calendar with \(.applicationName)",
            "Put my \(.applicationName) trip on my calendar",
        ], shortTitle: "Add to Calendar", systemImageName: "calendar.badge.plus")
    }
}
