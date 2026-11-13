import SwiftUI
import SwiftData
import MapKit

/// The destination photo fading into the page, with the trip name and countdown centered beneath it.
struct TripHeroView: View {
    let trip: Trip

    var body: some View {
        VStack(spacing: 0) {
            TripCover(trip: trip)
                .frame(height: 330)
                .frame(maxWidth: .infinity)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                             .init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 6) {
                Text(trip.displayName)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("\(countdown) · \(trip.days.count)-day trip")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, -64)
        }
    }

    private var countdown: String {
        let cal = trip.calendar
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: trip.startDate)
        let end = cal.startOfDay(for: trip.endDate)
        if today < start {
            let days = cal.dateComponents([.day], from: today, to: start).day ?? 0
            return days == 1 ? "Leaves tomorrow" : "Leaves in \(days) days"
        } else if today <= end {
            let day = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
            return "Day \(day)"
        }
        return "Completed"
    }
}

/// Menu listing every trip, used wherever the app lets you switch trips.
struct TripSwitcherMenu<Label: View>: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            ForEach(trips) { trip in
                Button {
                    model.selectedTripID = trip.id
                } label: {
                    SwiftUI.Label("\(trip.displayName) · \(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone))",
                                  systemImage: trip.id == model.currentTrip(from: trips)?.id ? "checkmark" : "suitcase")
                }
            }
            Divider()
            Button("New Trip…", systemImage: "plus") { model.isPresentingNewTrip = true }
        } label: {
            label
        }
        .accessibilityLabel("Switch trip")
    }
}

/// The flight routes on a map, drawn as great-circle arcs.
struct RouteMapCard: View {
    let trip: Trip

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in map }
    }

    private var map: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(trip.sortedFlights) { flight in
                MapPolyline(coordinates: [flight.departure.coordinate, flight.arrival.coordinate], contourStyle: .geodesic)
                    .stroke(Color.flight, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
                Annotation(flight.departure.iata, coordinate: flight.departure.coordinate, anchor: .center) { dot }
                    .annotationTitles(.visible)
                Annotation(flight.arrival.iata, coordinate: flight.arrival.coordinate, anchor: .center) { dot }
                    .annotationTitles(.visible)
                if let position = FlightProgress.position(of: flight) {
                    Annotation("", coordinate: position.coordinate) {
                        Image(systemName: "airplane")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.flight, in: Circle())
                            .rotationEffect(.degrees(position.bearing - 90))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .safeAreaPadding(.vertical, 24)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private var dot: some View {
        Circle().fill(.white).frame(width: 10, height: 10).overlay(Circle().stroke(Color.flight, lineWidth: 3))
    }
}

/// Where a flight currently is, by interpolating along the great circle by elapsed time.
enum FlightProgress {
    struct Position { let coordinate: CLLocationCoordinate2D; let bearing: Double }

    /// From two hours before departure until half an hour after landing: the window where live
    /// updates are worth fetching.
    static func isInLiveWindow(_ flight: FlightSegment, at date: Date = .now) -> Bool {
        date > flight.departure.best.addingTimeInterval(-2 * 3600) && date < flight.arrival.best.addingTimeInterval(30 * 60)
    }

    static func fraction(of flight: FlightSegment, at date: Date = .now) -> Double? {
        let start = flight.departure.best, end = flight.arrival.best
        guard end > start, date > start, date < end else { return nil }
        return date.timeIntervalSince(start) / end.timeIntervalSince(start)
    }

    static func position(of flight: FlightSegment, at date: Date = .now) -> Position? {
        if let live = livePosition(of: flight, at: date) { return live }
        return estimatedPosition(of: flight, at: date)
    }

    /// The position AeroDataBox last reported, if it's under 30 minutes old and the flight hasn't landed.
    static func livePosition(of flight: FlightSegment, at date: Date = .now) -> Position? {
        guard let lat = flight.liveLatitude, let lon = flight.liveLongitude, let at = flight.livePositionAt,
              date.timeIntervalSince(at) < 30 * 60, date < flight.arrival.best else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let heading = flight.liveHeading ?? bearing(coordinate, flight.arrival.coordinate)
        return Position(coordinate: coordinate, bearing: heading)
    }

    /// Where the plane should be if it's flying the great circle on schedule.
    static func estimatedPosition(of flight: FlightSegment, at date: Date = .now) -> Position? {
        guard let f = fraction(of: flight, at: date) else { return nil }
        let a = flight.departure.coordinate, b = flight.arrival.coordinate
        let p = interpolate(a, b, f)
        let ahead = interpolate(a, b, min(1, f + 0.01))
        return Position(coordinate: p, bearing: bearing(p, ahead))
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ f: Double) -> CLLocationCoordinate2D {
        let φ1 = rad(a.latitude), λ1 = rad(a.longitude), φ2 = rad(b.latitude), λ2 = rad(b.longitude)
        let d = 2 * asin(sqrt(pow(sin((φ2 - φ1) / 2), 2) + cos(φ1) * cos(φ2) * pow(sin((λ2 - λ1) / 2), 2)))
        guard d > 0 else { return a }
        let A = sin((1 - f) * d) / sin(d), B = sin(f * d) / sin(d)
        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)
        return .init(latitude: deg(atan2(z, sqrt(x * x + y * y))), longitude: deg(atan2(y, x)))
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = rad(a.latitude), φ2 = rad(b.latitude), Δλ = rad(b.longitude - a.longitude)
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return deg(atan2(y, x))
    }
}
