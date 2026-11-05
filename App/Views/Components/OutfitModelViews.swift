import OutfitEngine
import SwiftUI

enum OutfitModelMode {
    /// Collage only.
    case off
    /// Show the model photo when one was made before; never start a new render.
    case cachedOnly
    /// Dress the model as soon as the outfit appears.
    case auto
}

/// The picture of an outfit: the house model wearing it (with the pieces beside it), or the collage of pieces.
struct OutfitVisual: View {
    @Environment(AppServices.self) private var services
    @AppStorage(OutfitModelSettings.enabledKey) private var showsModel = true
    var tiles: [CollageTile]
    var mode: OutfitModelMode

    private static let height: CGFloat = 380

    var body: some View {
        let store = services.outfitModels
        let key = OutfitModelStore.key(for: tiles)
        let enabled = mode != .off && showsModel && store.isAvailable
        Group {
            if enabled, let key, let url = store.imageURL(for: key) {
                onModel(LocalPhoto(url: url))
                    .contextMenu {
                        Button { store.request(tiles, fresh: true) } label: {
                            Label("Dress the model again", systemImage: "arrow.clockwise")
                        }
                    }
            } else if enabled, mode == .auto, let key, let status = store.status(for: key) {
                switch status {
                case .waiting, .rendering:
                    onModel(RenderingPlaceholder())
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        OutfitCollageView(tiles: tiles)
                        HStack {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Try again") { store.request(tiles) }
                                .font(.caption.bold())
                        }
                    }
                }
            } else {
                OutfitCollageView(tiles: tiles)
            }
        }
        .task(id: key) {
            if enabled, mode == .auto { store.request(tiles) }
        }
    }

    /// Model photo on the left, the pieces stacked on the right.
    private func onModel(_ photo: some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            photo
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(spacing: 6) {
                ForEach(tiles) { tile in
                    OutfitCollageView.TileView(tile: tile)
                        .frame(width: 68, height: min(68, (Self.height - 6 * CGFloat(tiles.count - 1)) / CGFloat(max(tiles.count, 1))))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Model wearing " + tiles.map(\.label).joined(separator: ", "))
    }
}

/// A photo file from the phone, loaded off the main thread.
private struct LocalPhoto: View {
    var url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.93)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task(id: url) { image = await ThumbnailLoader.image(at: url, maxPixels: 1200) }
    }
}

private struct RenderingPlaceholder: View {
    var body: some View {
        ZStack {
            Color(white: 0.93)
            VStack(spacing: 10) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                ProgressView()
                Text("Dressing the model…")
                    .font(.subheadline.weight(.semibold))
                Text("About half a minute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
