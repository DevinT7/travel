import Foundation

enum APIError: LocalizedError {
    case missingKey(String)
    case badStatus(Int, String)
    case notFound
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let service): "Add your \(service) API key in Settings to use this."
        case .badStatus(let code, let service):
            switch code {
            case 401, 403: "\(service) rejected the API key. Check it in Settings."
            case 429: "\(service) rate limit reached. Try again later."
            default: "\(service) returned an error (\(code))."
            }
        case .notFound: "Nothing found. Check the details and try again."
        case .decoding(let service): "Couldn't read the response from \(service)."
        }
    }
}

/// API keys the user pastes into Settings. Both services have free tiers.
/// Stored in UserDefaults: this is a personal app and the keys are free-tier only.
enum APIKeys {
    static let aeroDataBoxKey = "apikey.aerodatabox"
    static let ticketmasterKey = "apikey.ticketmaster"
    static let googlePlacesKey = "apikey.googleplaces"

    static var aeroDataBox: String? { value(for: aeroDataBoxKey) }
    static var ticketmaster: String? { value(for: ticketmasterKey) }
    static var googlePlaces: String? { value(for: googlePlacesKey) }

    private static func value(for key: String) -> String? {
        let v = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty ?? true) ? nil : v
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000)
        return URLSession(configuration: config)
    }()

    static func get<T: Decodable>(_ url: URL, headers: [String: String] = [:], service: String,
                                  as type: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var request = URLRequest(url: url)
        // Wikimedia asks automated clients to identify themselves.
        request.setValue("TravelHub/1.0 (personal iOS/macOS travel planner)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 204 || http.statusCode == 404 { throw APIError.notFound }
            guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode, service) }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[\(service)] decode error:", error)
            #endif
            throw APIError.decoding(service)
        }
    }
}

extension URL {
    func appending(query: [String: String?]) -> URL {
        appending(queryItems: query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } })
    }
}
