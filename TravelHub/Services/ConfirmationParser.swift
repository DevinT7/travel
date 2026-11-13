import Foundation

/// A flight read out of pasted confirmation text, before its airports are looked up.
struct ParsedFlight: Equatable {
    var airlineCode: String?
    var number: String = ""
    var fromCode: String?
    var toCode: String?
    /// Calendar day of departure (year, month, day) in the departure airport's local time.
    var date: DateComponents?
    /// Local wall-clock times (hour, minute).
    var departs: DateComponents?
    var arrives: DateComponents?
    /// Explicit "+1" / "next day" on the arrival line; otherwise worked out from time zones later.
    var arrivalDayOffset: Int?

    var isComplete: Bool { fromCode != nil && toCode != nil && departs != nil && arrives != nil && date != nil }

    var flightNumber: String {
        if let airlineCode { return "\(airlineCode) \(number)" }
        return number.isEmpty ? "Flight" : "Flight \(number)"
    }
}

/// Reads flights out of airline confirmation emails and texts, e.g.
///
///     Departing Flight: Thu, Mar 5, 2026
///     Flight #: 837
///     Departs: 10:40 AM SFO
///     Arrives: 02:15 PM DEN
///
/// Works line by line and offline: flight numbers, dates, times paired with airport codes, and
/// "depart"/"arrive" words. Anything it can't place is ignored rather than guessed.
enum ConfirmationParser {
    /// - Parameter reference: used to fill in a missing year (dates without one are assumed to be
    ///   the next occurrence on or after roughly six months before the reference).
    static func parse(_ text: String, reference: Date = .now) -> [ParsedFlight] {
        let airline = airlineCode(in: text)
        var flights: [ParsedFlight] = []
        var draft = ParsedFlight()
        var currentDate: DateComponents?

        func finish() {
            if draft.isComplete {
                if draft.airlineCode == nil { draft.airlineCode = airline }
                flights.append(draft)
            }
            draft = ParsedFlight()
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()

            if let date = date(in: line, reference: reference) {
                if draft.isComplete { finish() }
                currentDate = date
                if draft.date == nil || draft.departs == nil { draft.date = date }
            }

            if let (code, number) = flightNumber(in: line) {
                if draft.isComplete || (!draft.number.isEmpty && draft.number != number && draft.departs != nil) { finish() }
                draft.number = number
                if let code { draft.airlineCode = code }
                if draft.date == nil { draft.date = currentDate }
            }

            let isDeparture = ["depart", "leave", "leaving", "take off", "takeoff"].contains { lower.contains($0) }
                || lower.hasPrefix("from")
            let isArrival = ["arriv", "land"].contains { lower.contains($0) } || lower.hasPrefix("to ") || lower.hasPrefix("to:")
            let role: Role? = isDeparture && !isArrival ? .departure : (isArrival && !isDeparture ? .arrival : nil)

            let pairs = timeCodePairs(in: line)
            if !pairs.isEmpty {
                if pairs.count >= 2 {
                    assign(time: pairs[0].time, code: pairs[0].code, role: .departure, to: &draft)
                    assign(time: pairs[1].time, code: pairs[1].code, role: .arrival, to: &draft)
                } else {
                    assign(time: pairs[0].time, code: pairs[0].code, role: role, to: &draft)
                }
            } else {
                if let route = route(in: line) {
                    if draft.fromCode == nil { draft.fromCode = route.0 }
                    if draft.toCode == nil { draft.toCode = route.1 }
                } else {
                    for code in parenthesizedCodes(in: line) { assign(time: nil, code: code, role: role, to: &draft) }
                }
                for time in times(in: line) { assign(time: time, code: nil, role: role, to: &draft) }
            }
            if role == .arrival || draft.arrives != nil, lower.contains("+1") || lower.contains("next day") {
                draft.arrivalDayOffset = 1
            }
            if draft.date == nil, draft.departs != nil { draft.date = currentDate }
        }
        finish()
        return flights
    }

    // MARK: Assignment

    private enum Role { case departure, arrival }

    private static func assign(time: DateComponents?, code: String?, role: Role?, to draft: inout ParsedFlight) {
        let target: Role
        if let role {
            target = role
        } else if code != nil {
            target = draft.fromCode == nil ? .departure : .arrival
        } else {
            target = draft.departs == nil ? .departure : .arrival
        }
        switch target {
        case .departure:
            if let time, draft.departs == nil { draft.departs = time }
            if let code, draft.fromCode == nil { draft.fromCode = code }
        case .arrival:
            if let time, draft.arrives == nil { draft.arrives = time }
            if let code, draft.toCode == nil { draft.toCode = code }
        }
    }

    // MARK: Airline

    static func airlineCode(in text: String) -> String? {
        let lower = text.lowercased()
        var best: (index: String.Index, code: String)?
        for (word, code) in Airlines.keywords {
            guard let range = lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression)
            else { continue }
            if best == nil || range.lowerBound < best!.index { best = (range.lowerBound, code) }
        }
        return best?.code
    }

    // MARK: Flight numbers

    private static let flightWord = try! NSRegularExpression(
        pattern: #"\b(?:flight|flt)\s*(?:#|no\.?|number)?\s*:?\s*(?:([A-Za-z]{2}|[A-Za-z]\d|\d[A-Za-z])\s?)?(\d{1,4})\b"#,
        options: [.caseInsensitive])
    private static let codedNumber = try! NSRegularExpression(pattern: #"\b([A-Z]{2}|[A-Z]\d|\d[A-Z])\s?(\d{1,4})\b"#)

    static func flightNumber(in line: String) -> (String?, String)? {
        if let m = flightWord.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            let code = group(m, 1, line)?.uppercased()
            return (code, group(m, 2, line)!)
        }
        for m in codedNumber.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let code = group(m, 1, line), Airlines.names[code] != nil { return (code, group(m, 2, line)!) }
        }
        return nil
    }

    // MARK: Dates

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let monthDay = try! NSRegularExpression(
        pattern: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?"#,
        options: [.caseInsensitive])
    private static let dayMonth = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:,?\s+(\d{4}))?"#,
        options: [.caseInsensitive])
    private static let iso = try! NSRegularExpression(pattern: #"\b(\d{4})-(\d{2})-(\d{2})\b"#)
    private static let slashed = try! NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#)

    static func date(in line: String, reference: Date) -> DateComponents? {
        let range = NSRange(line.startIndex..., in: line)
        var y: Int?, m: Int?, d: Int?
        if let r = iso.firstMatch(in: line, range: range) {
            y = Int(group(r, 1, line)!); m = Int(group(r, 2, line)!); d = Int(group(r, 3, line)!)
        } else if let r = monthDay.firstMatch(in: line, range: range) {
            m = months.firstIndex(of: group(r, 1, line)!.lowercased()).map { $0 + 1 }
            d = Int(group(r, 2, line)!); y = group(r, 3, line).flatMap(Int.init)
        } else if let r = dayMonth.firstMatch(in: line, range: range) {
            d = Int(group(r, 1, line)!)
            m = months.firstIndex(of: group(r, 2, line)!.lowercased()).map { $0 + 1 }
            y = group(r, 3, line).flatMap(Int.init)
        } else if let r = slashed.firstMatch(in: line, range: range) {
            m = Int(group(r, 1, line)!); d = Int(group(r, 2, line)!)
            y = group(r, 3, line).flatMap(Int.init).map { $0 < 100 ? 2000 + $0 : $0 }
        }
        guard let month = m, let day = d, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = y ?? inferYear(month: month, reference: reference)
        return DateComponents(year: year, month: month, day: day)
    }

    private static func inferYear(month: Int, reference: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let refYear = cal.component(.year, from: reference)
        let refMonth = cal.component(.month, from: reference)
        return month < refMonth - 6 ? refYear + 1 : refYear
    }

    // MARK: Times and airport codes

    private static let timePattern = #"(\d{1,2}):(\d{2})(?:\s*([AaPp])\.?\s?[Mm]\.?)?"#
    private static let timeRegex = try! NSRegularExpression(pattern: #"\b"# + timePattern)
    private static let timeThenCode = try! NSRegularExpression(pattern: #"\b"# + timePattern + #"\s*[-–,]?\s*\(?\b([A-Z]{3})\b\)?"#)
    private static let codeThenTime = try! NSRegularExpression(pattern: #"\b([A-Z]{3})\b\)?\s*[-–:,]?\s*"# + timePattern)
    private static let routeRegex = try! NSRegularExpression(pattern: #"\b([A-Z]{3})\b\)?\s*(?:→|->|–|-|to|✈︎?)\s*\(?\b([A-Z]{3})\b"#)
    private static let parenCode = try! NSRegularExpression(pattern: #"\(([A-Z]{3})\)"#)

    /// Upper-case three-letter words that are never airport codes in a confirmation.
    private static let notAirports: Set<String> = [
        "THE", "AND", "FOR", "YOU", "ARE", "NON", "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN",
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        "PST", "PDT", "MST", "MDT", "CST", "CDT", "EST", "EDT", "GMT", "UTC", "BST", "CET", "JST",
        "USD", "EUR", "GBP", "CAD", "JPY", "MXN", "PNR", "REF", "SEAT", "ROW", "BAG", "TSA",
    ]

    private static func time(_ m: NSTextCheckingResult, offset: Int, _ s: String) -> DateComponents? {
        guard var h = group(m, offset, s).flatMap(Int.init), let min = group(m, offset + 1, s).flatMap(Int.init),
              (0...23).contains(h), (0...59).contains(min) else { return nil }
        if let ap = group(m, offset + 2, s)?.lowercased() {
            guard (1...12).contains(h) else { return nil }
            if ap == "p", h < 12 { h += 12 }
            if ap == "a", h == 12 { h = 0 }
        }
        return DateComponents(hour: h, minute: min)
    }

    static func timeCodePairs(in line: String) -> [(time: DateComponents, code: String)] {
        let range = NSRange(line.startIndex..., in: line)
        var result: [(Int, DateComponents, String)] = []
        for m in timeThenCode.matches(in: line, range: range) {
            if let t = time(m, offset: 1, line), let c = group(m, 4, line), !notAirports.contains(c) {
                result.append((m.range.location, t, c))
            }
        }
        if result.isEmpty {
            for m in codeThenTime.matches(in: line, range: range) {
                if let c = group(m, 1, line), !notAirports.contains(c), let t = time(m, offset: 2, line) {
                    result.append((m.range.location, t, c))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
    }

    static func times(in line: String) -> [DateComponents] {
        timeRegex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { time($0, offset: 1, line) }
    }

    static func route(in line: String) -> (String, String)? {
        guard let m = routeRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let a = group(m, 1, line), let b = group(m, 2, line),
              !notAirports.contains(a), !notAirports.contains(b), a != b else { return nil }
        return (a, b)
    }

    static func parenthesizedCodes(in line: String) -> [String] {
        parenCode.matches(in: line, range: NSRange(line.startIndex..., in: line))
            .compactMap { group($0, 1, line) }.filter { !notAirports.contains($0) }
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }
}
