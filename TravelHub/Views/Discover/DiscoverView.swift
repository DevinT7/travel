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
    @State private var showMap = false

    init(trip: Trip) {
        self.trip = trip
        _model = State(initialValue: DiscoverModel(trip: trip))
    }

    private var savedIDs: Set<String> { Set((trip.planItems ?? []).compactMap(\.sourceID)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                chips
                Group {
                    if !query.isEmpty {
                        searchResults
                    } else if let selectedCategory {
                        categoryPage(selectedCategory)
                    } else {
                        allCategories
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .padding(.vertical, 12)
            .readableWidth(1200)
        }
        .background(Color.appBackground)
        .navigationTitle("Discover \(trip.destinationName)")
        .inlineTitle()
        .searchable(text: $query, prompt: "Search places in \(trip.destinationName)")
        .onSubmit(of: .search) { Task { await model.search(query) } }
        .task(id: query) {
            // Debounced type-ahead search.
            guard !query.isEmpty else { model.clearSearch(); return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .sheet(item: $openedItem) { item in
            DiscoverDetailView(item: item, trip: trip, distance: model.distance(to: item))
        }
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "For You", symbol: "sparkles", isSelected: selectedCategory == nil) {
                    withAnimation(.snappy) { selectedCategory = nil }
                }
                ForEach(DiscoverCategory.browsable) { c in
                    Chip(title: c.title, symbol: c.symbol, tint: c.color, isSelected: selectedCategory == c) {
                        withAnimation(.snappy) { selectedCategory = c }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }

    // MARK: "For You": a featured sight then a carousel per category

    private var allCategories: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let featured = model.state(for: .sights).items.first(where: { $0.imageURL != nil }) {
                FeaturedCard(item: featured, isSaved: savedIDs.contains(featured.id)) { openedItem = featured }
            }
            ForEach(DiscoverCategory.browsable) { category in
                carousel(category)
            }
        }
    }

    /// Apple Maps results have no photos, so they use dense rows instead of photo cards.
    private func usesPhotos(_ category: DiscoverCategory) -> Bool { category == .sights || category == .events }

    private var featuredID: String? { model.state(for: .sights).items.first(where: { $0.imageURL != nil })?.id }

    private func carousel(_ category: DiscoverCategory) -> some View {
        let state = model.state(for: category)
        let items = Array(state.items.filter { $0.id != featuredID }.prefix(12))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(category.title) {
                if !state.items.isEmpty {
                    Button("See all") { withAnimation(.snappy) { selectedCategory = category } }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if let error = state.error {
                        unavailable(category, error).frame(width: 320)
                    } else if usesPhotos(category) {
                        LazyHStack(spacing: 14) {
                            if items.isEmpty {
                                ForEach(0..<4, id: \.self) { _ in PlaceholderCard().frame(width: 250) }
                            }
                            ForEach(items) { item in
                                DiscoverCard(item: item, distance: model.distance(to: item), isSaved: savedIDs.contains(item.id),
                                             onOpen: { openedItem = item }, onToggleSave: { toggleSave(item) })
                                    .frame(width: 250)
                            }
                        }
                    } else {
                        LazyHGrid(rows: Array(repeating: GridItem(.fixed(70), spacing: 10), count: 3), spacing: 12) {
                            if items.isEmpty {
                                ForEach(0..<6, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.cardBackground).frame(width: 300)
                                }
                            }
                            ForEach(items) { item in
                                CompactPlaceRow(item: item, distance: model.distance(to: item), isSaved: savedIDs.contains(item.id),
                                                onOpen: { openedItem = item }, onToggleSave: { toggleSave(item) })
                                    .frame(width: 300)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .task { await model.load(category) }
    }

    // MARK: Single category

    private let gridColumns = [GridItem(.adaptive(minimum: 220), spacing: 14, alignment: .top)]

    private func categoryPage(_ category: DiscoverCategory) -> some View {
        let state = model.state(for: category)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(category.title).font(.title2.bold())
                Spacer()
                Picker("View", selection: $showMap) {
                    Image(systemName: "square.grid.2x2").tag(false).accessibilityLabel("Grid")
                    Image(systemName: "map").tag(true).accessibilityLabel("Map")
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            if let error = state.error {
                unavailable(category, error)
            } else if state.isLoading {
                LazyVGrid(columns: gridColumns, spacing: 14) { ForEach(0..<6, id: \.self) { _ in PlaceholderCard() } }
            } else if state.items.isEmpty, case .loaded = state {
                EmptyStateView(symbol: category.symbol, title: "Nothing found",
                               message: "No \(category.title.lowercased()) found near \(trip.destinationName).")
            } else if showMap {
                DiscoverMapView(items: state.items, onOpen: { openedItem = $0 })
                    .frame(height: 520)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            } else {
                itemGrid(state.items, photos: usesPhotos(category))
            }
        }
        .task(id: category) { await model.load(category) }
    }

    @ViewBuilder
    private func itemGrid(_ items: [DiscoverItem], photos: Bool) -> some View {
        if photos {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(items) { item in
                    DiscoverCard(item: item, distance: model.distance(to: item), isSaved: savedIDs.contains(item.id),
                                 onOpen: { openedItem = item }, onToggleSave: { toggleSave(item) })
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 10) {
                ForEach(items) { item in
                    CompactPlaceRow(item: item, distance: model.distance(to: item), isSaved: savedIDs.contains(item.id),
                                    onOpen: { openedItem = item }, onToggleSave: { toggleSave(item) })
                }
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
                itemGrid(model.searchResults, photos: false)
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
        return plan
    }
}
