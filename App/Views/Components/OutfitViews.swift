import OutfitEngine
import SwiftUI

/// One tile of an outfit collage: an owned garment or a missing piece.
struct CollageTile: Identifiable, Hashable {
    var slot: Slot
    var imageFile: String?
    var category: GarmentCategory
    var color: String
    var label: String
    var missing: HypotheticalItem?

    var id: Slot { slot }
}

enum OutfitPresenter {
    /// Resolves engine pieces to tiles using the user's garments (for image files and names).
    static func tiles(for outfit: EngineOutfit, garments: [UUID: Garment]) -> [CollageTile] {
        outfit.pieces.keys.sorted().compactMap { slot in
            guard let piece = outfit.pieces[slot] else { return nil }
            if let missing = outfit.missing[slot] {
                return CollageTile(slot: slot, imageFile: nil, category: missing.category, color: missing.color, label: missing.title, missing: missing)
            }
            let garment = garments[piece.id]
            return CollageTile(
                slot: slot, imageFile: garment?.displayImageFile, category: piece.category,
                color: piece.primaryColor, label: garment?.displayName ?? piece.shortLabel, missing: nil
            )
        }
    }

    static func tiles(for outfit: Outfit) -> [CollageTile] {
        outfit.orderedSlots.compactMap { slot in
            if let missing = slot.missingItem {
                return CollageTile(slot: slot.slot, imageFile: nil, category: missing.category, color: missing.color, label: missing.title, missing: missing)
            }
            guard let garment = slot.garment else { return nil }
            return CollageTile(
                slot: slot.slot, imageFile: garment.displayImageFile, category: garment.category,
                color: garment.primaryColor, label: garment.displayName, missing: nil
            )
        }
    }
}

struct OutfitCollageView: View {
    var tiles: [CollageTile]
    var height: CGFloat = 250

    private func tile(_ slot: Slot) -> CollageTile? { tiles.first { $0.slot == slot } }

    var body: some View {
        let left = [tile(.outerwear), tile(.top)].compactMap { $0 }
        let right = [tile(.bottom)].compactMap { $0 }
        let small = [tile(.shoes), tile(.accessory)].compactMap { $0 }

        HStack(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(left) { TileView(tile: $0) }
            }
            VStack(spacing: 8) {
                ForEach(right) { TileView(tile: $0) }
                if !small.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(small) { TileView(tile: $0) }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tiles.map(\.label).joined(separator: ", "))
    }

    struct TileView: View {
        var tile: CollageTile

        var body: some View {
            ZStack(alignment: .topLeading) {
                GarmentImageView(fileName: tile.imageFile, category: tile.category, color: tile.color, maxPixels: 500)
                    .opacity(tile.missing == nil ? 1 : 0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if tile.missing != nil {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .foregroundStyle(Theme.accent)
                    Text("Missing")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
        }
    }
}

struct OutfitCard: View {
    var title: String
    var reasoning: String
    var tiles: [CollageTile]
    var isFavorite: Bool
    var isWorn: Bool = false
    var subtitle: String?
    var onWear: (() -> Void)?
    var onFavorite: (() -> Void)?
    var onSwap: ((Slot) -> Void)?
    var onAddMissing: ((HypotheticalItem) -> Void)?

    private var hasMissing: Bool { tiles.contains { $0.missing != nil } }
    private var swappableSlots: [Slot] { tiles.filter { $0.missing == nil }.map(\.slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OutfitCollageView(tiles: tiles)

            VStack(alignment: .leading, spacing: 4) {
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                Text(reasoning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasMissing {
                ForEach(tiles.compactMap(\.missing)) { item in
                    HStack {
                        Image(systemName: "plus.circle.dashed")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text("Missing: \(item.title)").font(.subheadline.bold())
                            Text([item.cut, item.material, Formality.label(item.formality).lowercased()].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let onAddMissing {
                            Button("Add to shopping list") { onAddMissing(item) }
                                .font(.caption.bold())
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                if let onWear {
                    Button(action: onWear) {
                        Label(isWorn ? "Wearing today" : "I'm wearing this", systemImage: isWorn ? "checkmark.circle.fill" : "figure.walk")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorn || hasMissing)
                    .accessibilityIdentifier("outfit.wear")
                }
                if let onFavorite {
                    Button(action: onFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundStyle(isFavorite ? .red : .secondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                }
                if let onSwap, !swappableSlots.isEmpty {
                    Menu {
                        ForEach(swappableSlots) { slot in
                            Button("Swap \(slot.displayName.lowercased())") { onSwap(slot) }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Swap one piece")
                }
            }
        }
        .padding()
        .card()
        .contextMenu {
            if let onSwap {
                ForEach(swappableSlots) { slot in
                    Button { onSwap(slot) } label: { Label("Swap \(slot.displayName.lowercased())", systemImage: "arrow.triangle.2.circlepath") }
                }
            }
            if let onFavorite {
                Button { onFavorite() } label: { Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart") }
            }
        }
    }
}

struct WeatherCardView: View {
    var snapshot: WeatherSnapshot?
    var isStale: Bool
    var isLoading: Bool
    var attribution: WeatherAttributionInfo?

    var body: some View {
        HStack(spacing: 16) {
            if let snapshot {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 36))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(snapshot.temperatureC.rounded()))°").font(.title.bold())
                        Text("feels \(Int(snapshot.feelsLikeC.rounded()))°").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(snapshot.locationName).font(.subheadline)
                    if isStale {
                        Text("Offline · updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label("\(Int((snapshot.precipitationChance * 100).rounded()))%", systemImage: "umbrella")
                    Label("\(Int(snapshot.windKph.rounded())) km/h", systemImage: "wind")
                    if let attribution {
                        Link(" \(attribution.serviceName)", destination: attribution.legalPageURL)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
            } else if isLoading {
                SkeletonBlock(height: 52)
            } else {
                Label("Weather unavailable", systemImage: "cloud.slash")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let snapshot else { return "Weather unavailable" }
        return "\(snapshot.locationName): \(Int(snapshot.temperatureC.rounded())) degrees, feels like \(Int(snapshot.feelsLikeC.rounded())), \(snapshot.conditionDescription), \(Int(snapshot.precipitationChance * 100)) percent chance of rain, wind \(Int(snapshot.windKph)) kilometers per hour"
    }
}
