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
            VStack(alignment: .leading, spacing: 20) {
                categories
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
            .padding(.bottom, 32)
            #if os(macOS)
            .padding(.top, 12)
            #endif
            .readableWidth(1100)
        }
        .background(Color.appBackground)
        .navigationTitle(trip.displayName)
        .largeTitle()
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

    // MARK: Category circles

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                CategoryCircle(title: "For You", symbol: "sparkles", color: .accentColor, isSelected: selectedCategory == nil) {
                    withAnimation(.snappy) { selectedCategory = nil }
                }
                ForEach(DiscoverCategory.browsable) { c in
                    CategoryCircle(title: c.title, symbol: c.symbol, color: c.color, isSelected: selectedCategory == c) {
                        withAnimation(.snappy) { selectedCategory = c }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter - 4)
            .padding(.vertical, 4)
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

    /// Apple Maps results have no photos, so they use list rows instead of photo cards.
    private func usesPhotos(_ category: DiscoverCategory) -> Bool { category == .sights || category == .events }

    private var featuredID: String? { model.state(for: .sights).items.first(where: { $0.imageURL != nil })?.id }

    private func section(_ category: DiscoverCategory) -> some View {
        let state = model.state(for: category)
        let items = state.items.filter { $0.id != featuredID }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(category.headline) {
                if !state.items.isEmpty {
                    SeeAllButton { withAnimation(.snappy) { selectedCategory = category } }
                }
            }
            if let error = state.error {
                unavailable(category, error)
            } else if usesPhotos(category) {
                ScrollView(.horizontal, showsIndicators: false) {
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
                .scrollClipDisabled()
            } else if items.isEmpty {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Color.cardBackground).frame(height: 180)
            } else {
                placeList(Array(items.prefix(4)))
            }
        }
        .task { await model.load(category) }
    }

    private func placeList(_ items: [DiscoverItem]) -> some View {
        PlaceList(items: items, distance: { model.distance(to: $0) }, isSaved: { savedIDs.contains($0.id) },
                  onOpen: { openedItem = $0 }, onToggleSave: { toggleSave($0) })
    }

    // MARK: Single category

    private let photoColumns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]

    private func categoryPage(_ category: DiscoverCategory) -> some View {
        let state = model.state(for: category)
        return VStack(alignment: .leading, spacing: 14) {
            Picker("View", selection: $showMap) {
                Text("List").tag(false)
                Text("Map").tag(true)
            }
            .pickerStyle(.segmented)

            if let error = state.error {
                unavailable(category, error)
            } else if state.isLoading {
                LazyVGrid(columns: photoColumns, spacing: 12) { ForEach(0..<6, id: \.self) { _ in PlaceholderCard() } }
            } else if state.items.isEmpty, case .loaded = state {
                EmptyStateView(symbol: category.symbol, title: "Nothing found",
                               message: "No \(category.title.lowercased()) found near \(trip.destinationName).")
            } else if showMap {
                DiscoverMapView(items: state.items, onOpen: { openedItem = $0 })
                    .frame(height: 520)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            } else if usesPhotos(category) {
                LazyVGrid(columns: photoColumns, spacing: 12) {
                    ForEach(state.items) { item in
                        DiscoverCard(item: item, distance: model.distance(to: item), isSaved: savedIDs.contains(item.id),
                                     onOpen: { openedItem = item }, onToggleSave: { toggleSave(item) })
                    }
                }
            } else {
                placeList(state.items)
            }
        }
        .task(id: category) { await model.load(category) }
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
        return plan
    }
}
