import Foundation

/// Names for common airline codes, so "UA 837" shows as United, and "United" in a
/// confirmation email maps back to UA.
enum Airlines {
    static let names: [String: String] = [
        "AA": "American Airlines", "AS": "Alaska Airlines", "B6": "JetBlue", "DL": "Delta Air Lines",
        "F9": "Frontier Airlines", "G4": "Allegiant Air", "HA": "Hawaiian Airlines", "NK": "Spirit Airlines",
        "UA": "United Airlines", "WN": "Southwest Airlines", "SY": "Sun Country Airlines", "AC": "Air Canada",
        "WS": "WestJet", "AM": "Aeroméxico", "BA": "British Airways", "VS": "Virgin Atlantic", "AF": "Air France",
        "KL": "KLM", "LH": "Lufthansa", "LX": "SWISS", "IB": "Iberia", "EI": "Aer Lingus", "AY": "Finnair",
        "SK": "SAS", "TP": "TAP Air Portugal", "TK": "Turkish Airlines", "EK": "Emirates", "QR": "Qatar Airways",
        "EY": "Etihad Airways", "NH": "ANA", "JL": "Japan Airlines", "CX": "Cathay Pacific", "SQ": "Singapore Airlines",
        "KE": "Korean Air", "OZ": "Asiana Airlines", "QF": "Qantas", "NZ": "Air New Zealand", "AI": "Air India",
        "LA": "LATAM", "AV": "Avianca", "CM": "Copa Airlines", "FR": "Ryanair", "U2": "easyJet",
    ]

    /// "UA 837" / "ua837" → ("UA", "UA 837", "United Airlines")
    static func parse(_ text: String) -> (code: String, flightNumber: String, name: String)? {
        let compact = text.uppercased().filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return nil }
        let code = String(compact.prefix(2))
        let number = String(compact.dropFirst(2))
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return (code, "\(code) \(number)", names[code] ?? code)
    }

    /// Words that identify an airline in free text ("southwest", "delta", "air canada") → code.
    static let keywords: [(word: String, code: String)] = names.map { code, name in
        var word = name.lowercased()
        for suffix in [" airlines", " air lines", " airways", " air"] where word.hasSuffix(suffix) && word != "air canada" {
            word = String(word.dropLast(suffix.count))
        }
        return (word, code)
    }
    .sorted { $0.word.count > $1.word.count }
}
