import SwiftUI

/// Boarding-pass style flight summary: big airport codes, local times, gates and status.
struct FlightCardView: View {
    let flight: FlightSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            route
            times
            Divider()
            details
        }
        .card(padding: 18)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(flight.airlineCode.isEmpty ? "✈︎" : flight.airlineCode)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(flight.flightNumber).font(.headline)
                Text(flight.airlineName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if flight.isSample { StatusPill(text: "Sample", color: .orange) }
            StatusPill(text: status.text, color: status.color)
        }
    }

    private var route: some View {
        HStack(alignment: .center, spacing: 10) {
            airport(flight.departure, alignment: .leading)
            VStack(spacing: 6) {
                RouteLine(progress: FlightProgress.fraction(of: flight))
                    .frame(height: 16)
                Text(flight.duration.hoursMinutes)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            airport(flight.arrival, alignment: .trailing)
        }
    }

    private func airport(_ e: FlightEndpoint, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(e.iata)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospaced()
            Text(e.city).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .fixedSize()
    }

    private var times: some View {
        HStack(alignment: .top) {
            timeBlock(flight.departure, label: "Departs", alignment: .leading)
            Spacer()
            timeBlock(flight.arrival, label: "Arrives", alignment: .trailing, dayOffset: dayOffset)
        }
    }

    private func timeBlock(_ e: FlightEndpoint, label: String, alignment: HorizontalAlignment, dayOffset: Int = 0) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(e.best.time(in: e.timeZone))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(e.delayMinutes >= 15 ? .orange : .primary)
                if dayOffset != 0 {
                    Text(dayOffset > 0 ? "+\(dayOffset)" : "\(dayOffset)")
                        .font(.caption.weight(.bold)).foregroundStyle(.orange)
                }
            }
            if e.delayMinutes >= 15 {
                Text(e.scheduled.time(in: e.timeZone)).font(.caption).strikethrough().foregroundStyle(.secondary)
            } else {
                Text(e.best.weekdayDayMonth(in: e.timeZone)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                detail("Terminal", flight.departure.terminal)
                detail("Gate", flight.departure.gate)
                detail("Arr. Term.", flight.arrival.terminal)
                detail("Bags", flight.arrival.baggageBelt)
            }
            if let aircraft = flight.aircraftModel {
                Label(aircraft + distanceText, systemImage: "airplane.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var distanceText: String {
        guard let km = flight.distanceKm else { return "" }
        let m = Measurement(value: km, unit: UnitLength.kilometers)
        return " · " + m.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func detail(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).lineLimit(1)
            Text(value?.isEmpty == false ? value! : "—").font(.headline.monospaced())
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
        if s.contains("air") || s.contains("departed") { return ("In Air", .blue) }
        let delay = flight.departure.delayMinutes
        if delay >= 15 { return ("Delayed \(TimeInterval(delay * 60).hoursMinutes)", .orange) }
        if s.contains("board") { return ("Boarding", .green) }
        return ("On Time", .green)
    }
}

/// Dotted route with a plane that sits at the flight's current progress.
private struct RouteLine: View {
    let progress: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: w, y: geo.size.height / 2))
                }
                .stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                if let progress {
                    Capsule().fill(Color.accentColor).frame(width: w * progress, height: 3)
                }
                Image(systemName: "airplane")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 4)
                    .background(Color.cardBackground)
                    .offset(x: (w - 24) * (progress ?? 0.5))
            }
        }
    }
}
