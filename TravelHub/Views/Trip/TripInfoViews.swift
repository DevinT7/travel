import SwiftUI

/// The forecast as a row of days inside one card.
struct WeatherStripView: View {
    let forecast: [DailyForecast]
    let loaded: Bool
    let tz: TimeZone

    /// Multicolor weather symbols draw clouds in white, which vanish on a white card,
    /// so each symbol gets a single readable tint instead.
    static func tint(for symbol: String) -> Color {
        if symbol.contains("bolt") { return .purple }
        if symbol.contains("snow") || symbol.contains("sleet") { return .cyan }
        if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("heavy") { return .blue }
        if symbol.contains("sun") { return .orange }
        return .gray
    }

    var body: some View {
        if forecast.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: loaded ? "calendar.badge.clock" : "cloud.sun")
                    .font(.title2).symbolRenderingMode(.multicolor)
                Text(loaded ? "The forecast appears about two weeks before you leave."
                            : "Loading the forecast…")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .card()
        } else {
            HorizontalScroller {
                HStack(spacing: 4) {
                    ForEach(forecast) { day in
                        VStack(spacing: 8) {
                            Text(day.date.weekday(in: tz)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Image(systemName: day.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Self.tint(for: day.symbol))
                                .font(.title3)
                                .frame(height: 26)
                            Text("\(Int(day.high.rounded()))°").font(.subheadline.weight(.semibold))
                            Text("\(Int(day.low.rounded()))°").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 52)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(day.date.weekday(in: tz, .wide)): \(day.label), high \(Int(day.high)), low \(Int(day.low))")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}

/// Local time, currency and country as a short list in one card.
struct LocalInfoView: View {
    let trip: Trip
    let exchangeRate: Double?

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                row(symbol: "clock.fill", color: .blue, title: "Local time",
                    value: context.date.time(in: trip.timeZone), detail: timeDifference(at: context.date))
            }
            if let currency = CurrencyService.currency(forCountry: trip.countryCode) {
                Divider().padding(.leading, 52)
                row(symbol: "banknote.fill", color: .green, title: "Currency", value: currency, detail: currencyDetail(dest: currency))
            }
            if let code = trip.countryCode, let country = Locale.current.localizedString(forRegionCode: code) {
                Divider().padding(.leading, 52)
                row(symbol: "globe", color: .orange, title: "Country", value: country,
                    detail: trip.timeZone.localizedName(for: .generic, locale: .current) ?? trip.timeZone.identifier)
            }
        }
        .padding(.vertical, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func row(symbol: String, color: Color, title: String, value: String, detail: String) -> some View {
        HStack(spacing: 12) {
            CircleIcon(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
    }

    private func timeDifference(at date: Date) -> String {
        let diff = trip.timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if diff == 0 { return "Same time as you" }
        let hours = Double(diff) / 3600
        let text = hours == hours.rounded() ? String(Int(abs(hours))) : String(format: "%.1f", abs(hours))
        return "\(text)h \(diff > 0 ? "ahead of" : "behind") you"
    }

    private func currencyDetail(dest: String) -> String {
        let home = Locale.current.currency?.identifier ?? "USD"
        if dest == home { return "Same as home" }
        guard let rate = exchangeRate, rate > 0 else { return "Rate unavailable" }
        // Show a round amount of the local currency, e.g. ¥1,000 ≈ $6.48.
        let localAmount = pow(10, max(0, floor(log10(rate)) + 1))
        let local = localAmount.formatted(.currency(code: dest).precision(.fractionLength(0)))
        let homeValue = (localAmount / rate).formatted(.currency(code: home))
        return "\(local) ≈ \(homeValue)"
    }
}
