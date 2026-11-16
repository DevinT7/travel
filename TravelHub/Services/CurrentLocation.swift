import Foundation
import CoreLocation

/// Where the phone is right now, for "From: Current Location" when planning or starting a drive.
/// iPhone only; the Mac always picks a starting place by name.
@MainActor
enum CurrentLocation {
    static var isAvailable: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Location is already allowed, so asking for a fix won't show a permission prompt.
    static var isAuthorized: Bool {
        #if os(iOS)
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
        #else
        false
        #endif
    }

    /// One fresh fix, asking for "While Using" permission the first time. nil when location is off,
    /// denied, or nothing arrives within `timeout`.
    static func fetch(timeout: Duration = .seconds(10)) async -> CLLocationCoordinate2D? {
        #if os(iOS)
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        return await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                            return nil
                        }
                        if let l = update.location, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 1000,
                           abs(l.timestamp.timeIntervalSinceNow) < 120 {
                            return l.coordinate
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #else
        return nil
        #endif
    }

    /// A short name for a spot: the neighborhood or city ("Santa Monica", "Dallas"), with the street
    /// address as detail.
    static func describe(_ coordinate: CLLocationCoordinate2D) async -> (name: String, address: String) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let p = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return ("Starting point", "")
        }
        let name = p.subLocality ?? p.locality ?? p.name ?? "Starting point"
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street.isEmpty ? nil : street, p.locality].compactMap { $0 }.joined(separator: ", ")
        return (name, address)
    }
}
