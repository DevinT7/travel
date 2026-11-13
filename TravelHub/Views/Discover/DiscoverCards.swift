import SwiftUI
import MapKit

func distanceText(_ d: CLLocationDistance?) -> String? {
    d.map { Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)) }
}

/// Photo card used for sights and events: photo on top, name and details underneath.
struct DiscoverCard: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSaved: Bool
    let onOpen: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaceImage(url: item.imageURL, category: item.category)
                .frame(height: 160)
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

/// Big photo card at the top of "For You".
struct FeaturedCard: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSaved: Bool
    let onOpen: () -> Void

    var body: some View {
        PlaceImage(url: item.imageURL, category: item.category)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top pick").font(.caption.weight(.semibold)).opacity(0.85)
                    Text(item.title).font(.title2.bold()).lineLimit(2)
                    Text([item.subtitle, distanceText(distance)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).opacity(0.85).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .overlay(alignment: .topTrailing) {
                if isSaved {
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

/// Map view of a category's results.
struct DiscoverMapView: View {
    let items: [DiscoverItem]
    let onOpen: (DiscoverItem) -> Void
    @State private var selection: String?

    var body: some View {
        Map(selection: $selection) {
            ForEach(items.filter { $0.coordinate != nil }) { item in
                Marker(item.title, systemImage: item.category.symbol, coordinate: item.coordinate!)
                    .tint(item.category.color)
                    .tag(item.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: selection) { _, id in
            if let id, let item = items.first(where: { $0.id == id }) {
                onOpen(item)
                selection = nil
            }
        }
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
            CategoryIcon(category: item.category, size: 36)
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
                if i < items.count - 1 { Divider().padding(.leading, 64) }
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
