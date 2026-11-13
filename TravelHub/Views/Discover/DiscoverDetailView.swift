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

    private var existing: PlanItem? { (trip.planItems ?? []).first { $0.sourceID == item.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 20) {
                        titleBlock
                        addButton
                        if let summary, !summary.isEmpty {
                            Text(summary)
                                .font(.body)
                                .foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        locationBlock
                        linksBlock
                        Text("Source: \(item.source.rawValue)").font(.caption).foregroundStyle(.tertiary)
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
                PlanItemEditor(trip: trip, mode: existing.map { .edit($0) } ?? .fromDiscover(item))
            }
            #if os(iOS)
            .mapItemDetailSheet(isPresented: $showingAppleCard, item: mapItem)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 640)
        #endif
    }

    private var photoURL: URL? { heroURL ?? item.imageURL }

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
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(item.category.title, systemImage: item.category.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.category.color)
            Text(item.title).font(.title.bold())
            Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
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

    private var linksBlock: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if mapItem != nil {
                linkRow("Apple Maps Place Card", "Photos, ratings, hours", "map.fill", .blue) { showingAppleCard = true }
                Divider().padding(.leading, 58)
            }
            #endif
            if let url = item.externalURL {
                let (title, symbol): (String, String) = switch item.source {
                case .wikipedia: ("Read on Wikipedia", "book.closed.fill")
                case .ticketmaster: ("Get Tickets", "ticket.fill")
                default: ("Website", "safari.fill")
                }
                linkRow(title, url.host() ?? "", symbol, .gray) { openURL(url) }
            }
            if let phone = item.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                Divider().padding(.leading, 58)
                linkRow("Call", phone, "phone.fill", .green) { openURL(url) }
            }
        }
        .padding(.vertical, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
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
        if let raw = item.mapItemIdentifier, let id = MKMapItem.Identifier(rawValue: raw) {
            mapItem = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
        }
        if let c = item.coordinate {
            lookAround = try? await MKLookAroundSceneRequest(coordinate: c).scene
        }
    }
}
