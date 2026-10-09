import OutfitEngine
import SafariServices
import SwiftData
import SwiftUI

struct ShopView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ShopViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { ShopContent(model: model) } else { ProgressView() }
            }
            .navigationTitle("Shop")
        }
        .task {
            if model == nil { model = ShopViewModel(services: services) }
            await model?.load()
        }
    }
}

private struct ShopContent: View {
    @Bindable var model: ShopViewModel
    @Query(sort: \WishlistItem.createdAt, order: .reverse) private var wishlist: [WishlistItem]
    @State private var selectedGap: Gap?
    @State private var safariURL: URL?
    @State private var boughtItem: WishlistItem?

    private var openItems: [WishlistItem] { wishlist.filter { $0.status == .open } }

    var body: some View {
        List {
            Section {
                budgetRow
                if !model.favoriteBrands.isEmpty {
                    Picker("Brand", selection: $model.brand) {
                        Text("Any brand").tag(String?.none)
                        ForEach(model.favoriteBrands, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }
            } header: {
                Text("Filters")
            }

            Section {
                if model.isLoading && !model.hasLoaded {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 44) }
                } else if model.gaps.isEmpty {
                    Text(model.closetCount < 3
                         ? "Add a few garments first. Gaps are calculated from real combinations with your closet."
                         : "No obvious gaps. Your closet already combines well.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.gaps.prefix(12)) { gap in
                        Button { selectedGap = gap } label: { GapRow(gap: gap, isSaved: model.isOnWishlist(gap)) }
                            .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Biggest impact")
            } footer: {
                Text("Counts are new outfits the piece would create with what you own, using the same rules as your daily suggestions.")
            }

            if !openItems.isEmpty {
                Section("Shopping list") {
                    ForEach(openItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(Color.garment(item.color)).frame(width: 12, height: 12)
                                Text(item.itemDescription).font(.headline)
                                Spacer()
                                Text("+\(item.unlockedOutfitCount)").font(.subheadline.bold()).foregroundStyle(Theme.accent)
                            }
                            HStack {
                                ForEach(model.links(for: item)) { link in
                                    Button(link.retailer) { safariURL = link.url }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Bought") { boughtItem = item }.tint(.green)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { model.delete(item) }
                        }
                        .contextMenu {
                            Button { boughtItem = item } label: { Label("Bought", systemImage: "checkmark") }
                            Button(role: .destructive) { model.delete(item) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .paperBackground()
        .refreshable { await model.load(force: true) }
        .task { await model.load() }
        .sheet(item: $selectedGap) { gap in
            GapDetailSheet(model: model, gap: gap) { safariURL = $0 }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: Binding(get: { safariURL.map(IdentifiedURL.init) }, set: { safariURL = $0?.url })) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        .confirmationDialog("Bought \(boughtItem?.itemDescription ?? "")?", isPresented: Binding(get: { boughtItem != nil }, set: { if !$0 { boughtItem = nil } }), titleVisibility: .visible) {
            Button("Add to closet") { if let item = boughtItem { model.markBought(item, addToCloset: true) } }
            Button("Just mark as bought") { if let item = boughtItem { model.markBought(item, addToCloset: false) } }
        }
        .alert("Shop", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.message ?? "") }
    }

    private var budgetRow: some View {
        HStack {
            Text("Max budget")
            Spacer()
            TextField("Any", value: $model.maxBudget, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(model.currencyCode).foregroundStyle(.secondary)
        }
    }
}

private struct GapRow: View {
    var gap: Gap
    var isSaved: Bool

    var body: some View {
        HStack(spacing: 12) {
            GarmentImageView(fileName: nil, category: gap.item.category, color: gap.item.color, maxPixels: 120)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(gap.item.title).font(.headline)
                Text(gap.reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("+\(gap.unlockedOutfitCount)").font(Theme.serif(.title2, weight: .bold)).foregroundStyle(Theme.accent)
                Text(isSaved ? "on list" : "outfits").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gap.item.title), unlocks \(gap.unlockedOutfitCount) new outfits. \(gap.reason)")
    }
}

private struct GapDetailSheet: View {
    @Bindable var model: ShopViewModel
    var gap: Gap
    var open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("+\(gap.unlockedOutfitCount) new outfits").font(Theme.serif(.title, weight: .bold)).foregroundStyle(Theme.accent)
                        Text(gap.reason).foregroundStyle(.secondary)
                    }
                    Button {
                        model.addToWishlist(gap)
                    } label: {
                        Label(model.isOnWishlist(gap) ? "On your shopping list" : "Add to shopping list", systemImage: model.isOnWishlist(gap) ? "checkmark" : "plus")
                    }
                    .disabled(model.isOnWishlist(gap))
                }
                let directions = model.directions(for: gap)
                if directions.isEmpty {
                    Section { Text("Nothing in this category fits your budget.").foregroundStyle(.secondary) }
                }
                ForEach(directions) { direction in
                    Section {
                        Text(direction.attributes)
                        HStack {
                            ForEach(model.links(for: direction)) { link in
                                Button(link.retailer) { open(link.url) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                            }
                        }
                    } header: {
                        Text("\(direction.tier.displayName) · \(priceText(direction))")
                    }
                }
                Section {
                    Text("Links open store searches built from these attributes. Wardrobe never guesses product pages.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(gap.item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func priceText(_ direction: PurchaseDirection) -> String {
        if direction.priceRange.lowerBound == 0 { return "up to \(direction.priceRange.upperBound.currency(direction.currencyCode))" }
        return "\(direction.priceRange.lowerBound.currency(direction.currencyCode))–\(direction.priceRange.upperBound.currency(direction.currencyCode))"
    }
}

struct IdentifiedURL: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
