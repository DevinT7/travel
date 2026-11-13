import SwiftUI

// MARK: - Colors that work on both iOS and macOS

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
}

enum Metrics {
    static let cardRadius: CGFloat = 20
    static let gutter: CGFloat = 16
    static let maxContentWidth: CGFloat = 980
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

    /// Centers content and caps its width so pages read well on Mac and iPad.
    func readableWidth(_ width: CGFloat = Metrics.maxContentWidth) -> some View {
        frame(maxWidth: width, alignment: .leading).frame(maxWidth: .infinity)
    }
}
