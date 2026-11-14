import SwiftUI

// MARK: - Colors
//
// Native iOS surfaces (grouped gray background, white cards; black and dark gray in dark mode)
// with a single warm orange accent, in the spirit of the top-rated trip apps.

extension Color {
    #if os(iOS)
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let insetBackground = Color(uiColor: .tertiarySystemFill)
    #else
    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let insetBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    #endif

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Colors for the kinds of things on an itinerary.
    static let flight = Color.blue
    static let stay = Color.indigo
    /// Slate, so drives read apart from Sights (teal) and Outdoors (green) on the timeline.
    static let drive = Color(hex: 0x4E6A8E)
}

enum Metrics {
    static let cardRadius: CGFloat = 20
    static let gutter: CGFloat = 16
    static let maxContentWidth: CGFloat = 900
}

// MARK: - Date formatting in a specific time zone

extension Date {
    func time(in tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = tz
        return formatted(style)
    }

    func dayMonth(in tz: TimeZone) -> String {
        var style = Date.FormatStyle().month(.abbreviated).day()
        style.timeZone = tz
        return formatted(style)
    }

    func weekdayDayMonth(in tz: TimeZone) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = tz
        return formatted(style)
    }

    func weekday(in tz: TimeZone, _ width: Date.FormatStyle.Symbol.Weekday = .abbreviated) -> String {
        var style = Date.FormatStyle().weekday(width)
        style.timeZone = tz
        return formatted(style)
    }

    func dayNumber(in tz: TimeZone) -> String {
        var style = Date.FormatStyle().day()
        style.timeZone = tz
        return formatted(style)
    }
}

extension TimeInterval {
    /// 40500 → "11h 15m"
    var hoursMinutes: String {
        let total = Int(self / 60)
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// "Nov 20 – 27" or "Nov 28 – Dec 3"
func dateRangeText(_ start: Date, _ end: Date, tz: TimeZone) -> String {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
    let sameMonth = cal.component(.month, from: start) == cal.component(.month, from: end)
    return "\(start.dayMonth(in: tz)) – \(sameMonth ? end.dayNumber(in: tz) : end.dayMonth(in: tz))"
}

// MARK: - Platform helpers

extension View {
    /// Inline nav titles on iOS; no-op on macOS.
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Large nav titles on iOS; no-op on macOS.
    @ViewBuilder func largeTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// Centers content and caps its width so pages read well on Mac and iPad.
    func readableWidth(_ width: CGFloat = Metrics.maxContentWidth) -> some View {
        frame(maxWidth: width, alignment: .leading).frame(maxWidth: .infinity)
    }

    /// Background-colored fade behind the status bar for screens that hide their navigation bar.
    func statusBarFade() -> some View { modifier(StatusBarFade()) }
}

private struct StatusBarFade: ViewModifier {
    @State private var top: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { top = $0 }
            .overlay(alignment: .top) {
                LinearGradient(stops: [.init(color: .appBackground, location: 0), .init(color: .appBackground, location: 0.6),
                                       .init(color: .appBackground.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: top + 20)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
    }
}
