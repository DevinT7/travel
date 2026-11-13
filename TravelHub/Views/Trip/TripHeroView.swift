import SwiftUI
import MapKit

/// Map header showing flight routes (or the destination) with the trip name and countdown.
struct TripHeroView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: cameraPosition, interactionModes: [.pan, .zoom]) {
                ForEach(trip.sortedFlights) { flight in
                    MapPolyline(coordinates: [flight.departure.coordinate, flight.arrival.coordinate], contourStyle: .geodesic)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))
                    Annotation(flight.departure.iata, coordinate: flight.departure.coordinate, anchor: .center) {
                        airportDot
                    }
                    .annotationTitles(.visible)
                    Annotation(flight.arrival.iata, coordinate: flight.arrival.coordinate, anchor: .center) {
                        airportDot
                    }
                    .annotationTitles(.visible)
                    if let position = FlightProgress.position(of: flight) {
                        Annotation("", coordinate: position.coordinate) {
                            Image(systemName: "airplane")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Color.accentColor, in: Circle())
                                .rotationEffect(.degrees(position.bearing - 90))
                        }
                    }
                }
                if trip.sortedFlights.isEmpty {
                    Marker(trip.destinationName, systemImage: "mappin", coordinate: trip.coordinate)
                    ForEach(trip.sortedStays) { stay in
                        Marker(stay.name, systemImage: "bed.double.fill", coordinate: stay.coordinate).tint(.indigo)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .safeAreaPadding(.vertical, 24)
            .frame(height: 260)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 6) {
                Text(countdown.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.tint)
                Text(trip.displayName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text(dateRangeText(trip.startDate, trip.endDate, tz: trip.timeZone) + " · \(trip.days.count) days")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .readableWidth()
        }
    }

    private var airportDot: some View {
        Circle()
            .fill(.white)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
    }

    private var cameraPosition: MapCameraPosition {
        if trip.sortedFlights.isEmpty {
            return .region(MKCoordinateRegion(center: trip.coordinate, span: .init(latitudeDelta: 0.35, longitudeDelta: 0.35)))
        }
        return .automatic
    }

    private var countdown: String {
        let cal = trip.calendar
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: trip.startDate)
        let end = cal.startOfDay(for: trip.endDate)
        if today < start {
            let days = cal.dateComponents([.day], from: today, to: start).day ?? 0
            return days == 1 ? "Tomorrow" : "In \(days) days"
        } else if today <= end {
            let day = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
            return "Day \(day) of \(trip.days.count)"
        }
        return "Trip complete"
    }
}

/// Where a flight currently is, by interpolating along the great circle by elapsed time.
enum FlightProgress {
    struct Position { let coordinate: CLLocationCoordinate2D; let bearing: Double }

    static func fraction(of flight: FlightSegment, at date: Date = .now) -> Double? {
        let start = flight.departure.best, end = flight.arrival.best
        guard end > start, date > start, date < end else { return nil }
        return date.timeIntervalSince(start) / end.timeIntervalSince(start)
    }

    static func position(of flight: FlightSegment, at date: Date = .now) -> Position? {
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
