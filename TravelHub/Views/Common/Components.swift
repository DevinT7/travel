import SwiftUI

/// White (dark gray in dark mode) rounded card on the grouped background.
struct CardBackground: ViewModifier {
    var padding: CGFloat = Metrics.gutter
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Metrics.gutter) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Bold section title with an optional trailing action ("See All").
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            trailing
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 4)
    }
}

/// "See All" style text button in the accent color.
struct SeeAllButton: View {
    var title = "See All"
    let action: () -> Void
    var body: some View {
        Button(title, action: action).foregroundStyle(.tint)
    }
}

/// Filled circle with a white glyph, like Apple Maps place icons.
struct CircleIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
    }
}

struct CategoryIcon: View {
    let category: DiscoverCategory
    var size: CGFloat = 30
    var body: some View { CircleIcon(symbol: category.symbol, color: category.color, size: size) }
}

/// Photo for a place, falling back to a soft tint of its category with the symbol.
struct PlaceImage: View {
    let url: URL?
    let category: DiscoverCategory
    var symbolSize: CGFloat = 28

    var body: some View {
        // The photo lives in an overlay so its natural size can never stretch the card.
        category.color.opacity(0.15)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: symbolSize, weight: .medium))
                    .foregroundStyle(category.color.opacity(0.8))
            }
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.25))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipped()
    }
}

/// Round quick-action button with a label underneath (Tripsy-style).
struct QuickAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 54, height: 54)
                    .background(Color.cardBackground, in: Circle())
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
    }
}

/// Small capsule used for flight status and other states.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

/// Friendly empty state with an optional call to action.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Inline message for API errors (e.g. missing key) with a shortcut to Settings.
struct NoticeBanner: View {
    let symbol: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action).font(.subheadline.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }
}

/// Round "+" / check button used on photo cards.
struct SaveButton: View {
    let isSaved: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
