import SwiftUI
import SwiftData

@main
struct TravelHubApp: App {
    @State private var model = AppModel()

    let container = AppData.container

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
        #if os(iOS)
        // iOS wakes the app now and then to refresh flight status for the Lock Screen.
        .backgroundTask(.appRefresh(FlightBackgroundRefresh.taskID)) {
            await FlightBackgroundRefresh.run()
        }
        #endif
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Trip…") { model.isPresentingNewTrip = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 520, height: 560)
                .modelContainer(container)
        }
        #endif
    }
}

/// The trip database, shared by the app and its Siri / Shortcuts actions.
enum AppData {
    /// Local store. To sync between iPhone and Mac, add the iCloud capability with a
    /// CloudKit container in Xcode and change `cloudKitDatabase` to `.automatic`.
    static let container: ModelContainer = {
        let schema = Schema([Trip.self, FlightSegment.self, Stay.self, PlanItem.self, DriveLeg.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the trip database: \(error)")
        }
    }()
}

/// The sections inside a trip, switched from the top of the trip page.
enum TripSection: String, CaseIterable, Hashable {
    case overview, plan, discover

    var title: String {
        switch self {
        case .overview: "Overview"
        case .plan: "Plan"
        case .discover: "Discover"
        }
    }
}

/// App-wide UI state: which trip is open, which section of it, and global sheets.
///
/// The app opens on the Trips list. Opening a trip pushes it (iPhone) or shows it next to the
/// sidebar (iPad, Mac).
@MainActor
@Observable
final class AppModel {
    var tripSection: TripSection = .overview
    var isPresentingNewTrip = false
    /// Confirmation text pasted on the welcome screen, read when New Trip opens.
    var newTripConfirmationText: String?
    var isPresentingSettings = false
    /// iPhone navigation stack: the trip pushed on top of the Trips list, if any.
    var path: [UUID] = []

    /// The open trip (and the one Siri means by "my trip"). Kept when going back to the list.
    var selectedTripID: UUID? {
        didSet { UserDefaults.standard.set(selectedTripID?.uuidString, forKey: "selectedTripID") }
    }

    init() {
        selectedTripID = UserDefaults.standard.string(forKey: "selectedTripID").flatMap(UUID.init(uuidString:))
    }

    func open(_ trip: Trip, section: TripSection = .overview) {
        selectedTripID = trip.id
        tripSection = section
        path = [trip.id]
    }

    /// On launch, go straight into a trip that's happening today; otherwise stay on the list.
    func openOngoingTrip(from trips: [Trip]) {
        let today = Date.now
        guard path.isEmpty, let ongoing = trips.first(where: { trip in
            let cal = trip.calendar
            return cal.startOfDay(for: trip.startDate) <= today
                && today < cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: trip.endDate))!
        }) else { return }
        open(ongoing)
    }

    /// The selected trip, or the next upcoming / ongoing one.
    func currentTrip(from trips: [Trip]) -> Trip? {
        Trip.current(in: trips, selectedID: selectedTripID)
    }
}

extension Trip {
    /// The selected trip, or the ongoing / next upcoming one.
    static func current(in trips: [Trip], selectedID: UUID?) -> Trip? {
        if let selectedID, let trip = trips.first(where: { $0.id == selectedID }) { return trip }
        let now = Date.now
        return trips.filter { $0.endDate >= now }.min { $0.startDate < $1.startDate } ?? trips.last
    }
}
