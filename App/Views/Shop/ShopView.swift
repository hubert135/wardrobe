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
    @State private var showAllRecipes = false

    private var openItems: [WishlistItem] { wishlist.filter { $0.status == .open } }

    var body: some View {
        List {
            if model.hasStylebook {
                let progress = model.recipeProgress()
                Section {
                    ForEach(progress.prefix(showAllRecipes ? progress.count : 5)) { item in
                        NavigationLink {
                            RecipeDetailView(model: model, progress: item) { safariURL = $0 }
                        } label: {
                            RecipeRow(progress: item)
                        }
                    }
                    if progress.count > 5 {
                        Button(showAllRecipes ? "Show fewer" : "Show all \(progress.count) recipes") { showAllRecipes.toggle() }
                    }
                } header: {
                    Text("From your style guide")
                } footer: {
                    Text("Recipes from your e-book, closest to complete first. Open one to see products for the pieces you are missing.")
                }
            }

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

private struct RecipeRow: View {
    var progress: ShopViewModel.RecipeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recipe \(progress.recipe.id)").font(.caption.bold()).foregroundStyle(Theme.accent)
                Spacer()
                Text(progress.missingIndices.isEmpty ? "You have it all" : "You own \(progress.ownedCount) of \(progress.requiredIndices.count)")
                    .font(.caption)
                    .foregroundStyle(progress.missingIndices.isEmpty ? Color.green : Color.secondary)
            }
            Text(progress.recipe.title.capitalized).font(.subheadline.weight(.semibold)).lineLimit(2)
            if !progress.missingIndices.isEmpty {
                Text("Missing: " + progress.missingIndices.map { progress.recipe.pieces[$0].displayName.lowercased() }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One recipe: what you own, what is missing, and the e-book products in three budgets.
struct RecipeDetailView: View {
    @Bindable var model: ShopViewModel
    var progress: ShopViewModel.RecipeProgress
    var open: (URL) -> Void
    @State private var budget: StylebookBudget = .standard
    @State private var showsDescription = false

    private var recipe: StylebookRecipeDTO { progress.recipe }
    private var products: [StylebookProductDTO] { recipe.budgets[budget.rawValue]?.items ?? [] }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECIPE \(recipe.id)").font(.caption.bold()).foregroundStyle(Theme.accent)
                    Text(recipe.title.capitalized).font(.title3.bold())
                    Text(recipe.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                DisclosureGroup("From the e-book", isExpanded: $showsDescription) {
                    Text(recipe.description).font(.footnote)
                }
            }

            Section("Your pieces") {
                ForEach(progress.requiredIndices, id: \.self) { index in
                    pieceRow(index)
                }
                if !progress.missingIndices.isEmpty {
                    Button {
                        model.addMissingToWishlist(progress)
                    } label: {
                        Label("Add missing pieces to shopping list", systemImage: "cart.badge.plus")
                    }
                }
            }

            Section {
                Picker("Budget", selection: $budget) {
                    ForEach(StylebookBudget.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                ForEach(Array(products.enumerated()), id: \.offset) { _, product in
                    ProductRow(product: product, isMissing: product.pieceIndex.map { progress.missingIndices.contains($0) } ?? false, open: open)
                }
            } header: {
                Text("Products from the e-book")
            } footer: {
                if let total = recipe.budgets[budget.rawValue]?.total {
                    Text("Whole outfit in this budget: \(total) zł. Prices are from the e-book; check the shop for the current price.")
                }
            }
        }
        .navigationTitle("Recipe \(recipe.id)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Shop", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.message ?? "") }
    }

    @ViewBuilder
    private func pieceRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            if let garment = progress.owned[index] {
                GarmentImageView(garment: garment, maxPixels: 120)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading) {
                    Text(garment.displayName)
                    Text(recipe.pieces[index].displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "plus.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text(recipe.pieces[index].displayName)
                    Text("Missing").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

private struct ProductRow: View {
    var product: StylebookProductDTO
    var isMissing: Bool
    var open: (URL) -> Void

    var body: some View {
        Button {
            if let url = product.url.flatMap(URL.init(string:)) { open(url) }
        } label: {
            HStack(spacing: 12) {
                StylebookProductImage(name: product.image, maxPixels: 200)
                    .frame(width: 48, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(product.label.capitalized).font(.subheadline.weight(.semibold))
                        if isMissing {
                            Text("YOU NEED THIS")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text(product.shop ?? "Shop unknown").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(product.price) zł").font(.subheadline.monospacedDigit())
                if product.url != nil {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(product.url == nil)
        .accessibilityLabel("\(product.label), \(product.shop ?? ""), \(product.price) złoty\(isMissing ? ", you need this" : "")")
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
                Text("+\(gap.unlockedOutfitCount)").font(.title3.bold()).foregroundStyle(Theme.accent)
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
                        Text("+\(gap.unlockedOutfitCount) new outfits").font(.title2.bold()).foregroundStyle(Theme.accent)
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
