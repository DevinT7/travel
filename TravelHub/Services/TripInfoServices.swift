import Foundation
import MapKit

// MARK: - Weather (Open-Meteo, free, no key)

struct DailyForecast: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    let precipitationChance: Int?

    var symbol: String { WeatherCode.symbol(code) }
    var label: String { WeatherCode.label(code) }
}

@MainActor
struct WeatherService {
    /// Daily forecast for the trip days that fall inside Open-Meteo's 16-day window.
    func forecast(for trip: Trip) async throws -> [DailyForecast] {
        let cal = trip.calendar
        let today = cal.startOfDay(for: .now)
        guard let windowEnd = cal.date(byAdding: .day, value: 15, to: today) else { return [] }
        let start = max(cal.startOfDay(for: trip.startDate), today)
        let end = min(cal.startOfDay(for: trip.endDate), windowEnd)
        guard start <= end else { return [] }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = trip.timeZone
        df.dateFormat = "yyyy-MM-dd"
        let useFahrenheit = Locale.current.measurementSystem == .us

        let url = URL(string: "https://api.open-meteo.com/v1/forecast")!.appending(query: [
            "latitude": String(trip.destinationLatitude), "longitude": String(trip.destinationLongitude),
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "timezone": trip.timeZone.identifier,
            "start_date": df.string(from: start), "end_date": df.string(from: end),
            "temperature_unit": useFahrenheit ? "fahrenheit" : "celsius",
        ])
        let r: Response = try await HTTP.get(url, service: "Open-Meteo")
        return r.daily.time.indices.compactMap { i in
            guard let date = df.date(from: r.daily.time[i]),
                  let hi = r.daily.temperature_2m_max[i], let lo = r.daily.temperature_2m_min[i] else { return nil }
            return DailyForecast(date: date, code: r.daily.weather_code[i] ?? 0, high: hi, low: lo,
                                 precipitationChance: r.daily.precipitation_probability_max?[i])
        }
    }

    private struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]?
        }
        let daily: Daily
    }
}

/// WMO weather interpretation codes used by Open-Meteo.
enum WeatherCode {
    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func label(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Storms"
        default: "Cloudy"
        }
    }
}

// MARK: - Currency (open.er-api.com, free, no key)

struct CurrencyService {
    /// How many units of `to` one unit of `from` buys.
    func rate(from: String, to: String) async throws -> Double? {
        guard from != to else { return 1 }
        let url = URL(string: "https://open.er-api.com/v6/latest/\(from)")!
        let r: Response = try await HTTP.get(url, service: "Exchange rates")
        return r.rates[to]
    }

    /// The currency used in a country, e.g. "JP" → "JPY".
    static func currency(forCountry code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale(components: .init(languageCode: "en", languageRegion: .init(code))).currency?.identifier
    }

    private struct Response: Decodable { let rates: [String: Double] }
}

// MARK: - Travel time between plan stops (MapKit, free)

struct TravelEstimate: Hashable {
    enum Mode { case walk, transit, drive }
    let mode: Mode
    let minutes: Int

    var symbol: String {
        switch mode { case .walk: "figure.walk"; case .transit: "tram.fill"; case .drive: "car.fill" }
    }
    var text: String {
        let verb = switch mode { case .walk: "walk"; case .transit: "transit"; case .drive: "drive" }
        return minutes < 60 ? "\(minutes) min \(verb)" : "\(minutes / 60) h \(minutes % 60) min \(verb)"
    }
}

@MainActor
final class DirectionsService {
    static let shared = DirectionsService()
    private var cache: [String: TravelEstimate] = [:]

    /// With `.auto`: walking under ~1.5 km, otherwise transit (falling back to driving where transit
    /// isn't covered). Other modes use that mode, except transit, which falls back to driving.
    func estimate(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
                  mode preference: GettingAround = .auto) async -> TravelEstimate? {
        let key = String(format: "%.4f,%.4f>%.4f,%.4f|", a.latitude, a.longitude, b.latitude, b.longitude) + preference.rawValue
        if let hit = cache[key] { return hit }
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        if meters < 80 { return nil }

        let modes: [(MKDirectionsTransportType, TravelEstimate.Mode)] = switch preference {
        case .auto: meters < 1500 ? [(.walking, .walk)] : [(.transit, .transit), (.automobile, .drive)]
        case .drive: [(.automobile, .drive)]
        case .transit: [(.transit, .transit), (.automobile, .drive)]
        case .walk: [(.walking, .walk)]
        }
        for (type, mode) in modes {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            request.transportType = type
            if let eta = try? await MKDirections(request: request).calculateETA() {
                let result = TravelEstimate(mode: mode, minutes: max(1, Int((eta.expectedTravelTime / 60).rounded())))
                cache[key] = result
                return result
            }
        }
        return nil
    }
}
