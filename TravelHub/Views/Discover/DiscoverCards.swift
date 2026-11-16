import SwiftUI
import MapKit

func distanceText(_ d: CLLocationDistance?) -> String? {
    d.map { Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)) }
}

/// Photo card: the place's photo (or its Look Around street view) on top, name and details underneath.
struct DiscoverCard: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSaved: Bool
    var photoHeight: CGFloat = 160
    let onOpen: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacePhoto(item: item)
                .frame(height: photoHeight)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { SaveButton(isSaved: isSaved, action: onToggleSave).padding(10) }
                .overlay(alignment: .topLeading) {
                    if let date = item.eventDate {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: isSaved ? "Remove from plan" : "Save to plan", onToggleSave)
    }

    private var detailLine: String {
        [distanceText(distance), item.priceText, item.subtitle].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Big photo card at the top of "For You" and of each category.
struct FeaturedCard: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSaved: Bool
    var label = "Top pick"
    var height: CGFloat = 300
    let onOpen: () -> Void
    /// Shows a + / check button; without it, a "Saved" tag appears once the place is in the plan.
    var onToggleSave: (() -> Void)? = nil

    var body: some View {
        PlacePhoto(item: item, symbolSize: 40)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption.weight(.semibold)).opacity(0.85)
                    Text(item.title).font(.title2.bold()).lineLimit(2)
                    Text([item.subtitle, distanceText(distance)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).opacity(0.85).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .overlay(alignment: .topTrailing) {
                if let onToggleSave {
                    SaveButton(isSaved: isSaved, action: onToggleSave).padding(12)
                } else if isSaved {
                    Label("Saved", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor, in: Capsule())
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }
}

/// Skeleton shown while a category loads.
struct PlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.insetBackground).frame(height: 160)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.insetBackground).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Color.insetBackground).frame(width: 100, height: 10)
            }
            .padding(12)
            .frame(height: 64, alignment: .top)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Map of a category's results with a strip of cards along the bottom. Tapping a pin brings its
/// card into view and swiping the cards moves the highlighted pin; tapping a card opens the place.
struct DiscoverMapView: View {
    let items: [DiscoverItem]
    let distance: (DiscoverItem) -> CLLocationDistance?
    let onOpen: (DiscoverItem) -> Void
    @State private var selection: String?
    @State private var position: MapCameraPosition
    /// How far out the camera is, so following the cards keeps the zoom the person chose.
    @State private var cameraDistance: CLLocationDistance = 3000

    init(items: [DiscoverItem], distance: @escaping (DiscoverItem) -> CLLocationDistance?, onOpen: @escaping (DiscoverItem) -> Void) {
        self.items = items
        self.distance = distance
        self.onOpen = onOpen
        _position = State(initialValue: Self.fitting(items))
    }

    private var mapped: [DiscoverItem] { items.filter { $0.coordinate != nil } }

    /// A region around every pin, with room at the bottom for the cards.
    private static func fitting(_ items: [DiscoverItem]) -> MapCameraPosition {
        let coords = items.compactMap(\.coordinate)
        guard let first = coords.first else { return .automatic }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let latSpan = max(0.008, (maxLat - minLat) * 1.3)
        return .region(MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2 - latSpan * 0.15, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: latSpan * 1.4, longitudeDelta: max(0.008, (maxLon - minLon) * 1.3))))
    }

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(mapped) { item in
                Marker(item.title, systemImage: item.category.symbol, coordinate: item.coordinate!)
                    .tint(item.category.color)
                    .tag(item.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange { cameraDistance = $0.camera.distance }
        .onChange(of: selection) { _, id in
            // Swiping the cards (or tapping a pin) brings that place to the middle of the map.
            guard let id, let c = items.first(where: { $0.id == id })?.coordinate else { return }
            withAnimation(.smooth) {
                position = .camera(MapCamera(centerCoordinate: c, distance: min(cameraDistance, 6000)))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(mapped) { item in
                        MapPlaceCard(item: item, distance: distance(item), isSelected: selection == item.id) { onOpen(item) }
                            .frame(width: 280)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 12)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection, anchor: .center)
            .padding(.bottom, 12)
        }
    }
}

/// Small horizontal card floating over the map: photo, name, details.
private struct MapPlaceCard: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PlacePhoto(item: item, symbolSize: 18)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text([distanceText(distance), item.kind ?? item.subtitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? item.category.color : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Rounded filter button ("All", "Restaurant", "Bakery").
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(Color.cardBackground), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One place in a list: colored icon, name, area and distance, and a save button.
struct CompactPlaceRow: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSaved: Bool
    let onOpen: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlacePhoto(item: item, symbolSize: 18)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text([distanceText(distance), item.subtitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onToggleSave) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isSaved ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSaved ? "Saved to plan" : "Save to plan")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }
}

/// A run of place rows in one card, separated by inset dividers.
struct PlaceList: View {
    let items: [DiscoverItem]
    let distance: (DiscoverItem) -> CLLocationDistance?
    let isSaved: (DiscoverItem) -> Bool
    let onOpen: (DiscoverItem) -> Void
    let onToggleSave: (DiscoverItem) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                CompactPlaceRow(item: item, distance: distance(item), isSaved: isSaved(item),
                                onOpen: { onOpen(item) }, onToggleSave: { onToggleSave(item) })
                if i < items.count - 1 { Divider().padding(.leading, 84) }
            }
        }
        .padding(.vertical, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

/// Round category button with a label underneath, like Apple Maps' search shortcuts.
struct CategoryCircle: View {
    let title: String
    let symbol: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : color)
                    .frame(width: 52, height: 52)
                    .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15)), in: Circle())
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 68)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
