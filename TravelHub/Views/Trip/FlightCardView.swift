import SwiftUI

/// Compact flight card: airport codes with local times either side of a route line, then gate details.
struct FlightCardView: View {
    let flight: FlightSegment
    /// Optional row at the bottom of the card (e.g. the Live Activity control on the trip page).
    var footer: AnyView? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in card }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CircleIcon(symbol: "airplane", color: .flight, size: 26)
                Text(flight.flightNumber).font(.subheadline.weight(.semibold))
                Text(flight.airlineName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                StatusPill(text: status.text, color: status.color)
            }

            HStack(alignment: .center, spacing: 10) {
                endpoint(flight.departure, alignment: .leading)
                VStack(spacing: 4) {
                    RouteLine(progress: FlightProgress.fraction(of: flight)).frame(height: 14)
                    Text(flight.duration.hoursMinutes).font(.caption).foregroundStyle(.secondary)
                }
                endpoint(flight.arrival, alignment: .trailing, dayOffset: dayOffset)
            }

            Divider()

            if let liveLine {
                Label(liveLine, systemImage: FlightProgress.livePosition(of: flight) != nil ? "dot.radiowaves.left.and.right" : "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                detail("Terminal", flight.departure.terminal)
                detail("Gate", flight.departure.gate)
                detail("Arr. Terminal", flight.arrival.terminal)
                detail("Bags", flight.arrival.baggageBelt)
            }

            if let footer {
                Divider()
                footer
            }
        }
        .card()
    }

    private func endpoint(_ e: FlightEndpoint, alignment: HorizontalAlignment, dayOffset: Int = 0) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(e.city).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(e.iata).font(.system(size: 30, weight: .bold, design: .rounded))
            HStack(spacing: 3) {
                Text(e.best.time(in: e.timeZone))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(e.delayMinutes >= 15 ? Color.orange : Color.primary)
                if dayOffset != 0 {
                    Text(dayOffset > 0 ? "+\(dayOffset)" : "\(dayOffset)").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                }
            }
            Text(e.best.weekdayDayMonth(in: e.timeZone)).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private func detail(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "–").font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Calendar-day difference between departure and arrival in their own local zones.
    private var dayOffset: Int {
        var depCal = Calendar(identifier: .gregorian); depCal.timeZone = flight.departure.timeZone
        let d = depCal.dateComponents([.year, .month, .day], from: flight.departure.best)
        var arrCal = Calendar(identifier: .gregorian); arrCal.timeZone = flight.arrival.timeZone
        let a = arrCal.dateComponents([.year, .month, .day], from: flight.arrival.best)
        guard let dd = Calendar(identifier: .gregorian).date(from: d), let ad = Calendar(identifier: .gregorian).date(from: a) else { return 0 }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: dd, to: ad).day ?? 0
    }

    private var status: (text: String, color: Color) {
        let s = flight.status.lowercased()
        if s.contains("cancel") { return ("Canceled", .red) }
        if s.contains("divert") { return ("Diverted", .red) }
        if s.contains("landed") || s.contains("arrived") { return ("Landed", .secondary) }
        if s.contains("approach") { return ("Landing Soon", .blue) }
        if s.contains("in air") || s.contains("enroute") || s.contains("departed") { return ("In Air", .blue) }
        let delay = flight.departure.delayMinutes
        if delay >= 15 { return ("Delayed \(TimeInterval(delay * 60).hoursMinutes)", .orange) }
        if s.contains("delay") { return ("Delayed", .orange) }
        if s.contains("board") { return ("Boarding", .green) }
        if s.contains("gate closed") { return ("Gate Closed", .orange) }
        if s.contains("check") { return ("Check-in", .green) }
        if Date.now > flight.departure.best, Date.now < flight.arrival.best, flight.livePositionAt == nil {
            return ("Scheduled", .secondary)
        }
        return ("On Time", .green)
    }

    /// "35,000 ft · 482 kt · Updated 3 min ago" while airborne; "Updated 12 min ago" otherwise.
    private var liveLine: String? {
        var parts: [String] = []
        if FlightProgress.livePosition(of: flight) != nil {
            if let ft = flight.liveAltitudeFeet { parts.append("\(Int(ft).formatted()) ft") }
            if let kt = flight.liveSpeedKnots { parts.append("\(Int(kt)) kt") }
        }
        guard APIKeys.aeroDataBox != nil, FlightProgress.isInLiveWindow(flight) else {
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        parts.append("Updated \(flight.lastUpdated.formatted(.relative(presentation: .named)))")
        return parts.joined(separator: " · ")
    }
}

/// Route line with a plane at the flight's current progress (or the middle before departure).
private struct RouteLine: View {
    let progress: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, mid = geo.size.height / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 2).offset(y: 0)
                if let progress {
                    Capsule().fill(Color.flight).frame(width: w * progress, height: 2)
                }
                Image(systemName: "airplane")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.flight)
                    .padding(.horizontal, 3)
                    .background(Color.cardBackground)
                    .offset(x: (w - 20) * (progress ?? 0.5))
            }
            .frame(height: geo.size.height)
            .position(x: w / 2, y: mid)
        }
    }
}
