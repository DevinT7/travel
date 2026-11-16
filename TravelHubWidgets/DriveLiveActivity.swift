import ActivityKit
import SwiftUI
import WidgetKit

private let driveColor = Color(red: 0.42, green: 0.58, blue: 0.78)

/// The next drive on the Lock Screen, in the Dynamic Island and, through the small family, on the
/// CarPlay dashboard. Kept to a glance: where to, when to leave, when you'll arrive.
struct DriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            DriveActivityContent(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color(red: 0.05, green: 0.10, blue: 0.11).opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            let tz = TimeZone(identifier: a.timeZoneIdentifier) ?? .current
            let phase = DrivePhase(s, isStale: context.isStale)
            return DynamicIsland {
                // Big glyph and the drive time sit in the roomy upper corners; the small labels
                // that the island's curve would clip go in the full-width bottom region.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "car.fill")
                        .font(.title2)
                        .foregroundStyle(driveColor)
                        .frame(width: 44, height: 44)
                        .background(driveColor.opacity(0.22), in: Circle())
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(DriveText.duration(s.remainingMinutes ?? s.minutes))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        let distance = s.remainingText ?? s.distanceText
                        if !distance.isEmpty {
                            Text(phase == .live ? "\(distance) left" : distance).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 6)
                    .frame(height: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text("Drive to").font(.caption).foregroundStyle(.secondary)
                        Text(a.toName).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            TimeColumn(label: s.isLive ? "Started" : "Leave", time: s.leaveAt, tz: tz, alignment: .leading)
                            DriveRouteLine(state: s, phase: phase)
                            ArriveColumn(state: s, phase: phase, tz: tz)
                        }
                        // Centered: the island's bottom corners curve in and clip leading text.
                        DriveStatusLine(state: s, phase: phase, tz: tz)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: "car.fill").foregroundStyle(driveColor)
            } compactTrailing: {
                DriveCompactCountdown(state: s, phase: phase, tz: tz).foregroundStyle(driveColor)
            } minimal: {
                Image(systemName: "car.fill").foregroundStyle(driveColor)
            }
            .keylineTint(driveColor)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

private struct DriveActivityContent: View {
    @Environment(\.activityFamily) private var family
    let attributes: DriveActivityAttributes
    let state: DriveActivityAttributes.ContentState
    let isStale: Bool

    private var tz: TimeZone { TimeZone(identifier: attributes.timeZoneIdentifier) ?? .current }

    var body: some View {
        if family == .small {
            // CarPlay dashboard / Watch: two lines, readable at a glance.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "car.fill").foregroundStyle(driveColor)
                    Text(attributes.toName).font(.headline).lineLimit(1)
                }
                Text(DriveText.status(state, phase: DrivePhase(state, isStale: isStale), tz: tz))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(driveColor, in: Circle())
                    Text("Drive to \(attributes.toName)").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DriveText.pill(state, phase: DrivePhase(state, isStale: isStale)))
                        .font(.caption.weight(.semibold)).foregroundStyle(driveColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(driveColor.opacity(0.18), in: Capsule())
                }
                HStack(spacing: 10) {
                    TimeColumn(label: state.isLive ? "Started" : "Leave", time: state.leaveAt, tz: tz, alignment: .leading)
                    DriveRouteLine(state: state, phase: DrivePhase(state, isStale: isStale))
                    ArriveColumn(state: state, phase: DrivePhase(state, isStale: isStale), tz: tz)
                }
                HStack {
                    DriveStatusLine(state: state, phase: DrivePhase(state, isStale: isStale), tz: tz, alignment: .leading)
                        .font(.subheadline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(attributes.fromName.isEmpty ? attributes.toAddress : "From \(attributes.fromName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(16)
        }
    }
}

private struct TimeColumn: View {
    let label: String
    let time: Date
    let tz: TimeZone
    let alignment: HorizontalAlignment
    var color: Color = .primary

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(time.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz)))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .fixedSize()
    }
}

/// "Arrive" from the plan, or the live "ETA" (orange when it's later than planned).
private struct ArriveColumn: View {
    let state: DriveActivityAttributes.ContentState
    let phase: DrivePhase
    let tz: TimeZone

    var body: some View {
        if phase == .live, let eta = state.etaAt {
            TimeColumn(label: "ETA", time: eta, tz: tz, alignment: .trailing,
                       color: state.minutesLate >= 5 ? .orange : .green)
        } else if phase == .arrived, state.isLive {
            TimeColumn(label: "Arrived", time: state.arriveAt, tz: tz, alignment: .trailing)
        } else {
            TimeColumn(label: "Arrive", time: state.arriveAt, tz: tz, alignment: .trailing)
        }
    }
}

enum DrivePhase {
    case upcoming, driving, live, arrived

    /// The app's view of the drive, moved on by the stale date (set to the departure, then the
    /// arrival) even when the app hasn't run.
    init(_ s: DriveActivityAttributes.ContentState, isStale: Bool) {
        let now = Date.now
        if s.arrived == true { self = .arrived }
        else if s.isLive { self = .live }
        else if now >= s.arriveAt { self = .arrived }
        else if now >= s.leaveAt || isStale { self = .driving }
        else { self = .upcoming }
    }
}

/// Before leaving: car, dashed road, flag. On the road: a bar that fills on the system clock.
private struct DriveRouteLine: View {
    let state: DriveActivityAttributes.ContentState
    let phase: DrivePhase

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "car.fill").font(.caption2).foregroundStyle(driveColor)
            Group {
                switch phase {
                case .upcoming:
                    Capsule()
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
                        .frame(height: 2)
                case .driving where state.arriveAt > state.leaveAt:
                    ProgressView(timerInterval: state.leaveAt...state.arriveAt, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.linear)
                case .live:
                    ProgressView(value: state.progress ?? 0).progressViewStyle(.linear)
                case .driving, .arrived:
                    ProgressView(value: 1).progressViewStyle(.linear)
                }
            }
            .tint(driveColor)
            .frame(maxWidth: .infinity)
            Image(systemName: "flag.checkered").font(.caption2)
                .foregroundStyle(phase == .arrived ? driveColor : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Leave in 12 min" / "Arriving at 3:41 PM" / "You've arrived". Minutes, not seconds, because
/// the Lock Screen blanks seconds while the phone is locked.
private struct DriveStatusLine: View {
    let state: DriveActivityAttributes.ContentState
    let phase: DrivePhase
    let tz: TimeZone
    var alignment: TextAlignment = .center

    /// Compared with the plan: "On time", "6 min late", "4 min early".
    private var lateness: Text {
        guard state.plannedArrival != nil else {
            return Text("\(state.remainingMinutes ?? 0) min to go").fontWeight(.semibold)
        }
        // Leaving early isn't news; only running behind the plan is.
        let late = state.minutesLate
        if late >= 5 { return Text("\(late) min behind plan").fontWeight(.semibold).foregroundStyle(.orange) }
        return Text("On time").fontWeight(.semibold).foregroundStyle(.green)
    }

    var body: some View {
        // One Text, so a live countdown (which stretches to fill its row) still centers or leads
        // with the rest of the line.
        Group {
            switch phase {
            case .upcoming:
                Text("Leave in ").foregroundStyle(.secondary)
                    + Text(.currentDate, format: .offset(to: state.leaveAt, allowedFields: [.hour, .minute], sign: .never))
                        .fontWeight(.semibold)
            case .driving:
                Text("Arriving around ").foregroundStyle(.secondary)
                    + Text(DriveText.time(state.arriveAt, tz)).fontWeight(.semibold)
            case .live:
                Text(Image(systemName: "location.fill")).foregroundStyle(.green)
                    + Text(" Live · ").foregroundStyle(.secondary)
                    + lateness
            case .arrived:
                Text("You've arrived").foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(alignment)
    }
}

/// Compact island: minutes until it's time to leave, then the arrival time.
private struct DriveCompactCountdown: View {
    let state: DriveActivityAttributes.ContentState
    let phase: DrivePhase
    /// The trip's zone, like every other time in the app.
    let tz: TimeZone

    var body: some View {
        Group {
            switch phase {
            case .upcoming:
                Text(timerInterval: Date.now...max(state.leaveAt, .now), countsDown: true, showsHours: false)
                    .frame(maxWidth: 44)
            case .driving:
                Text(DriveText.time(state.arriveAt, tz))
            case .live:
                Text(DriveText.time(state.etaAt ?? state.arriveAt, tz))
            case .arrived:
                Image(systemName: "flag.checkered")
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private enum DriveText {
    /// 26 → "26 min", 135 → "2h 15m"
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")"
    }

    /// Planned "27 min · 11 mi"; "19 min · 9 mi left" on the road; "Drove 24 min" at the end.
    static func pill(_ s: DriveActivityAttributes.ContentState, phase: DrivePhase) -> String {
        switch phase {
        case .live:
            let left = s.remainingText.map { " · \($0) left" } ?? ""
            return duration(s.remainingMinutes ?? s.minutes) + left
        case .arrived where s.isLive:
            return "Drove " + duration(max(1, Int(s.arriveAt.timeIntervalSince(s.leaveAt) / 60)))
        default:
            return summary(s)
        }
    }

    /// "32 min · 18 km"
    static func summary(_ s: DriveActivityAttributes.ContentState) -> String {
        s.distanceText.isEmpty ? duration(s.minutes) : "\(duration(s.minutes)) · \(s.distanceText)"
    }

    /// Small family: "Leave 2:35 PM · 32 min", then "Arrive 3:07 PM".
    static func status(_ s: DriveActivityAttributes.ContentState, phase: DrivePhase, tz: TimeZone) -> String {
        switch phase {
        case .upcoming: "Leave \(time(s.leaveAt, tz)) · \(duration(s.minutes))"
        case .driving: "Arrive \(time(s.arriveAt, tz))"
        case .live: "ETA \(time(s.etaAt ?? s.arriveAt, tz)) · \(duration(s.remainingMinutes ?? s.minutes)) left"
        case .arrived: "Arrived"
        }
    }

    static func time(_ d: Date, _ tz: TimeZone) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz))
    }
}
