import SwiftUI
import SwiftData
import MapKit

struct DiscoverDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: DiscoverItem
    let trip: Trip
    let distance: CLLocationDistance?

    @State private var summary: String?
    @State private var heroURL: URL?
    @State private var lookAround: MKLookAroundScene?
    @State private var mapItem: MKMapItem?
    @State private var showingAppleCard = false
    @State private var showingScheduler = false
    /// Rating and hours: from the item if it came from Google, otherwise looked up when the page opens.
    @State private var google: GooglePlaceInfo?

    init(item: DiscoverItem, trip: Trip, distance: CLLocationDistance?) {
        self.item = item
        self.trip = trip
        self.distance = distance
        _google = State(initialValue: item.google)
    }

    /// The place with whatever Google added on this page, so its hours go into the plan with it.
    private var enriched: DiscoverItem {
        var copy = item
        copy.google = google
        return copy
    }

    private var existing: PlanItem? { (trip.planItems ?? []).first { $0.sourceID == item.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 20) {
                        titleBlock
                        addButton
                        if let hours = google?.hours { PlaceHoursCard(hours: hours) }
                        if let summary, !summary.isEmpty {
                            Text(summary)
                                .font(.body)
                                .foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        locationBlock
                        linksBlock
                        Text(sourceText).font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(Metrics.gutter)
                }
            }
            .background(Color.appBackground)
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await loadExtras() }
            .sheet(isPresented: $showingScheduler) {
                PlanItemEditor(trip: trip, mode: existing.map { .edit($0) } ?? .fromDiscover(enriched))
            }
            #if os(iOS)
            .mapItemDetailSheet(isPresented: $showingAppleCard, item: mapItem)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 640)
        #endif
    }

    /// Wikipedia's or Ticketmaster's own photo first, then Google's.
    private var photoURL: URL? { heroURL ?? item.imageURL ?? google?.photoURL() }
    private var showsGooglePhoto: Bool { heroURL == nil && item.imageURL == nil && google?.photoName != nil }

    private var sourceText: String {
        if item.source == .google { return "Source: Google Maps" }
        return "Source: \(item.source.rawValue)" + (google == nil ? "" : " · Ratings and hours from Google Maps")
    }

    /// Photo if we have one, otherwise an interactive Look Around view, otherwise a short tinted header.
    @ViewBuilder
    private var hero: some View {
        if photoURL == nil, let lookAround {
            LookAroundPreview(initialScene: lookAround, allowsNavigation: true, badgePosition: .bottomTrailing)
                .frame(height: 300)
        } else {
            PlaceImage(url: photoURL, category: item.category, symbolSize: 44)
                .frame(height: photoURL == nil ? 180 : 300)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if showsGooglePhoto, let credit = google?.photoCredit {
                        Text("Photo: \(credit)")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: Capsule())
                            .padding(10)
                    }
                }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(item.category.title, systemImage: item.category.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.category.color)
            Text(item.title).font(.title.bold())
            Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
            if let rating = ratingLine {
                rating.font(.subheadline).padding(.top, 2)
            }
            HStack(spacing: 14) {
                if let date = item.eventDate {
                    Label(date.weekdayDayMonth(in: trip.timeZone) + ", " + date.time(in: trip.timeZone), systemImage: "calendar")
                }
                if let price = item.priceText { Label(price, systemImage: "tag") }
                if let d = distanceText(distance) { Label(d, systemImage: "location") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    /// "★ 4.6 · 2,314 reviews · $$"
    private var ratingLine: Text? {
        guard let google, google.rating != nil || google.priceLevel != nil else { return nil }
        var parts: [Text] = []
        if let r = google.rating {
            let star = Text(Image(systemName: "star.fill")).foregroundStyle(.orange)
            parts.append(Text("\(star) \(r.formatted(.number.precision(.fractionLength(1))))").fontWeight(.semibold))
            if let n = google.ratingCount {
                parts.append(Text("\(n.formatted()) review\(n == 1 ? "" : "s")").foregroundStyle(.secondary))
            }
        }
        if let price = google.priceText { parts.append(Text(price).foregroundStyle(.secondary)) }
        var line = parts[0]
        for p in parts.dropFirst() { line = Text("\(line)\(Text(" · ").foregroundStyle(.secondary))\(p)") }
        return line
    }

    private var addButton: some View {
        Button {
            showingScheduler = true
        } label: {
            Label(existing == nil ? "Add to Plan" : (existing!.isScheduled ? "In Your Plan" : "Saved · Pick a Time"),
                  systemImage: existing == nil ? "calendar.badge.plus" : "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(existing == nil ? Color.accentColor : .green)
    }

    @ViewBuilder
    private var locationBlock: some View {
        if let coordinate = item.coordinate {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) {
                    Marker(item.title, systemImage: item.category.symbol, coordinate: coordinate).tint(item.category.color)
                    ForEach(trip.sortedStays) { stay in
                        Marker(stay.name, systemImage: "bed.double.fill", coordinate: stay.coordinate).tint(Color.stay)
                    }
                }
                .frame(height: 170)
                .allowsHitTesting(false)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.address.isEmpty ? item.title : item.address).font(.subheadline).lineLimit(2)
                        if let d = distanceText(distance) {
                            Text("\(d) from \(trip.sortedStays.isEmpty ? "the city center" : "your stay")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Directions") {
                        let mi = mapItem ?? MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        if mapItem == nil { mi.name = item.title }
                        mi.openInMaps()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
                .padding(14)
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    private struct LinkItem: Identifiable {
        let title: String, subtitle: String, symbol: String, color: Color, action: () -> Void
        var id: String { title }
    }

    /// Apple Maps, Google Maps, website and phone, whichever this place has.
    private var links: [LinkItem] {
        var rows: [LinkItem] = []
        #if os(iOS)
        if mapItem != nil {
            rows.append(.init(title: "Apple Maps Place Card", subtitle: google == nil ? "Photos, ratings, hours" : "Photos and details",
                              symbol: "map.fill", color: .blue) { showingAppleCard = true })
        }
        #endif
        if let maps = google?.mapsURL {
            rows.append(.init(title: "Google Maps", subtitle: "Reviews and photos", symbol: "star.bubble.fill", color: .orange) { openURL(maps) })
        }
        if let url = item.externalURL ?? google?.website {
            let (title, symbol): (String, String) = switch item.source {
            case .wikipedia: ("Read on Wikipedia", "book.closed.fill")
            case .ticketmaster: ("Get Tickets", "ticket.fill")
            default: ("Website", "safari.fill")
            }
            rows.append(.init(title: title, subtitle: url.host() ?? "", symbol: symbol, color: .gray) { openURL(url) })
        }
        if let phone = item.phone ?? google?.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
            rows.append(.init(title: "Call", subtitle: phone, symbol: "phone.fill", color: .green) { openURL(url) })
        }
        return rows
    }

    @ViewBuilder
    private var linksBlock: some View {
        let rows = links
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Divider().padding(.leading, 58) }
                    linkRow(row.title, row.subtitle, row.symbol, row.color, action: row.action)
                }
            }
            .padding(.vertical, 4)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    private func linkRow(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CircleIcon(symbol: symbol, color: color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline).foregroundStyle(.primary)
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadExtras() async {
        if item.source == .wikipedia, let s = try? await WikipediaProvider().summary(title: item.title) {
            summary = s.text
            heroURL = s.image ?? item.imageURL
        } else {
            summary = item.summary
        }
        if google == nil, item.source != .ticketmaster, let match = await GooglePlacesProvider().match(item) {
            withAnimation(.easeOut(duration: 0.25)) { google = match }
        }
        if let raw = item.mapItemIdentifier, let id = MKMapItem.Identifier(rawValue: raw) {
            mapItem = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
        }
        if let c = item.coordinate {
            lookAround = try? await MKLookAroundSceneRequest(coordinate: c).scene
        }
    }
}
