import Foundation
import SwiftUI
import MapKit

/// What a discovered place or event is. Drives icon, color and which data source is queried.
enum DiscoverCategory: String, CaseIterable, Identifiable, Codable {
    case sights, food, cafes, nightlife, culture, outdoors, shopping, events, other

    var id: String { rawValue }

    static var browsable: [DiscoverCategory] { [.sights, .food, .cafes, .culture, .outdoors, .nightlife, .shopping, .events] }

    var title: String {
        switch self {
        case .sights: "Sights"
        case .food: "Food"
        case .cafes: "Cafés"
        case .nightlife: "Nightlife"
        case .culture: "Museums & Arts"
        case .outdoors: "Outdoors"
        case .shopping: "Shopping"
        case .events: "Events"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .sights: "building.columns.fill"
        case .food: "fork.knife"
        case .cafes: "cup.and.saucer.fill"
        case .nightlife: "wineglass.fill"
        case .culture: "theatermasks.fill"
        case .outdoors: "leaf.fill"
        case .shopping: "bag.fill"
        case .events: "ticket.fill"
        case .other: "mappin"
        }
    }

    var color: Color {
        switch self {
        case .sights: Color(red: 0.95, green: 0.55, blue: 0.15)
        case .food: Color(red: 0.93, green: 0.33, blue: 0.31)
        case .cafes: Color(red: 0.62, green: 0.43, blue: 0.30)
        case .nightlife: Color(red: 0.58, green: 0.35, blue: 0.86)
        case .culture: Color(red: 0.86, green: 0.30, blue: 0.56)
        case .outdoors: Color(red: 0.20, green: 0.68, blue: 0.40)
        case .shopping: Color(red: 0.95, green: 0.70, blue: 0.10)
        case .events: Color(red: 0.12, green: 0.55, blue: 0.95)
        case .other: .gray
        }
    }

    /// Typical time spent, used as the default duration when added to the plan.
    var defaultDurationMinutes: Int {
        switch self {
        case .sights, .culture: 90
        case .food: 75
        case .cafes: 45
        case .nightlife, .events: 150
        case .outdoors: 120
        case .shopping: 60
        case .other: 60
        }
    }

    /// Apple Maps point-of-interest categories used for this tab.
    var mapKitCategories: [MKPointOfInterestCategory] {
        switch self {
        case .food: [.restaurant, .bakery, .foodMarket]
        case .cafes: [.cafe, .bakery]
        case .nightlife: [.nightlife, .brewery, .winery, .distillery, .musicVenue]
        case .culture: [.museum, .theater, .musicVenue, .planetarium]
        case .outdoors: [.park, .nationalPark, .beach, .hiking, .zoo, .aquarium, .marina]
        case .shopping: [.store, .foodMarket]
        case .sights: [.landmark, .castle, .nationalMonument, .fortress]
        case .events, .other: []
        }
    }

    /// Natural-language query sent to MapKit along with the category filter.
    var mapKitQuery: String {
        switch self {
        case .food: "restaurants"
        case .cafes: "coffee"
        case .nightlife: "bars"
        case .culture: "museums"
        case .outdoors: "parks"
        case .shopping: "shopping"
        case .sights: "landmarks"
        case .events, .other: ""
        }
    }

    init(mapKitCategory: MKPointOfInterestCategory?) {
        guard let c = mapKitCategory else { self = .other; return }
        self = DiscoverCategory.browsable.first { $0.mapKitCategories.contains(c) } ?? .other
    }
}

/// Where a discovered item came from. Shown as attribution on detail pages.
enum DiscoverSource: String, Codable {
    case appleMaps = "Apple Maps"
    case wikipedia = "Wikipedia"
    case ticketmaster = "Ticketmaster"
    case custom = "Custom"
}

/// A normalized result from any data source, ready to show as a card.
struct DiscoverItem: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var category: DiscoverCategory
    var source: DiscoverSource
    var coordinate: CLLocationCoordinate2D?
    var address: String = ""
    var imageURL: URL?
    var summary: String?
    var externalURL: URL?
    /// Events only: when it starts.
    var eventDate: Date?
    var priceText: String?
    var phone: String?
    /// MapKit only: lets the detail view open Apple's full place card.
    var mapItemIdentifier: String?

    static func == (lhs: DiscoverItem, rhs: DiscoverItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
