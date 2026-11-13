import SwiftUI
import MapKit

/// Photo card used in carousels and grids.
struct DiscoverCard: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSaved: Bool
    let onOpen: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaceImage(url: item.imageURL, category: item.category)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    if let date = item.eventDate {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: item.category.symbol).foregroundStyle(item.category.color)
                    if let distance {
                        Text(Measurement(value: distance, unit: UnitLength.meters)
                            .formatted(.measurement(width: .abbreviated, usage: .road)))
                    }
                    if let price = item.priceText { Text("· \(price)") }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .padding(12)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) { saveButton.padding(10) }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: isSaved ? "Remove from plan" : "Save to plan", onToggleSave)
    }

    private var saveButton: some View {
        Button(action: onToggleSave) {
            Image(systemName: isSaved ? "checkmark" : "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSaved ? Color.white : Color.primary)
                .frame(width: 32, height: 32)
                .background {
                    if isSaved { Circle().fill(Color.accentColor) } else { Circle().fill(.regularMaterial) }
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Saved to plan" : "Save to plan")
    }
}

/// Big hero card at the top of "For You".
struct FeaturedCard: View {
    let item: DiscoverItem
    let isSaved: Bool
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PlaceImage(url: item.imageURL, category: item.category)
                .frame(height: 280)
                .frame(maxWidth: .infinity)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("MUST SEE").font(.caption.weight(.heavy)).tracking(1).opacity(0.85)
                Text(item.title).font(.system(.title, design: .rounded).bold())
                Text(item.subtitle).font(.subheadline).opacity(0.9).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(20)
            if isSaved {
                Label("In your plan", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }
}

/// Shimmer-free skeleton shown while a category loads.
struct PlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.insetBackground).frame(height: 150)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.insetBackground).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).fill(Color.insetBackground).frame(width: 120, height: 10)
            }
            .padding(12)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .redacted(reason: .placeholder)
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
        .onChange(of: selection) { _, id in
            if let id, let item = items.first(where: { $0.id == id }) {
                onOpen(item)
                selection = nil
            }
        }
    }
}

/// Dense row for places without photos (Apple Maps results): icon, name, area, distance.
struct CompactPlaceRow: View {
    let item: DiscoverItem
    let distance: CLLocationDistance?
    let isSaved: Bool
    let onOpen: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.category, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let distance {
                    Text(Measurement(value: distance, unit: UnitLength.meters)
                        .formatted(.measurement(width: .abbreviated, usage: .road)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
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
        .padding(12)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }
}
