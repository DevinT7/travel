import SwiftUI

/// Rounded surface used for every card in the app.
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
            trailing.font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 4)
    }
}

/// Square icon tile in a category's color. Used when a place has no photo.
struct CategoryIcon: View {
    let category: DiscoverCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Photo for a place, falling back to a soft category gradient with its symbol.
struct PlaceImage: View {
    let url: URL?
    let category: DiscoverCategory

    var body: some View {
        // The photo lives in an overlay so its natural size can never stretch the card.
        LinearGradient(colors: [category.color.opacity(0.85), category.color.opacity(0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
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

/// Filter chip used for category rows.
struct Chip: View {
    let title: String
    var symbol: String?
    var tint: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.cardBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(isSelected ? 0 : 0.08)))
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
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
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
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
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
            Image(systemName: symbol).foregroundStyle(.orange).font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action).font(.subheadline.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
