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

/// Garments floating on one shared backdrop, like a flat-lay in a magazine.
struct OutfitCollageView: View {
    var tiles: [CollageTile]
    var height: CGFloat = 340
    var showsBackdrop = true

    private func tile(_ slot: Slot) -> CollageTile? { tiles.first { $0.slot == slot } }

    var body: some View {
        let left = [tile(.outerwear), tile(.top)].compactMap { $0 }
        let right = [tile(.bottom)].compactMap { $0 }
        let small = [tile(.shoes), tile(.accessory)].compactMap { $0 }

        HStack(spacing: 4) {
            VStack(spacing: 4) {
                ForEach(left) { PieceView(tile: $0) }
            }
            VStack(spacing: 4) {
                ForEach(right) { PieceView(tile: $0).frame(maxHeight: .infinity) }
                if !small.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(small) { PieceView(tile: $0) }
                    }
                    .frame(maxHeight: height * 0.32)
                }
            }
        }
        .padding(height > 200 ? 16 : 6)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(showsBackdrop ? Theme.canvas : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tiles.map(\.label).joined(separator: ", "))
    }

    struct PieceView: View {
        var tile: CollageTile

        var body: some View {
            ZStack(alignment: .topLeading) {
                GarmentImageView(fileName: tile.imageFile, category: tile.category, color: tile.color, maxPixels: 500, showsCanvas: false)
                    .opacity(tile.missing == nil ? 1 : 0.4)
                    .shadow(color: .black.opacity(tile.missing == nil ? 0.12 : 0), radius: 8, y: 6)
                if tile.missing != nil {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .foregroundStyle(Theme.accent)
                    Text("MISSING")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
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
    /// Small label on the photo, e.g. "Look 01".
    var badge: String?
    var onWear: (() -> Void)?
    var onFavorite: (() -> Void)?
    var onSwap: ((Slot) -> Void)?
    var onAddMissing: ((HypotheticalItem) -> Void)?

    private var hasMissing: Bool { tiles.contains { $0.missing != nil } }
    private var swappableSlots: [Slot] { tiles.filter { $0.missing == nil }.map(\.slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OutfitCollageView(tiles: tiles)
                .overlay(alignment: .topLeading) {
                    if let badge {
                        EyebrowText(badge, color: Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(14)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isWorn {
                        Label("Wearing today", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.ink, in: Capsule())
                            .foregroundStyle(Theme.paper)
                            .padding(14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if let subtitle { EyebrowText(subtitle) }
                    Text(title)
                        .font(Theme.serif(.title2))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reasoning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if hasMissing {
                    ForEach(tiles.compactMap(\.missing)) { item in
                        missingRow(item)
                    }
                }

                actions
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
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

    private func missingRow(_ item: HypotheticalItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.dashed")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Missing: \(item.title)").font(.subheadline.weight(.semibold))
                Text([item.cut, item.material, Formality.label(item.formality).lowercased()].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let onAddMissing {
                Button("Add to list") { onAddMissing(item) }
                    .buttonStyle(.secondary)
            }
        }
        .padding(12)
        .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let onWear {
                Button(action: onWear) {
                    Label(isWorn ? "Wearing today" : "I'm wearing this", systemImage: isWorn ? "checkmark" : "figure.walk")
                }
                .buttonStyle(.primary)
                .disabled(isWorn || hasMissing)
                .accessibilityIdentifier("outfit.wear")
            } else {
                Spacer()
            }
            if let onFavorite {
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Theme.accent : Theme.ink)
                        .symbolEffect(.bounce, value: isFavorite)
                }
                .buttonStyle(.icon)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            if let onSwap, !swappableSlots.isEmpty {
                Menu {
                    ForEach(swappableSlots) { slot in
                        Button("Swap \(slot.displayName.lowercased())") { onSwap(slot) }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 46, height: 46)
                        .background(Circle().stroke(Theme.ink.opacity(0.15), lineWidth: 1))
                }
                .accessibilityLabel("Swap one piece")
            }
        }
    }
}

/// Slim weather strip: icon, temperature, place, rain and wind.
struct WeatherCardView: View {
    var snapshot: WeatherSnapshot?
    var isStale: Bool
    var isLoading: Bool
    var attribution: WeatherAttributionInfo?

    var body: some View {
        HStack(spacing: 14) {
            if let snapshot {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.title2)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(snapshot.temperatureC.rounded()))°")
                            .font(Theme.serif(.title2, weight: .bold))
                        Text("feels \(Int(snapshot.feelsLikeC.rounded()))°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(isStale ? "\(snapshot.locationName) · offline" : snapshot.locationName)
                        .font(.caption)
                        .foregroundStyle(isStale ? Theme.accent : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 14) {
                    Label("\(Int((snapshot.precipitationChance * 100).rounded()))%", systemImage: "umbrella")
                    Label("\(Int(snapshot.windKph.rounded()))", systemImage: "wind")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.ink)
                .labelStyle(.titleAndIcon)
            } else if isLoading {
                SkeletonBlock(height: 40)
            } else {
                Label("Weather unavailable", systemImage: "cloud.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline))
        .overlay(alignment: .bottomTrailing) {
            if let attribution {
                Link("\u{F8FF} \(attribution.serviceName)", destination: attribution.legalPageURL)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 12)
                    .padding(.bottom, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let snapshot else { return "Weather unavailable" }
        return "\(snapshot.locationName): \(Int(snapshot.temperatureC.rounded())) degrees, feels like \(Int(snapshot.feelsLikeC.rounded())), \(snapshot.conditionDescription), \(Int(snapshot.precipitationChance * 100)) percent chance of rain, wind \(Int(snapshot.windKph)) kilometers per hour"
    }
}
