import Foundation
import SwiftData

/// Looks up opening hours for plan stops that don't have them yet (added by hand, or saved before
/// hours were kept), so Plan can warn about visits while a place is closed. One Google call per
/// place, ever: places with no listing are remembered and not asked about again for a month.
@MainActor
enum PlanHours {
    private static var running: Set<UUID> = []

    static func fill(_ trip: Trip, context: ModelContext) async {
        guard GooglePlacesProvider.isEnabled, running.insert(trip.id).inserted else { return }
        defer { running.remove(trip.id) }
        let stale = Date.now.addingTimeInterval(-30 * 86400)
        let missing = (trip.planItems ?? []).filter {
            $0.isScheduled && $0.category != .events && $0.openingHoursData == nil && $0.coordinate != nil
                && ($0.hoursCheckedAt ?? .distantPast) < stale && $0.end > .now
        }
        guard !missing.isEmpty else { return }
        for item in missing.prefix(15) {
            guard let c = item.coordinate else { continue }
            let info = await GooglePlacesProvider().match(title: item.title, near: c)
            // Google refused (bad key, quota): try again another time rather than remembering "no hours".
            if info == nil, !(UserDefaults.standard.string(forKey: GooglePlacesProvider.problemKey) ?? "").isEmpty { break }
            item.openingHours = info?.hours
            item.hoursCheckedAt = .now
        }
        try? context.save()
    }
}
