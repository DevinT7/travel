import SwiftUI
import SwiftData

@main
struct TravelHubApp: App {
    @State private var model = AppModel()

    /// Local store. To sync between iPhone and Mac, add the iCloud capability with a
    /// CloudKit container in Xcode and change `cloudKitDatabase` to `.automatic`.
    let container: ModelContainer = {
        let schema = Schema([Trip.self, FlightSegment.self, Stay.self, PlanItem.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the trip database: \(error)")
        }
    }()

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

enum AppTab: Hashable { case trip, discover, plan, trips }

/// App-wide UI state: which trip is open, which tab, and global sheets.
@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .trip
    var isPresentingNewTrip = false
    var isPresentingSettings = false

    var selectedTripID: UUID? {
        didSet { UserDefaults.standard.set(selectedTripID?.uuidString, forKey: "selectedTripID") }
    }

    init() {
        selectedTripID = UserDefaults.standard.string(forKey: "selectedTripID").flatMap(UUID.init(uuidString:))
    }

    /// The selected trip, or the next upcoming / ongoing one.
    func currentTrip(from trips: [Trip]) -> Trip? {
        if let id = selectedTripID, let trip = trips.first(where: { $0.id == id }) { return trip }
        let now = Date.now
        return trips.filter { $0.endDate >= now }.min { $0.startDate < $1.startDate } ?? trips.last
    }
}
