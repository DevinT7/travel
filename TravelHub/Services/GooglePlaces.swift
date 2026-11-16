import Foundation
import CryptoKit
import CoreLocation
import SwiftUI

/// Ratings, price level and opening hours for a place, from Google.
struct GooglePlaceInfo {
    var placeID: String
    var rating: Double?
    var ratingCount: Int?
    /// 0 (free) to 4 ($$$$).
    var priceLevel: Int?
    var hours: PlaceHours?
    var mapsURL: URL?
    var website: URL?
    var phone: String?
    /// Google's photo resource name ("places/…/photos/…"); turned into a URL only when shown,
    /// since every photo load is a billed call.
    var photoName: String?
    var photoCredit: String?

    var priceText: String? {
        guard let p = priceLevel else { return nil }
        return p == 0 ? "Free" : String(repeating: "$", count: p)
    }

    func photoURL(maxWidth: Int = 1200) -> URL? {
        guard let photoName, let key = APIKeys.googlePlaces else { return nil }
        return URL(string: "https://places.googleapis.com/v1/\(photoName)/media")?
            .appending(query: ["maxWidthPx": String(maxWidth), "key": key])
    }
}

/// A place's weekly opening hours, in the place's own time zone.
struct PlaceHours: Codable {
    struct Period: Codable { let open: Int; let close: Int? }  // minutes since Sunday 00:00
    let periods: [Period]
    /// "Monday: 9:00 AM – 5:00 PM", Monday first, as Google writes them.
    let weekdayText: [String]
    let timeZone: TimeZone

    enum Status {
        case open(until: Date?)
        case closingSoon(Date)
        case closed(opensAt: Date?)

        /// One word for cards.
        var short: String {
            switch self {
            case .open: "Open"
            case .closingSoon: "Closes soon"
            case .closed: "Closed"
            }
        }

        var color: Color {
            switch self {
            case .open: .green
            case .closingSoon: .orange
            case .closed: .red
            }
        }
    }

    private static let week = 7 * 1440

    func status(at now: Date = .now) -> Status? {
        guard !periods.isEmpty else { return nil }
        // Open around the clock: Google sends one period that opens Sunday 00:00 and never closes.
        if periods.count == 1, periods[0].close == nil { return .open(until: nil) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let current = ((c.weekday ?? 1) - 1) * 1440 + (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let date = { (minutes: Int) in now.addingTimeInterval(TimeInterval((minutes - current) * 60)) }

        for p in periods {
            guard var close = p.close else { continue }
            if close <= p.open { close += Self.week }
            for shift in [0, -Self.week] where (p.open + shift)...(close + shift - 1) ~= current {
                let closesAt = date(close + shift)
                return closesAt.timeIntervalSince(now) <= 3600 ? .closingSoon(closesAt) : .open(until: closesAt)
            }
        }
        let next = periods.map { $0.open > current ? $0.open : $0.open + Self.week }.min()
        return .closed(opensAt: next.map(date))
    }

    /// "Closes 10 PM", "Opens 9 AM", "Opens Tue 9 AM".
    func detail(for status: Status, now: Date = .now) -> String? {
        switch status {
        case .open(let until): until.map { "Closes \(time($0))" } ?? "Open 24 hours"
        case .closingSoon(let at): "Closes \(time(at))"
        case .closed(let opens): opens.map { "Opens \(day($0, now: now))\(time($0))" }
        }
    }

    /// Why a visit from `start` to `end` won't find the place open, or nil if it will (or the hours
    /// aren't known). Short enough for a plan row.
    func conflict(start: Date, end: Date) -> String? {
        guard let status = status(at: start) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        switch status {
        case .open(let until), .closingSoon(let until as Date?):
            // A few minutes' overlap at closing time isn't worth a warning. No closing time: open all day.
            guard let until else { return nil }
            return until < end.addingTimeInterval(-15 * 60) ? "Closes at \(time(until))" : nil
        case .closed(let opens):
            if let opens, cal.isDate(opens, inSameDayAs: start) {
                return opens < end ? "Not open until \(time(opens))" : "Closed then · opens \(time(opens))"
            }
            // Open earlier that day, just not this late; or not open that day at all.
            let day = cal.component(.weekday, from: start) - 1
            if periods.contains(where: { ($0.open / 1440) % 7 == day }) { return "Closed at this time" }
            let weekday = start.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.wide))
            return "Closed on \(weekday)s"
        }
    }

    /// Monday-first index of today, to highlight it in the week.
    func todayIndex(_ now: Date = .now) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return (cal.component(.weekday, from: now) + 5) % 7
    }

    private func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    private func day(_ d: Date, now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        if cal.isDate(d, inSameDayAs: now) { return "" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tomorrow) { return "tomorrow " }
        return d.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated)) + " "
    }
}

/// Google Places (New): restaurants, cafés, bars, museums, parks and shops with ratings, prices
/// and hours. Needs the person's own key. Each search is one billed call (Google includes a free
/// monthly allowance), so results are kept on disk for two days.
/// Docs: https://developers.google.com/maps/documentation/places/web-service/text-search
struct GooglePlacesProvider {
    static var isEnabled: Bool { APIKeys.googlePlaces != nil }
    /// Why the last call failed ("API key not valid…"), shown in Settings. Empty when working.
    static let problemKey = "googlePlaces.problem"

    private static let fields = [
        "id", "displayName", "formattedAddress", "location", "rating", "userRatingCount", "priceLevel",
        "regularOpeningHours", "utcOffsetMinutes", "photos", "primaryTypeDisplayName", "googleMapsUri",
        "websiteUri", "nationalPhoneNumber", "businessStatus",
    ]

    func search(category: DiscoverCategory, near center: CLLocationCoordinate2D, radius: CLLocationDistance = 6000) async throws -> [DiscoverItem] {
        let latDelta = radius / 111_000
        let lonDelta = radius / (111_000 * max(0.2, cos(center.latitude * .pi / 180)))
        let body: [String: Any] = [
            "textQuery": Self.query(for: category),
            "pageSize": 20,
            "languageCode": "en",
            "locationRestriction": ["rectangle": [
                "low": ["latitude": center.latitude - latDelta, "longitude": center.longitude - lonDelta],
                "high": ["latitude": center.latitude + latDelta, "longitude": center.longitude + lonDelta],
            ]],
        ]
        let places = try await searchText(body)
        return places.compactMap { Self.item(from: $0, category: category) }
    }

    /// Finds the Google listing for a place that came from somewhere else (Apple Maps, Wikipedia),
    /// to add its rating and hours on the place's page. Nil if nothing close by has that name.
    func match(_ item: DiscoverItem) async -> GooglePlaceInfo? {
        guard let c = item.coordinate else { return nil }
        return await match(title: item.title, near: c)
    }

    func match(title: String, near c: CLLocationCoordinate2D) async -> GooglePlaceInfo? {
        guard Self.isEnabled else { return nil }
        let body: [String: Any] = [
            "textQuery": title,
            "pageSize": 1,
            "languageCode": "en",
            "locationBias": ["circle": ["center": ["latitude": c.latitude, "longitude": c.longitude], "radius": 300.0]],
        ]
        guard let place = try? await searchText(body).first, let loc = place.location,
              CLLocation(latitude: loc.latitude, longitude: loc.longitude)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 400
        else { return nil }
        return Self.info(from: place)
    }

    private static func query(for category: DiscoverCategory) -> String {
        switch category {
        case .food: "restaurants"
        case .cafes: "coffee shops and cafés"
        case .nightlife: "bars"
        case .culture: "museums and galleries"
        case .outdoors: "parks"
        case .shopping: "shopping"
        case .sights: "tourist attractions"
        case .events, .other: category.title
        }
    }

    // MARK: Converting

    private static func item(from p: Place, category: DiscoverCategory) -> DiscoverItem? {
        guard let name = p.displayName?.text, let loc = p.location,
              p.businessStatus == nil || p.businessStatus == "OPERATIONAL" else { return nil }
        let info = info(from: p)
        let kind = p.primaryTypeDisplayName?.text
        return DiscoverItem(
            id: "gp-\(p.id)",
            title: name,
            subtitle: kind ?? category.title,
            category: category,
            kind: kind,
            source: .google,
            coordinate: .init(latitude: loc.latitude, longitude: loc.longitude),
            address: p.formattedAddress ?? "",
            externalURL: info.website,
            phone: info.phone,
            google: info
        )
    }

    private static func info(from p: Place) -> GooglePlaceInfo {
        let tz = TimeZone(secondsFromGMT: (p.utcOffsetMinutes ?? 0) * 60) ?? .current
        let hours = p.regularOpeningHours.map { h in
            PlaceHours(
                periods: (h.periods ?? []).compactMap { period in
                    guard let o = period.open else { return nil }
                    return .init(open: o.minutes, close: period.close?.minutes)
                },
                weekdayText: h.weekdayDescriptions ?? [],
                timeZone: tz)
        }
        let photo = p.photos?.first
        return GooglePlaceInfo(
            placeID: p.id,
            rating: p.rating,
            ratingCount: p.userRatingCount,
            priceLevel: p.priceLevel.flatMap(Self.priceLevels.firstIndex(of:)),
            hours: hours,
            mapsURL: p.googleMapsUri.flatMap(URL.init(string:)),
            website: p.websiteUri.flatMap(URL.init(string:)),
            phone: p.nationalPhoneNumber,
            photoName: photo?.name,
            photoCredit: photo?.authorAttributions?.first?.displayName)
    }

    private static let priceLevels = [
        "PRICE_LEVEL_FREE", "PRICE_LEVEL_INEXPENSIVE", "PRICE_LEVEL_MODERATE",
        "PRICE_LEVEL_EXPENSIVE", "PRICE_LEVEL_VERY_EXPENSIVE",
    ]

    // MARK: Network, with a two-day disk cache

    private func searchText(_ body: [String: Any]) async throws -> [Place] {
        guard let key = APIKeys.googlePlaces else { throw APIError.missingKey("Google Places") }
        let mask = Self.fields.map { "places.\($0)" }.joined(separator: ",")
        let json = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let cacheFile = Self.cacheFile(for: Data(mask.utf8) + json)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
           let modified = attrs[.modificationDate] as? Date, Date.now.timeIntervalSince(modified) < 2 * 86400,
           let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode(Response.self, from: data) {
            return cached.places ?? []
        }

        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.httpBody = json
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(mask, forHTTPHeaderField: "X-Goog-FieldMask")
        if let bundle = Bundle.main.bundleIdentifier { request.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }

        let (data, response) = try await HTTP.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(GoogleError.self, from: data))?.error.message
            Self.report(message ?? "Google returned an error (\(status)).")
            throw APIError.badStatus(status == 400 ? 403 : status, "Google Places")
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw APIError.decoding("Google Places")
        }
        Self.report(nil)
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheFile)
        return decoded.places ?? []
    }

    private static func report(_ problem: String?) {
        UserDefaults.standard.set(problem ?? "", forKey: problemKey)
    }

    private static func cacheFile(for data: Data) -> URL {
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return URL.cachesDirectory.appending(path: "GooglePlaces/\(name).json")
    }

    // MARK: Response

    private struct Response: Decodable { let places: [Place]? }

    private struct Place: Decodable {
        struct Text: Decodable { let text: String? }
        struct LatLng: Decodable { let latitude: Double; let longitude: Double }
        struct Hours: Decodable {
            struct Point: Decodable {
                let day: Int?; let hour: Int?; let minute: Int?
                var minutes: Int { (day ?? 0) * 1440 + (hour ?? 0) * 60 + (minute ?? 0) }
            }
            struct Period: Decodable { let open: Point?; let close: Point? }
            let periods: [Period]?
            let weekdayDescriptions: [String]?
        }
        struct Photo: Decodable {
            struct Author: Decodable { let displayName: String? }
            let name: String
            let authorAttributions: [Author]?
        }
        let id: String
        let displayName: Text?
        let formattedAddress: String?
        let location: LatLng?
        let rating: Double?
        let userRatingCount: Int?
        let priceLevel: String?
        let regularOpeningHours: Hours?
        let utcOffsetMinutes: Int?
        let photos: [Photo]?
        let primaryTypeDisplayName: Text?
        let googleMapsUri: String?
        let websiteUri: String?
        let nationalPhoneNumber: String?
        let businessStatus: String?
    }

    private struct GoogleError: Decodable {
        struct Body: Decodable { let message: String? }
        let error: Body
    }
}

// MARK: - Showing it

/// "★ 4.6 · $$ · Open · 0.4 mi": a place's rating, price and whether it's open, followed by any
/// other details, as one line of text. Parts that aren't known are left out.
enum PlaceMeta {
    static func line(_ info: GooglePlaceInfo?, _ extras: [String?] = [], showCount: Bool = false) -> Text? {
        var parts: [Text] = []
        if let info {
            if let r = info.rating {
                let star = Text(Image(systemName: "star.fill")).foregroundStyle(.orange)
                let count = showCount ? info.ratingCount.map { " (\($0.formatted(.number.notation(.compactName))))" } ?? "" : ""
                parts.append(Text("\(star) \(r.formatted(.number.precision(.fractionLength(1))))\(count)"))
            }
            if let price = info.priceText { parts.append(Text(price)) }
            if let status = info.hours?.status() { parts.append(Text(status.short).foregroundStyle(status.color)) }
        }
        parts += extras.compactMap { $0 }.filter { !$0.isEmpty }.map { Text($0) }
        guard var line = parts.first else { return nil }
        for part in parts.dropFirst() { line = Text("\(line) · \(part)") }
        return line
    }
}

/// Today's status with the whole week underneath, folded away until tapped.
struct PlaceHoursCard: View {
    let hours: PlaceHours
    @State private var expanded = false

    var body: some View {
        if let status = hours.status() {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        CircleIcon(symbol: "clock.fill", color: status.color, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(status.short).font(.subheadline.weight(.semibold)).foregroundStyle(status.color)
                            if let detail = hours.detail(for: status) {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !hours.weekdayText.isEmpty {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(hours.weekdayText.isEmpty)
                .accessibilityHint(expanded ? "Hides opening hours" : "Shows opening hours for the week")

                if expanded {
                    Divider().padding(.leading, 58)
                    VStack(spacing: 6) {
                        let today = hours.todayIndex()
                        ForEach(Array(hours.weekdayText.enumerated()), id: \.offset) { i, line in
                            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                            HStack(alignment: .firstTextBaseline) {
                                Text(parts.first ?? "")
                                Spacer()
                                Text(parts.count > 1 ? parts[1] : "").multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline.weight(i == today ? .semibold : .regular))
                            .foregroundStyle(i == today ? .primary : .secondary)
                        }
                    }
                    .padding(.leading, 58)
                    .padding(.trailing, Metrics.gutter)
                    .padding(.vertical, 12)
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 4)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}
