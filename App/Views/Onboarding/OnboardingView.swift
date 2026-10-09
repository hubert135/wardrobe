import AuthenticationServices
import OutfitEngine
import SwiftData
import SwiftUI

/// Three steps: location + styles, first garments, first outfits.
struct OnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(AuthService.self) private var auth
    @Query private var profiles: [UserProfile]
    @Query private var garments: [Garment]
    @State private var step = 0
    @State private var today: TodayViewModel?

    private let targetCount = 10
    private var unlockCount: Int { services.outfits.engine.config.minimumClosetSize }
    private var activeCount: Int { garments.filter { $0.status != .archived }.count }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3)
                    .padding()
                    .accessibilityLabel("Step \(step + 1) of 3")
                TabView(selection: $step) {
                    stepOne.tag(0)
                    stepTwo.tag(1)
                    stepThree.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.default, value: step)
            }
            .navigationTitle("Welcome to Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $router.isAddSheetPresented) {
            AddGarmentSheet(initialTab: router.addSheetInitialTab)
        }
    }

    // MARK: Step 1

    private var stepOne: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your closet, dressed for the day.")
                    .font(.largeTitle.bold())
                Text("Wardrobe learns what you own and suggests outfits that fit the weather and your plans.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Account", systemImage: "person.crop.circle").font(.headline)
                    if auth.isSignedIn {
                        Label("Signed in with Apple", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        SignInWithAppleButton(.signIn, onRequest: { auth.configure($0) }) { result in
                            Task {
                                let name = await auth.handle(result)
                                if let profile = profiles.first {
                                    profile.appleUserID = auth.appleUserID
                                    if let name, profile.name.isEmpty { profile.name = name }
                                }
                            }
                        }
                        .frame(height: 48)
                        Text("Needed for automatic recognition and AI outfit ranking. You can do it later in Profile.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding().card()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Weather", systemImage: "location").font(.headline)
                    Text("Allow location so outfits match today's temperature and rain.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Allow location") {
                        Task { await services.location.requestPermission() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(services.location.authorizationStatus != .notDetermined)
                }
                .padding().card()

                if let profile = profiles.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your style", systemImage: "sparkles").font(.headline)
                        ChipSelector(
                            options: Style.allCases,
                            selection: Binding(get: { Set(profile.preferredStyles) }, set: { new in profile.preferredStyles = Style.allCases.filter(new.contains) }),
                            title: \.displayName
                        )
                    }
                    .padding().card()
                }

                Button {
                    step = 1
                } label: {
                    Text("Continue").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }

    // MARK: Step 2

    private var stepTwo: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "tshirt")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("Add your first \(targetCount) garments")
                .font(.title2.bold())
            ProgressView(value: Double(min(activeCount, targetCount)), total: Double(targetCount))
                .padding(.horizontal, 40)
            Text(progressText)
                .font(.headline)
                .foregroundStyle(activeCount >= unlockCount ? .green : .secondary)
                .multilineTextAlignment(.center)
            Text("Photograph a few pieces at once, or paste an order confirmation email.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                router.openAdd()
            } label: {
                Label("Add garments", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            #if DEBUG
            Button("Load sample closet") {
                SeedData.seed(SeedData.sampleCloset, into: services.repository, imageStore: services.imageStore)
            }
            .font(.footnote)
            #endif
            Spacer()
            HStack {
                Button("Back") { step = 0 }
                Spacer()
                Button(activeCount >= unlockCount ? "See my outfits" : "Skip for now") {
                    step = 2
                    Task { await loadFirstOutfits() }
                }
                .bold()
            }
        }
        .padding()
    }

    private var progressText: String {
        let remaining = unlockCount - activeCount
        if remaining > 0 { return "\(remaining) more to unlock your first outfits" }
        return "Outfits unlocked. \(max(targetCount - activeCount, 0)) more for better variety."
    }

    // MARK: Step 3

    private var stepThree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("Your first outfits").font(.title2.bold())
                if let today {
                    switch today.phase {
                    case .loading, .idle:
                        OutfitCardSkeleton()
                    case .notEnoughGarments:
                        Text("Add at least \(unlockCount) garments to see outfits. You can always do it from the Closet tab.")
                            .foregroundStyle(.secondary)
                    case .noMatches:
                        Text("No outfits match today's weather yet. Add a few more pieces from the Closet tab.")
                            .foregroundStyle(.secondary)
                    case .loaded:
                        ForEach(today.suggestions) { suggestion in
                            OutfitCard(
                                title: suggestion.outfit.title,
                                reasoning: suggestion.outfit.reasoning,
                                tiles: today.tiles(for: suggestion),
                                isFavorite: suggestion.isFavorite,
                                onFavorite: { today.toggleFavorite(suggestion) }
                            )
                        }
                    }
                } else {
                    OutfitCardSkeleton()
                }

                Button {
                    profiles.first?.onboardingCompleted = true
                    services.repository.save()
                } label: {
                    Text("Start using Wardrobe").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.finish")
            }
            .padding()
        }
    }

    private func loadFirstOutfits() async {
        let model = TodayViewModel(services: services)
        today = model
        await model.loadWeather()
        await model.suggest()
    }
}
