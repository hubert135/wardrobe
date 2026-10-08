import Foundation
import Observation
import OutfitEngine
import SwiftData

/// Launch configuration from process arguments.
struct LaunchOptions {
    /// UI tests: in-memory store, offline API, mock weather, onboarding skipped, small seed closet.
    var isUITesting: Bool
    /// Debug: load the 25-garment sample closet when the closet is empty.
    var seedSampleCloset: Bool

    static let current: LaunchOptions = {
        let arguments = ProcessInfo.processInfo.arguments
        return LaunchOptions(isUITesting: arguments.contains("-uiTesting"), seedSampleCloset: arguments.contains("-seed"))
    }()
}

enum AppTab: Hashable {
    case today, closet, outfits, shop, profile
}

enum OutfitsSegment: String, CaseIterable, Identifiable {
    case favorites = "Favorites"
    case history = "History"
    case builder = "Builder"
    var id: String { rawValue }
}

/// Cross-tab navigation state.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var outfitsSegment: OutfitsSegment = .favorites
    /// Garment preselected in the builder ("Build outfits with this").
    var builderAnchorID: UUID?
    var isAddSheetPresented = false
    var addSheetInitialTab: AddTab = .photos
    /// Text or image shared from the Share Extension, waiting to be imported.
    var pendingImport: PendingImport?

    func buildOutfits(with garmentID: UUID) {
        builderAnchorID = garmentID
        outfitsSegment = .builder
        selectedTab = .outfits
    }

    func openAdd(_ tab: AddTab = .photos) {
        addSheetInitialTab = tab
        isAddSheetPresented = true
    }
}

/// Composition root. Everything is created here and passed down through the SwiftUI environment.
@MainActor
@Observable
final class AppServices {
    let options: LaunchOptions
    let modelContainer: ModelContainer
    let imageStore: ImageStore
    let repository: WardrobeRepository
    let tokens: SessionTokenStore
    let api: WardrobeAPI
    let auth: AuthService
    let location: LocationService
    let weather: WeatherManager
    let backgroundRemover: BackgroundRemoving
    let recognizer: GarmentRecognizing
    let purchaseImporter: PurchaseImporter
    let imageDownloader = ProductImageDownloader()
    let outfits: OutfitService
    let shop: ShopService
    let notifications = NotificationService()
    let router = AppRouter()

    init(options: LaunchOptions = .current) {
        self.options = options
        let container = ModelContainerFactory.make(inMemory: options.isUITesting)
        modelContainer = container
        let imageStore: ImageStore = options.isUITesting
            ? FileImageStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("UITestImages"))
            : FileImageStore()
        self.imageStore = imageStore
        repository = SwiftDataWardrobeRepository(context: container.mainContext, imageStore: imageStore)

        let tokens = SessionTokenStore()
        self.tokens = tokens
        let api: WardrobeAPI = options.isUITesting
            ? OfflineWardrobeAPI()
            : HTTPWardrobeAPI(baseURL: { ServerSettings.baseURL }, tokens: tokens)
        self.api = api
        let auth = AuthService(tokens: tokens, api: api)
        self.auth = auth

        let location = LocationService()
        self.location = location
        let providerName = Bundle.main.object(forInfoDictionaryKey: "WardrobeWeatherProvider") as? String
        let provider: WeatherProvider = (providerName == "weatherkit" && !options.isUITesting) ? WeatherKitProvider() : MockWeatherProvider()
        weather = WeatherManager(provider: provider, location: location)

        backgroundRemover = VisionBackgroundRemover()
        recognizer = AIGarmentRecognizer(api: api)
        purchaseImporter = AIOrderImporter(api: api)
        outfits = OutfitService(api: api, isAIEnabled: { [weak auth] in auth?.isSignedIn ?? false })
        shop = ShopService()

        prepareData()
    }

    private func prepareData() {
        let profile = repository.profile()
        if options.isUITesting {
            profile.onboardingCompleted = true
            #if DEBUG
            SeedData.seed(SeedData.uiTestCloset, into: repository, imageStore: imageStore)
            #endif
            repository.save()
            return
        }
        #if DEBUG
        if options.seedSampleCloset, repository.garments(includeArchived: true).isEmpty {
            SeedData.seed(SeedData.sampleCloset, into: repository, imageStore: imageStore)
            profile.onboardingCompleted = true
            repository.save()
        }
        #endif
    }

    /// Picks up anything the Share Extension left in the App Group container.
    func checkPendingImports() {
        guard router.pendingImport == nil, let next = PendingImportStore.shared.all().first else { return }
        router.pendingImport = next
        router.openAdd(.order)
    }

    var closetForEngine: [EngineGarment] {
        repository.garments(includeArchived: false).map(\.engineGarment)
    }
}
