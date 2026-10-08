import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives order confirmation text or a screenshot from the share sheet and hands it to the app.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task { await model.receive(extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State: Equatable { case working, saved, failed(String) }
    @Published var state: State = .working

    func receive(_ items: [NSExtensionItem]) async {
        let providers = items.flatMap { $0.attachments ?? [] }
        do {
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
                let data = try await loadImageData(provider)
                try PendingImportStore.shared.save(imageData: data)
            } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
                let text = try await loadText(provider)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShareError.empty }
                try PendingImportStore.shared.save(text: String(text.prefix(50_000)))
            } else {
                throw ShareError.unsupported
            }
            state = .saved
        } catch {
            state = .failed("This content can't be imported. Share the text of an order email or a screenshot.")
        }
    }

    private func loadText(_ provider: NSItemProvider) async throws -> String {
        let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        if let text = item as? String { return text }
        if let data = item as? Data, let text = String(data: data, encoding: .utf8) { return text }
        throw ShareError.unsupported
    }

    private func loadImageData(_ provider: NSItemProvider) async throws -> Data {
        let item = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        let image: UIImage?
        switch item {
        case let url as URL: image = UIImage(contentsOfFile: url.path)
        case let data as Data: image = UIImage(data: data)
        case let uiImage as UIImage: image = uiImage
        default: image = nil
        }
        guard let jpeg = image?.jpegData(compressionQuality: 0.8) else { throw ShareError.unsupported }
        return jpeg
    }

    enum ShareError: Error { case unsupported, empty }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch model.state {
                case .working:
                    ProgressView()
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Saved for import")
                        .font(.title3.bold())
                    Text("Open Wardrobe to review the items from this order.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text(message)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Add to Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }
}
