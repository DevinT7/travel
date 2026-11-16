import SwiftUI
import SwiftData
import MapKit

struct DiscoverView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let trip: Trip

    @State private var model: DiscoverModel
    @State private var selectedCategory: DiscoverCategory?
    @State private var query = ""
    @State private var openedItem: DiscoverItem?
    @State private var layout: PlaceLayout = .cards
    /// "Restaurant", "Bakery"…: narrows a category to one kind of place. Nil shows them all.
    @State private var kindFilter: String?
    @State private var sort: PlaceSort = .best
    /// Hide places that are closed right now (only offered when the results have hours).
    @State private var openNowOnly = false
    /// Another city to browse instead of the destination (a day trip or the next stop).
    @State private var exploring: ExplorePlace?
    @State private var showingPlacePicker = false
    /// Waiting for a location fix before loading anything, so results don't load twice.
    @State private var locating: Bool

    init(trip: Trip) {
        self.trip = trip
        let place = DiscoverModel.lastPlace[trip.id]
        _exploring = State(initialValue: place)
        _model = State(initialValue: DiscoverModel.cached(trip: trip, place: place))
        _locating = State(initialValue: place == nil && Self.shouldTryNearMe(trip))
    }

    /// Start near the person rather than the destination the first time Discover opens, if they might
    /// be there: always while the trip is on (prompting for location if needed), otherwise only when
    /// location is already allowed, to check whether they're in the area.
    private static func shouldTryNearMe(_ trip: Trip) -> Bool {
        guard CurrentLocation.isAvailable, !DiscoverModel.triedNearMe.contains(trip.id),
              !DiscoverModel.pickedByHand.contains(trip.id) else { return false }
        return trip.isUnderway || CurrentLocation.isAuthorized
    }

    private var placeName: String { exploring?.name ?? trip.destinationName }
    private var isNearMe: Bool { exploring?.isNearMe == true }
    /// "near you" or "near Seattle", for counts and empty states.
    private var nearText: String { isNearMe ? "near you" : "near \(placeName)" }

    private var savedIDs: Set<String> { Set((trip.planItems ?? []).compactMap(\.sourceID)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                placeBar
                categories
                Group {
                    if locating {
                        locatingPlaceholder
                    } else if !query.isEmpty {
                        searchResults
                    } else if let selectedCategory {
                        categoryPage(selectedCategory)
                    } else {
                        allCategories
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                // A new place reloads every section.
                .id(exploring?.id ?? "destination")
            }
            .padding(.bottom, 32)
            #if os(macOS)
            .padding(.top, 12)
            #endif
            .readableWidth(1320)
        }
        .background(Color.appBackground)
        .navigationTitle(trip.displayName)
        .largeTitle()
        .searchable(text: $query, prompt: isNearMe ? "Search places near you" : "Search places in \(placeName)")
        .task { await startNearMe() }
        .onSubmit(of: .search) { Task { await model.search(query) } }
        .task(id: query) {
            // Debounced type-ahead search.
            guard !query.isEmpty else { model.clearSearch(); return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .sheet(isPresented: $showingPlacePicker) {
            ExplorePlacePicker(trip: trip, current: exploring) { explore($0) }
        }
        .sheet(item: $openedItem) { item in
            DiscoverDetailView(item: item, trip: trip, distance: model.distance(to: item))
        }
    }

    // MARK: Where to look

    private var placeBar: some View {
        HStack(spacing: 10) {
            Button {
                showingPlacePicker = true
            } label: {
                HStack(spacing: 6) {
                    if locating {
                        ProgressView().controlSize(.small)
                        Text("Finding your location…").fontWeight(.semibold).lineLimit(1)
                    } else {
                        Image(systemName: isNearMe ? "location.fill" : exploring == nil ? "suitcase.fill" : "location.magnifyingglass")
                            .foregroundStyle(.tint)
                        if isNearMe {
                            Text("Near You").fontWeight(.semibold)
                            Text(placeName).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text("Near \(placeName)").fontWeight(.semibold).lineLimit(1)
                        }
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.cardBackground, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Explore another city")

            if exploring != nil, !isNearMe {
                Button {
                    explore(nil)
                } label: {
                    Label("Back to \(trip.destinationName)", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func explore(_ place: ExplorePlace?, byHand: Bool = true) {
        if byHand { DiscoverModel.pickedByHand.insert(trip.id) }
        withAnimation(.snappy) {
            exploring = place
            DiscoverModel.lastPlace[trip.id] = place
            model = DiscoverModel.cached(trip: trip, place: place)
            query = ""
        }
    }

    /// The first time Discover opens for a trip, switch to "Near You" if the person is on the trip or
    /// already in the area. While showing "Near You", catch up if they've moved since.
    private func startNearMe() async {
        if isNearMe, let current = exploring {
            guard let here = await ExplorePlaces.nearMe(), here.distance(from: current.coordinate) > 1000 else { return }
            explore(here, byHand: false)
            return
        }
        guard locating else { return }
        DiscoverModel.triedNearMe.insert(trip.id)
        let here = await ExplorePlaces.nearMe()
        if let here, !DiscoverModel.pickedByHand.contains(trip.id),
           trip.isUnderway || here.distance(from: trip.coordinate) < 100_000 {
            explore(here, byHand: false)
        }
        withAnimation(.snappy) { locating = false }
    }

    private var locatingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Color.cardBackground).frame(height: 230)
            LazyVGrid(columns: photoColumns, spacing: 12) { ForEach(0..<4, id: \.self) { _ in PlaceholderCard() } }
        }
        .accessibilityLabel("Finding places near you")
    }

    // MARK: Category circles

    private var categories: some View {
        HorizontalScroller {
            HStack(spacing: 6) {
                CategoryCircle(title: "For You", symbol: "sparkles", color: .accentColor, isSelected: selectedCategory == nil) {
                    select(nil)
                }
                ForEach(DiscoverCategory.browsable) { c in
                    CategoryCircle(title: c.title, symbol: c.symbol, color: c.color, isSelected: selectedCategory == c) {
                        select(c)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter - 4)
            .padding(.vertical, 4)
        }
    }

    private func select(_ category: DiscoverCategory?) {
        withAnimation(.snappy) {
            selectedCategory = category
            kindFilter = nil
            openNowOnly = false
        }
    }

    // MARK: "For You": a top pick then a section per category

    private var allCategories: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let featured = model.state(for: .sights).items.first(where: { $0.imageURL != nil }) {
                FeaturedCard(item: featured, distance: model.distance(to: featured), isSaved: savedIDs.contains(featured.id)) {
                    openedItem = featured
                }
            }
            ForEach(DiscoverCategory.browsable) { category in
                section(category)
            }
        }
    }

    private var featuredID: String? { model.state(for: .sights).items.first(where: { $0.imageURL != nil })?.id }

    /// A row of photo cards per category. Apple Maps places have no photos of their own, so their
    /// cards show the Look Around street view of the place instead.
    private func section(_ category: DiscoverCategory) -> some View {
        let state = model.state(for: category)
        let items = state.items.filter { $0.id != featuredID }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(category.headline) {
                if !state.items.isEmpty {
                    SeeAllButton { select(category) }
                }
            }
            if let error = state.error {
                unavailable(category, error)
            } else {
                HorizontalScroller {
                    LazyHStack(spacing: 12) {
                        if items.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in PlaceholderCard().frame(width: 220) }
                        }
                        ForEach(items.prefix(12)) { item in
                            DiscoverCard(item: item, distance: model.distance(to: item), isSaved: savedIDs.contains(item.id),
                                         onOpen: { openedItem = item }, onToggleSave: { toggleSave(item) })
                                .frame(width: 220)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .bleedsToScreenEdge()
            }
        }
        .task { await model.load(category) }
    }

    private func placeList(_ items: [DiscoverItem]) -> some View {
        PlaceList(items: items, distance: { model.distance(to: $0) }, isSaved: { savedIDs.contains($0.id) },
                  onOpen: { openedItem = $0 }, onToggleSave: { toggleSave($0) })
    }

    // MARK: Single category

    enum PlaceLayout: String, CaseIterable, Identifiable {
        case cards, list, map
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .cards: "square.grid.2x2"
            case .list: "list.bullet"
            case .map: "map"
            }
        }
    }

    private let photoColumns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]

    /// The kinds of place in a category, most common first, when there's more than one to choose from.
    private func kinds(in items: [DiscoverItem]) -> [String] {
        let counts = Dictionary(grouping: items.compactMap(\.kind), by: { $0 }).mapValues(\.count)
        guard counts.count > 1 else { return [] }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    enum PlaceSort { case best, nearest, topRated }

    private func shown(_ items: [DiscoverItem]) -> [DiscoverItem] {
        var filtered = kindFilter.map { k in items.filter { $0.kind == k } } ?? items
        if openNowOnly {
            filtered = filtered.filter {
                switch $0.google?.hours?.status() {
                case .open?, .closingSoon?: true
                default: false
                }
            }
        }
        switch sort {
        case .best: return filtered
        case .nearest:
            return filtered.sorted { (model.distance(to: $0) ?? .infinity) < (model.distance(to: $1) ?? .infinity) }
        case .topRated:
            guard hasRatings else { return filtered }
            return filtered.sorted { Self.ratingScore($0) > Self.ratingScore($1) }
        }
    }

    /// A rating weighted by how many people gave it, so a 5.0 from 3 reviews doesn't beat a 4.7 from 3,000.
    private static func ratingScore(_ item: DiscoverItem) -> Double {
        guard let r = item.google?.rating else { return 0 }
        let n = Double(item.google?.ratingCount ?? 0), prior = 4.0, weight = 30.0
        return (r * n + prior * weight) / (n + weight)
    }

    private func categoryPage(_ category: DiscoverCategory) -> some View {
        let state = model.state(for: category)
        let items = shown(state.items)
        return VStack(alignment: .leading, spacing: 14) {
            categoryHeader(category, count: items.count, loaded: !state.items.isEmpty)
            kindChips(kinds(in: state.items), color: category.color)

            if let error = state.error {
                unavailable(category, error)
            } else if state.isLoading {
                LazyVGrid(columns: photoColumns, spacing: 12) { ForEach(0..<6, id: \.self) { _ in PlaceholderCard() } }
            } else if state.items.isEmpty, case .loaded = state {
                EmptyStateView(symbol: category.symbol, title: "Nothing found",
                               message: "No \(category.title.lowercased()) found \(nearText).")
            } else if items.isEmpty && openNowOnly {
                EmptyStateView(symbol: "clock", title: "Nothing open right now",
                               message: "Turn off Open now to see everything \(nearText).")
            } else {
                switch layout {
                case .cards: cardGrid(items, category: category)
                case .list: placeList(items)
                case .map:
                    DiscoverMapView(items: items, distance: { model.distance(to: $0) }, onOpen: { openedItem = $0 })
                        .frame(height: 560)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                        .id(kindFilter ?? "all")
                }
            }
        }
        .task(id: category) { await model.load(category) }
    }

    private var currentItems: [DiscoverItem] { selectedCategory.map { model.state(for: $0).items } ?? [] }
    private var hasRatings: Bool { currentItems.contains { $0.google?.rating != nil } }
    private var hasHours: Bool { currentItems.contains { $0.google?.hours != nil } }

    /// "Where to eat · 25 places", then sort and Cards / List / Map.
    private func categoryHeader(_ category: DiscoverCategory, count: Int, loaded: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.headline).font(.title2.bold())
                Text(loaded ? "\(count) place\(count == 1 ? "" : "s") \(nearText)" : "Looking \(nearText)…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Picker("Sort", selection: $sort) {
                    Label("Best Match", systemImage: "sparkles").tag(PlaceSort.best)
                    Label("Nearest", systemImage: "location").tag(PlaceSort.nearest)
                    if hasRatings { Label("Top Rated", systemImage: "star").tag(PlaceSort.topRated) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.cardBackground, in: Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Sort")
            Picker("View", selection: $layout.animation(.snappy)) {
                ForEach(PlaceLayout.allCases) { l in
                    Image(systemName: l.symbol).accessibilityLabel(l.title).tag(l)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func kindChips(_ kinds: [String], color: Color) -> some View {
        if !kinds.isEmpty || hasHours {
            HorizontalScroller {
                HStack(spacing: 8) {
                    if hasHours {
                        FilterChip(title: "Open now", symbol: "clock", isSelected: openNowOnly, color: .green) {
                            withAnimation(.snappy) { openNowOnly.toggle() }
                        }
                        if !kinds.isEmpty { Divider().frame(height: 20) }
                    }
                    if !kinds.isEmpty {
                        FilterChip(title: "All", isSelected: kindFilter == nil, color: color) {
                            withAnimation(.snappy) { kindFilter = nil }
                        }
                    }
                    ForEach(kinds, id: \.self) { kind in
                        FilterChip(title: kind, isSelected: kindFilter == kind, color: color) {
                            withAnimation(.snappy) { kindFilter = kindFilter == kind ? nil : kind }
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .padding(.horizontal, -Metrics.gutter)
        }
    }

    /// One big card up top, then a two-column grid of photo cards.
    @ViewBuilder
    private func cardGrid(_ items: [DiscoverItem], category: DiscoverCategory) -> some View {
        if let first = items.first {
            FeaturedCard(item: first, distance: model.distance(to: first), isSaved: savedIDs.contains(first.id),
                         label: sort == .nearest ? "Closest" : sort == .topRated ? "Top rated" : "Best match", height: 230,
                         onOpen: { openedItem = first }, onToggleSave: { toggleSave(first) })
        }
        LazyVGrid(columns: photoColumns, spacing: 12) {
            ForEach(items.dropFirst()) { item in
                DiscoverCard(item: item, distance: model.distance(to: item), isSaved: savedIDs.contains(item.id),
                             photoHeight: 130, onOpen: { openedItem = item }, onToggleSave: { toggleSave(item) })
            }
        }
    }

    // MARK: Search

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isSearching && model.searchResults.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            } else if model.searchResults.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "No results",
                               message: "Try another name, or something like “ramen” or “rooftop bar”.")
            } else {
                placeList(model.searchResults)
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func unavailable(_ category: DiscoverCategory, _ error: Error) -> some View {
        if case APIError.missingKey = error {
            NoticeBanner(symbol: "key.fill",
                         message: "Add a free Ticketmaster key in Settings to see concerts, sports and shows during your trip.",
                         actionTitle: "Open Settings") { app.isPresentingSettings = true }
        } else {
            NoticeBanner(symbol: "wifi.exclamationmark", message: error.localizedDescription, actionTitle: "Try Again") {
                Task { await model.load(category, force: true) }
            }
        }
    }

    /// Quick-save from a card's + button: adds as an unscheduled idea, or removes it.
    private func toggleSave(_ item: DiscoverItem) {
        if let existing = (trip.planItems ?? []).first(where: { $0.sourceID == item.id }) {
            context.delete(existing)
        } else {
            let plan = PlanItem.from(item, trip: trip)
            context.insert(plan)
            plan.trip = trip
        }
        try? context.save()
    }
}

extension PlanItem {
    /// A plan item seeded from a discover result. Events get their real start time.
    static func from(_ item: DiscoverItem, trip: Trip) -> PlanItem {
        let plan = PlanItem(title: item.title, category: item.category,
                            start: item.eventDate ?? trip.startDate,
                            durationMinutes: item.category.defaultDurationMinutes)
        plan.isScheduled = item.eventDate != nil
        plan.latitude = item.coordinate?.latitude
        plan.longitude = item.coordinate?.longitude
        plan.address = item.address
        plan.imageURLString = item.imageURL?.absoluteString
        plan.externalURLString = item.externalURL?.absoluteString
        plan.sourceID = item.id
        if let google = item.google {
            plan.openingHours = google.hours
            plan.hoursCheckedAt = .now
        }
        return plan
    }
}

private extension View {
    /// On iPhone, lets a card row run past the side gutter to the screen edge. Anywhere wider (Mac,
    /// iPad, a full-screen window), the page is a centered column, so the row stays clipped to it
    /// instead of spilling out past the hero and section headers.
    @ViewBuilder func bleedsToScreenEdge() -> some View {
        #if os(iOS)
        modifier(CompactScrollClip())
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct CompactScrollClip: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        content.scrollClipDisabled(sizeClass == .compact)
    }
}
#endif
