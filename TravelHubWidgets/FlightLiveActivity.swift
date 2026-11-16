import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TravelHubWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
        DriveLiveActivity()
    }
}

/// Lock Screen and Dynamic Island view of a tracked flight.
///
/// Updates come from the app when it refreshes flight status. In between, the countdowns and the
/// progress bar run on their own, and the activity's stale date (set to the next departure or
/// landing) flips the view to the next phase even if the app hasn't run.
struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            // A dark card with light text reads on any wallpaper, light or dark. The small family is
            // the CarPlay dashboard (iOS 26) and the Apple Watch Smart Stack.
            FlightActivityContent(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.13).opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            let phase = FlightPhaseView.phase(s, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AirportColumn(code: a.fromCode, city: a.fromCity, time: s.departs, tz: a.fromTimeZone, alignment: .leading,
                                  late: s.delayMinutes >= 15)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AirportColumn(code: a.toCode, city: a.toCity, time: s.arrives, tz: a.toTimeZone, alignment: .trailing,
                                  late: s.delayMinutes >= 15)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(a.flightNumber).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        StatusBadge(state: s, phase: phase)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        FlightProgressBar(departs: s.departs, arrives: s.arrives, phase: phase)
                        HStack(alignment: .center) {
                            FlightPhaseView(state: s, phase: phase, destination: a.toCity).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 8)
                            // Just the gate (or belt) here; the terminal name would squeeze the countdown.
                            GateLine(state: s, phase: phase, showsDetail: false)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: phase == .landed ? "airplane.arrival" : "airplane")
                        .foregroundStyle(.blue)
                    Text(phase == .scheduled ? a.fromCode : a.toCode).font(.caption.weight(.semibold))
                }
            } compactTrailing: {
                CompactCountdown(state: s, phase: phase)
            } minimal: {
                Image(systemName: phase == .landed ? "airplane.arrival" : "airplane").foregroundStyle(.blue)
            }
            .keylineTint(.blue)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

private struct FlightActivityContent: View {
    @Environment(\.activityFamily) private var family
    let attributes: FlightActivityAttributes
    let state: FlightActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if family == .small {
            let phase = FlightPhaseView.phase(state, isStale: isStale)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: phase == .landed ? "airplane.arrival" : "airplane").foregroundStyle(.blue)
                    Text("\(attributes.fromCode) → \(attributes.toCode)").font(.headline).lineLimit(1)
                }
                FlightPhaseView(state: state, phase: phase, destination: attributes.toCity)
                    .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LockScreenFlightView(attributes: attributes, state: state, isStale: isStale)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenFlightView: View {
    let attributes: FlightActivityAttributes
    let state: FlightActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let phase = FlightPhaseView.phase(state, isStale: isStale)
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "airplane")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(.blue, in: Circle())
                Text(attributes.flightNumber).font(.subheadline.weight(.semibold))
                Text(attributes.airlineName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                StatusBadge(state: state, phase: phase)
            }
            HStack(alignment: .center, spacing: 10) {
                AirportColumn(code: attributes.fromCode, city: attributes.fromCity, time: state.departs,
                              tz: attributes.fromTimeZone, alignment: .leading, late: state.delayMinutes >= 15)
                FlightProgressBar(departs: state.departs, arrives: state.arrives, phase: phase)
                AirportColumn(code: attributes.toCode, city: attributes.toCity, time: state.arrives,
                              tz: attributes.toTimeZone, alignment: .trailing, late: state.delayMinutes >= 15)
            }
            HStack(alignment: .center) {
                FlightPhaseView(state: state, phase: phase, destination: attributes.toCity).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                GateLine(state: state, phase: phase)
            }
        }
        .padding(16)
    }
}

// MARK: - Pieces

private struct AirportColumn: View {
    let code: String
    let city: String
    let time: Date
    let tz: String
    let alignment: HorizontalAlignment
    let late: Bool

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(code).font(.system(.title2, design: .rounded).weight(.bold))
            Text(time.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: TimeZone(identifier: tz) ?? .current)))
                .font(.caption.weight(.medium))
                .foregroundStyle(late ? Color.orange : Color.primary)
            Text(city).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .fixedSize()
    }
}

/// A route line that fills in as the flight goes, driven by the system clock (no updates needed).
private struct FlightProgressBar: View {
    let departs: Date
    let arrives: Date
    let phase: FlightActivityAttributes.ContentState.Phase

    var body: some View {
        Group {
            if phase == .landed {
                ProgressView(value: 1)
            } else if arrives > departs {
                ProgressView(timerInterval: departs...arrives, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: 0)
            }
        }
        .progressViewStyle(.linear)
        .tint(.blue)
        .padding(.horizontal, 16)
        // The bar fills from takeoff to landing on its own; the glyphs mark each end.
        .overlay(alignment: .leading) {
            Image(systemName: "airplane.departure").font(.caption2).foregroundStyle(.secondary)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "airplane.arrival").font(.caption2)
                .foregroundStyle(phase == .landed ? Color.green : Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatusBadge: View {
    let state: FlightActivityAttributes.ContentState
    let phase: FlightActivityAttributes.ContentState.Phase

    var body: some View {
        let (text, color): (String, Color) = switch phase {
        case .canceled: ("Canceled", .red)
        case .landed: ("Landed", .green)
        case .inAir: ("In Air", .blue)
        case .scheduled: state.delayMinutes >= 15 ? ("Delayed \(Self.duration(state.delayMinutes))", .orange) : ("On Time", .green)
        }
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
    }

    /// 45 → "45m", 85 → "1h 25m".
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")"
    }
}

/// "Departs in 1:23:45" / "Lands in 52:10" / "Landed 2:15 PM".
private struct FlightPhaseView: View {
    let state: FlightActivityAttributes.ContentState
    let phase: FlightActivityAttributes.ContentState.Phase
    var destination = ""

    /// The app's phase, moved on by one step once the stale date (the next departure or landing) passes.
    static func phase(_ s: FlightActivityAttributes.ContentState, isStale: Bool) -> FlightActivityAttributes.ContentState.Phase {
        let now = Date.now
        switch s.phase {
        case .scheduled where isStale || now >= s.departs: return now >= s.arrives ? .landed : .inAir
        case .inAir where isStale || now >= s.arrives: return .landed
        default: return s.phase
        }
    }

    /// "1 hr, 24 min", ticking by the minute on its own. Minutes rather than a seconds timer,
    /// because the Lock Screen blanks out seconds ("1:24:--") while the phone is locked.
    static func countdown(to date: Date) -> some View {
        Text(.currentDate, format: .offset(to: date, allowedFields: [.hour, .minute], sign: .never))
            .fontWeight(.semibold)
            .monospacedDigit()
    }

    var body: some View {
        switch phase {
        case .scheduled:
            HStack(spacing: 4) {
                Text("Departs in").foregroundStyle(.secondary)
                Self.countdown(to: state.departs)
            }
        case .inAir:
            HStack(spacing: 4) {
                Text("Lands in").foregroundStyle(.secondary)
                Self.countdown(to: state.arrives)
            }
        case .landed:
            Text(destination.isEmpty ? "Welcome to your destination" : "Welcome to \(destination)").foregroundStyle(.secondary)
        case .canceled:
            Text("Check with your airline").foregroundStyle(.secondary)
        }
    }
}

/// Gate (big) with the terminal under it before departure; baggage belt after landing.
private struct GateLine: View {
    let state: FlightActivityAttributes.ContentState
    let phase: FlightActivityAttributes.ContentState.Phase
    var showsDetail = true

    var body: some View {
        let (main, detail): (String?, String?) = switch phase {
        case .landed, .inAir:
            state.baggageBelt.map { ("Bags \($0)", state.arrivalTerminal.map { "Terminal \($0)" }) }
                ?? (state.arrivalTerminal.map { "Terminal \($0)" }, nil)
        case .scheduled, .canceled:
            state.gate.map { ("Gate \($0)", state.terminal.map { "Terminal \($0)" }) }
                ?? (state.terminal.map { "Terminal \($0)" }, nil)
        }
        if let main {
            VStack(alignment: .trailing, spacing: 0) {
                Text(main).font(.headline)
                if showsDetail, let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }
}

private struct CompactCountdown: View {
    let state: FlightActivityAttributes.ContentState
    let phase: FlightActivityAttributes.ContentState.Phase

    var body: some View {
        Group {
            switch phase {
            case .scheduled:
                if let gate = state.gate, state.departs.timeIntervalSinceNow < 3600 {
                    Text("Gate \(gate)").foregroundStyle(.blue).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text(timerInterval: Date.now...max(Date.now, state.departs), countsDown: true, showsHours: true)
                }
            case .inAir:
                Text(timerInterval: Date.now...max(Date.now, state.arrives), countsDown: true, showsHours: true)
            case .landed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .canceled:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 64, alignment: .trailing)
    }
}
