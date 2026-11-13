import SwiftUI

struct WeatherStripView: View {
    let forecast: [DailyForecast]
    let loaded: Bool
    let tz: TimeZone

    var body: some View {
        if forecast.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: loaded ? "calendar.badge.clock" : "cloud.sun")
                    .font(.title2).symbolRenderingMode(.multicolor)
                Text(loaded ? "The forecast appears about two weeks before your trip."
                            : "Loading forecast…")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .card()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(forecast) { day in
                        VStack(spacing: 8) {
                            Text(day.date.weekday(in: tz)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(day.date.dayNumber(in: tz)).font(.caption2).foregroundStyle(.tertiary)
                            Image(systemName: day.symbol)
                                .symbolRenderingMode(.multicolor)
                                .font(.title2)
                                .frame(height: 30)
                            Text("\(Int(day.high.rounded()))°").font(.headline)
                            Text("\(Int(day.low.rounded()))°").font(.subheadline).foregroundStyle(.secondary)
                            if let p = day.precipitationChance, p >= 20 {
                                Label("\(p)%", systemImage: "drop.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(width: 66)
                        .padding(.vertical, 14)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(day.date.weekday(in: tz, .wide)): \(day.label), high \(Int(day.high)), low \(Int(day.low))")
                    }
                }
            }
        }
    }
}

struct LocalInfoView: View {
    let trip: Trip
    let exchangeRate: Double?

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                tile(symbol: "clock.fill", tint: .blue, title: "Local time",
                     value: context.date.time(in: trip.timeZone),
                     detail: timeDifference(at: context.date))
            }
            if let currency = CurrencyService.currency(forCountry: trip.countryCode) {
                tile(symbol: "banknote.fill", tint: .green, title: "Currency", value: currency,
                     detail: currencyDetail(dest: currency))
            }
            if let code = trip.countryCode, let country = Locale.current.localizedString(forRegionCode: code) {
                tile(symbol: "globe", tint: .orange, title: "Country", value: country,
                     detail: trip.timeZone.localizedName(for: .generic, locale: .current) ?? trip.timeZone.identifier)
            }
        }
    }

    private func tile(symbol: String, tint: Color, title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.headline)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }

    private func timeDifference(at date: Date) -> String {
        let diff = trip.timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if diff == 0 { return "Same time as you" }
        let hours = Double(diff) / 3600
        let text = hours == hours.rounded() ? String(Int(abs(hours))) : String(format: "%.1f", abs(hours))
        return "\(text) h \(diff > 0 ? "ahead of" : "behind") you"
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
