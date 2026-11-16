import Foundation
import MapKit
import SwiftUI

#if os(iOS)
typealias PlatformImage = UIImage
extension Image { init(platformImage: PlatformImage) { self.init(uiImage: platformImage) } }
#else
typealias PlatformImage = NSImage
extension Image { init(platformImage: PlatformImage) { self.init(nsImage: platformImage) } }
#endif

/// Apple Maps results that came back from a search, so a place's Look Around view can face the
/// building itself without a second lookup. NSCache is thread-safe, so the provider can fill it
/// from any context.
enum MapItemCache {
    static let shared = NSCache<NSString, MKMapItem>()
}

/// A picture of a place that has no photo of its own: the Apple Maps Look Around street view
/// facing it, or, where there's no Look Around coverage, a small map of where it is.
struct PlaceSnapshot {
    enum Kind { case lookAround, map }
    let image: PlatformImage
    let kind: Kind
}

/// Loads and remembers place snapshots. Cards ask for one as they scroll into view; only a few
/// load at a time (newest request first, so what's on screen wins) to stay under MapKit's limits.
@MainActor
final class PlaceSnapshots {
    static let shared = PlaceSnapshots()

    private let cache = NSCache<NSString, Box>()
    private var inFlight: [String: Task<PlaceSnapshot?, Never>] = [:]
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let limit = 3
    private let size = CGSize(width: 480, height: 340)

    private final class Box { let value: PlaceSnapshot; init(_ v: PlaceSnapshot) { value = v } }

    func cached(for item: DiscoverItem) -> PlaceSnapshot? { cache.object(forKey: item.id as NSString)?.value }

    func snapshot(for item: DiscoverItem) async -> PlaceSnapshot? {
        if let hit = cached(for: item) { return hit }
        if let running = inFlight[item.id] { return await running.value }
        guard let coordinate = item.coordinate else { return nil }
        let task = Task<PlaceSnapshot?, Never> {
            await acquire()
            defer { release() }
            let result = await make(item: item, coordinate: coordinate)
            if let result { cache.setObject(Box(result), forKey: item.id as NSString) }
            return result
        }
        inFlight[item.id] = task
        let result = await task.value
        inFlight[item.id] = nil
        return result
    }

    // MARK: Making one

    private func make(item: DiscoverItem, coordinate: CLLocationCoordinate2D) async -> PlaceSnapshot? {
        if let image = await lookAround(item: item, coordinate: coordinate) {
            return PlaceSnapshot(image: image, kind: .lookAround)
        }
        if let image = await map(at: coordinate) {
            return PlaceSnapshot(image: image, kind: .map)
        }
        return nil
    }

    private func lookAround(item: DiscoverItem, coordinate: CLLocationCoordinate2D) async -> PlatformImage? {
        var mapItem = MapItemCache.shared.object(forKey: item.id as NSString)
        if mapItem == nil, let raw = item.mapItemIdentifier, let id = MKMapItem.Identifier(rawValue: raw) {
            mapItem = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
        }
        // A map item frames the place itself; a bare coordinate just finds the nearest street view.
        let request = mapItem.map { MKLookAroundSceneRequest(mapItem: $0) } ?? MKLookAroundSceneRequest(coordinate: coordinate)
        guard let scene = try? await request.scene else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        return try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
    }

    private func map(at coordinate: CLLocationCoordinate2D) async -> PlatformImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 450, longitudinalMeters: 450)
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        return try? await MKMapSnapshotter(options: options).start().image
    }

    // MARK: Throttle

    private func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        // Last in, first out: the cards the person just scrolled to load before ones they passed.
        if let next = waiters.popLast() { next.resume() } else { active -= 1 }
    }
}

/// A place's picture: its own photo if it has one (Wikipedia, Ticketmaster), otherwise the Look
/// Around street view facing it, otherwise a map of where it is.
struct PlacePhoto: View {
    let item: DiscoverItem
    var symbolSize: CGFloat = 28

    @State private var snapshot: PlaceSnapshot?

    init(item: DiscoverItem, symbolSize: CGFloat = 28) {
        self.item = item
        self.symbolSize = symbolSize
        _snapshot = State(initialValue: PlaceSnapshots.shared.cached(for: item))
    }

    var body: some View {
        if item.imageURL != nil || item.coordinate == nil {
            PlaceImage(url: item.imageURL, category: item.category, symbolSize: symbolSize)
        } else {
            item.category.color.opacity(0.15)
                .overlay {
                    if snapshot == nil {
                        Image(systemName: item.category.symbol)
                            .font(.system(size: symbolSize, weight: .medium))
                            .foregroundStyle(item.category.color.opacity(0.8))
                    }
                }
                .overlay {
                    if let snapshot {
                        Image(platformImage: snapshot.image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .overlay {
                    // A map has no building to look at, so pin the place in the middle.
                    if snapshot?.kind == .map { CategoryIcon(category: item.category, size: max(24, symbolSize)) }
                }
                .clipped()
                .task(id: item.id) {
                    guard snapshot == nil else { return }
                    let result = await PlaceSnapshots.shared.snapshot(for: item)
                    withAnimation(.easeOut(duration: 0.25)) { snapshot = result }
                }
        }
    }
}
