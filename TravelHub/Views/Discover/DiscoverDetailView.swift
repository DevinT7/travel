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
                            Text(summary).font(.body).foregroundStyle(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        locationBlock
                        linksBlock
                        Text("Source: \(item.source.rawValue)").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(20)
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

    /// Photo if we have one, otherwise an interactive Look Around street view, otherwise a short color header.
    @ViewBuilder
    private var hero: some View {
        if photoURL == nil, let lookAround {
            LookAroundPreview(initialScene: lookAround, allowsNavigation: true, badgePosition: .bottomTrailing)
                .frame(height: 280)
        } else {
            PlaceImage(url: photoURL, category: item.category)
                .frame(height: photoURL == nil ? 170 : 280)
                .frame(maxWidth: .infinity)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: item.category.symbol)
                Text(item.category.title)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(item.category.color)
            .textCase(.uppercase)
            Text(item.title).font(.system(.largeTitle, design: .rounded).bold())
            Text(item.subtitle).font(.headline).foregroundStyle(.secondary)
            if let date = item.eventDate {
                Label(date.weekdayDayMonth(in: trip.timeZone) + " · " + date.time(in: trip.timeZone), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
            }
            if let price = item.priceText {
                Label(price, systemImage: "tag").font(.subheadline)
            }
        }
    }

    private var addButton: some View {
        Button {
            showingScheduler = true
        } label: {
            Label(existing == nil ? "Add to Plan" : (existing!.isScheduled ? "In your plan · Edit" : "Saved · Pick a time"),
                  systemImage: existing == nil ? "calendar.badge.plus" : "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(existing == nil ? Color.accentColor : .green)
    }

    @ViewBuilder
    private var locationBlock: some View {
        if let coordinate = item.coordinate {
            VStack(alignment: .leading, spacing: 10) {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) {
                    Marker(item.title, systemImage: item.category.symbol, coordinate: coordinate).tint(item.category.color)
                    ForEach(trip.sortedStays) { stay in
                        Marker(stay.name, systemImage: "bed.double.fill", coordinate: stay.coordinate).tint(.indigo)
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !item.address.isEmpty { Text(item.address).font(.subheadline) }
                        if let distance {
                            Text("\(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))) from \(trip.sortedStays.isEmpty ? "the city center" : "your stay")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                        let mi = mapItem ?? MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        if mapItem == nil { mi.name = item.title }
                        mi.openInMaps()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var linksBlock: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if mapItem != nil {
                linkRow("Apple Maps place card", "Photos, ratings, hours", "map.fill") { showingAppleCard = true }
            }
            #endif
            if let url = item.externalURL {
                let (title, symbol): (String, String) = switch item.source {
                case .wikipedia: ("Read on Wikipedia", "book.closed.fill")
                case .ticketmaster: ("Get tickets", "ticket.fill")
                default: ("Website", "safari.fill")
                }
                linkRow(title, url.host() ?? "", symbol) { openURL(url) }
            }
            if let phone = item.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                linkRow("Call", phone, "phone.fill") { openURL(url) }
            }
        }
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func linkRow(_ title: String, _ subtitle: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
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
