import OutfitEngine
import SwiftData
import SwiftUI

struct ClosetFilter: Equatable {
    var category: GarmentCategory?
    var color: String?
    var season: Season?
    var formality: Int?
    var status: GarmentStatus?

    var isActive: Bool { self != ClosetFilter() }

    func matches(_ garment: Garment, searchText: String) -> Bool {
        if let category, garment.category != category { return false }
        if let color, garment.primaryColor != color, garment.secondaryColor != color { return false }
        if let season, !garment.seasons.isEmpty, !garment.seasons.contains(season) { return false }
        if let formality, garment.formality != formality { return false }
        if let status {
            if garment.status != status { return false }
        } else if garment.status == .archived {
            return false
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return [garment.name, garment.brand, garment.subcategory, garment.primaryColor, garment.category.displayName, garment.material]
            .contains { $0.lowercased().contains(query) }
    }
}

struct ClosetView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Garment.createdAt, order: .reverse) private var garments: [Garment]
    @State private var searchText = ""
    @State private var filter = ClosetFilter()
    @State private var isFilterPresented = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    private var pending: [Garment] { garments.filter { $0.status == .pendingReview } }
    private var visible: [Garment] {
        garments.filter { filter.matches($0, searchText: searchText) && (filter.status != nil || $0.status != .pendingReview) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if garments.isEmpty {
                    EmptyStateView(
                        symbol: "tshirt",
                        title: "Your closet is empty",
                        message: "Snap a few photos of your clothes or import an order. Wardrobe fills in the details for you.",
                        actionTitle: "Add garments",
                        action: { router.openAdd() }
                    )
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        if !pending.isEmpty && filter.status == nil && searchText.isEmpty {
                            section(title: "Needs review", subtitle: "Check these details before they're used in outfits.", items: pending)
                        }
                        section(title: filter.isActive ? "Filtered" : "All garments", subtitle: "\(visible.count) items", items: visible)
                    }
                    .padding()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Closet")
            .navigationDestination(for: UUID.self) { id in
                GarmentDetailView(garmentID: id)
            }
            .searchable(text: $searchText, prompt: "Search name, brand, color")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isFilterPresented = true } label: {
                        Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.openAdd() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add garment")
                        .accessibilityIdentifier("closet.add")
                }
            }
            .sheet(isPresented: $isFilterPresented) {
                ClosetFilterSheet(filter: $filter)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func section(title: String, subtitle: String, items: [Garment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.bold())
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("Nothing matches these filters.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { garment in
                    NavigationLink(value: garment.id) {
                        GarmentTile(garment: garment)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct GarmentTile: View {
    @Environment(AppServices.self) private var services
    var garment: Garment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GarmentImageView(garment: garment, maxPixels: 300)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if services.productPhotos.isWorking(on: garment.id) {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Store photo").font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                        .accessibilityLabel("Creating store photo")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if garment.status == .pendingReview {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .padding(6)
                    }
                }
            Text(garment.displayName)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(garment.displayName)\(garment.status == .pendingReview ? ", needs review" : "")")
    }
}

struct ClosetFilterSheet: View {
    @Binding var filter: ClosetFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $filter.category) {
                    Text("Any").tag(GarmentCategory?.none)
                    ForEach(GarmentCategory.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Color", selection: $filter.color) {
                    Text("Any").tag(String?.none)
                    ForEach(ColorPalette.all) { Text($0.displayName).tag(Optional($0.name)) }
                }
                Picker("Season", selection: $filter.season) {
                    Text("Any").tag(Season?.none)
                    ForEach(Season.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Formality", selection: $filter.formality) {
                    Text("Any").tag(Int?.none)
                    ForEach(1...5, id: \.self) { Text("\($0) · \(Formality.label($0))").tag(Optional($0)) }
                }
                Picker("Status", selection: $filter.status) {
                    Text("Active").tag(GarmentStatus?.none)
                    ForEach(GarmentStatus.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = ClosetFilter() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
