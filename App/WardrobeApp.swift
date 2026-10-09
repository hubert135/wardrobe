import SwiftData
import SwiftUI

@main
struct WardrobeApp: App {
    @State private var services = AppServices()

    init() {
        Theme.applyNavigationAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .environment(services.router)
                .environment(services.auth)
        }
        .modelContainer(services.modelContainer)
    }
}

struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Group {
            if profile?.onboardingCompleted ?? false {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(colorScheme)
        .tint(Theme.accent)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            services.checkPendingImports()
            Task { await services.auth.verifyCredentialState() }
        }
    }

    private var colorScheme: ColorScheme? {
        switch profile?.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            ClosetView()
                .tabItem { Label("Closet", systemImage: "tshirt") }
                .tag(AppTab.closet)
            OutfitsView()
                .tabItem { Label("Outfits", systemImage: "rectangle.stack") }
                .tag(AppTab.outfits)
            ShopView()
                .tabItem { Label("Shop", systemImage: "bag") }
                .tag(AppTab.shop)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .sheet(isPresented: $router.isAddSheetPresented) {
            AddGarmentSheet(initialTab: router.addSheetInitialTab)
        }
    }
}
