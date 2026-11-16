import Foundation
import Observation
import CoreLocation

/// Loads and caches discover results per category for one trip.
@MainActor
@Observable
final class DiscoverModel {
    enum LoadState {
        case idle, loading, loaded([DiscoverItem]), failed(Error)

        var items: [DiscoverItem] { if case .loaded(let i) = self { i } else { [] } }
        var isLoading: Bool { if case .loading = self { true } else { false } }
        var error: Error? { if case .failed(let e) = self { e } else { nil } }
    }

    private(set) var states: [DiscoverCategory: LoadState] = [:]
    private(set) var searchResults: [DiscoverItem] = []
    private(set) var isSearching = false

    let center: CLLocationCoordinate2D
    private let start: Date
    private let end: Date

    /// - Parameter place: another city to explore; nil for the trip's destination.
    init(trip: Trip, place: ExplorePlace? = nil) {
        // Search around the hotel if there is one: that's where the traveller will be.
        center = place?.coordinate ?? trip.sortedStays.first?.coordinate ?? trip.coordinate
        start = trip.startDate
        end = trip.calendar.date(byAdding: .day, value: 1, to: trip.endDate) ?? trip.endDate
    }

    // MARK: Cache

    /// One model per search center, kept so switching between Overview, Plan and Discover doesn't
    /// load everything again.
    private static var cache: [String: DiscoverModel] = [:]
    /// The city each trip was last exploring in Discover (nil: the destination).
    static var lastPlace: [UUID: ExplorePlace] = [:]
    /// Trips where Discover has already tried starting near the person this session.
    static var triedNearMe: Set<UUID> = []
    /// Trips where the person picked a place themselves, so Discover stops choosing for them.
    static var pickedByHand: Set<UUID> = []

    static func cached(trip: Trip, place: ExplorePlace?) -> DiscoverModel {
        let center = place?.coordinate ?? trip.sortedStays.first?.coordinate ?? trip.coordinate
        // Adding or removing a Google key changes where places come from, so it gets its own entry.
        let key = "\(trip.id)|\((center.latitude * 1000).rounded()),\((center.longitude * 1000).rounded())|\(GooglePlacesProvider.isEnabled)"
        if let hit = cache[key] { return hit }
        let model = DiscoverModel(trip: trip, place: place)
        cache[key] = model
        return model
    }

    func state(for c: DiscoverCategory) -> LoadState { states[c] ?? .idle }

    func load(_ category: DiscoverCategory, force: Bool = false) async {
        if !force {
            switch states[category] {
            case .loading?, .loaded?: return
            default: break
            }
        }
        states[category] = .loading
        do {
            let items: [DiscoverItem]
            switch category {
            case .sights:
                async let wiki = WikipediaProvider().sights(near: center)
                async let landmarks = try? MapKitPlacesProvider().search(category: .sights, near: center)
                // Wikipedia has photos; Apple Maps fills gaps with named landmarks.
                let w = try await wiki
                let names = Set(w.map { $0.title.lowercased() })
                let extra = (await landmarks ?? []).filter { !names.contains($0.title.lowercased()) }
                items = w + extra
            case .events:
                items = try await TicketmasterProvider().events(near: center, from: start, to: end)
            default:
                // Google adds ratings and hours; Apple Maps is the free fallback if it isn't set up or fails.
                if GooglePlacesProvider.isEnabled,
                   let google = try? await GooglePlacesProvider().search(category: category, near: center), !google.isEmpty {
                    items = google
                } else {
                    items = try await MapKitPlacesProvider().search(category: category, near: center)
                }
            }
            states[category] = .loaded(items)
        } catch {
            states[category] = .failed(error)
        }
    }

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await MapKitPlacesProvider().search(query: q, near: center)) ?? []
    }

    func clearSearch() { searchResults = [] }

    func distance(to item: DiscoverItem) -> CLLocationDistance? {
        guard let c = item.coordinate else { return nil }
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
    }
}
