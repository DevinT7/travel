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
        let schema = Schema([Trip.self, FlightSegment.self, Stay.self, PlanItem.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the trip database: \(error)")
        }
    }()
}

enum AppTab: Hashable { case trip, discover, plan, trips }

/// App-wide UI state: which trip is open, which tab, and global sheets.
@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .trip
    var isPresentingNewTrip = false
    /// Confirmation text pasted on the welcome screen, read when New Trip opens.
    var newTripConfirmationText: String?
    var isPresentingSettings = false

    var selectedTripID: UUID? {
        didSet { UserDefaults.standard.set(selectedTripID?.uuidString, forKey: "selectedTripID") }
    }

    init() {
        selectedTripID = UserDefaults.standard.string(forKey: "selectedTripID").flatMap(UUID.init(uuidString:))
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
