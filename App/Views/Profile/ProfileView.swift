import AuthenticationServices
import OutfitEngine
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    ProfileForm(profile: profile)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Profile")
        }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: UserProfile
    @Environment(AppServices.self) private var services
    @Environment(AuthService.self) private var auth
    @State private var newBrand = ""
    @State private var exportURL: URL?
    @State private var isDeletePresented = false
    @State private var notificationError: String?
    @AppStorage(ServerSettings.overrideKey) private var serverAddress = ""

    var body: some View {
        Form {
            accountSection

            Section {
                TextField("e.g. 192.168.1.20:8787", text: $serverAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !serverAddress.isEmpty, ServerSettings.normalized(serverAddress) == nil {
                    Text("This doesn't look like a valid address.").font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Only needed for AI features. Enter the address of the computer running the Wardrobe backend. Leave empty to use the built-in address.")
            }

            Section {
                TextField("Name", text: $profile.name)
                TextField("City (leave empty to use your location)", text: Binding(
                    get: { profile.cityOverride ?? "" },
                    set: { profile.cityOverride = $0.isEmpty ? nil : $0 }
                ))
                .textContentType(.addressCity)
            } header: {
                Text("You")
            } footer: {
                Text("Weather comes from your current location unless you set a city.")
            }

            Section("Style") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferred styles").font(.subheadline)
                    ChipSelector(
                        options: Style.allCases,
                        selection: Binding(get: { Set(profile.preferredStyles) }, set: { new in profile.preferredStyles = Style.allCases.filter(new.contains) }),
                        title: \.displayName
                    )
                }
                .padding(.vertical, 4)
                colorChips(title: "Favorite colors", values: $profile.favoriteColors)
                colorChips(title: "Colors to avoid", values: $profile.avoidedColors)
            }

            Section("Favorite brands") {
                ForEach(profile.favoriteBrands, id: \.self) { Text($0) }
                    .onDelete { profile.favoriteBrands.remove(atOffsets: $0) }
                HStack {
                    TextField("Add a brand", text: $newBrand)
                        .onSubmit(addBrand)
                    Button("Add", action: addBrand).disabled(newBrand.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Budget") {
                HStack {
                    Text("Default budget per item")
                    Spacer()
                    TextField("None", value: $profile.defaultBudget, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                Picker("Currency", selection: $profile.currencyCode) {
                    ForEach(Array(PurchaseDirectionCatalog.eurRates.keys).sorted(), id: \.self) { Text($0).tag($0) }
                    if PurchaseDirectionCatalog.eurRates[profile.currencyCode] == nil {
                        Text(profile.currencyCode).tag(profile.currencyCode)
                    }
                }
            }

            Section {
                Toggle("Morning reminder", isOn: $profile.notificationsEnabled)
                if profile.notificationsEnabled {
                    DatePicker("Time", selection: notificationTime, displayedComponents: .hourAndMinute)
                }
                if let notificationError {
                    Text(notificationError).font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("\"Your outfits for today are ready\" at the time you choose.")
            }

            Section("Appearance") {
                Picker("Appearance", selection: Binding(get: { profile.appearance }, set: { profile.appearance = $0 })) {
                    ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Closet") {
                NavigationLink("Statistics") { StatisticsView() }
            }

            Section {
                Button("Export my data (JSON)") { exportData() }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export file", systemImage: "square.and.arrow.up") }
                }
                Button("Delete account and all data", role: .destructive) { isDeletePresented = true }
            } header: {
                Text("Your data")
            } footer: {
                Text("Photos stay on this iPhone. Only photos you add for recognition, order text and anonymous outfit attributes are sent to the Wardrobe server, and nothing is stored there.")
            }

            #if DEBUG
            Section("Debug") {
                Button("Load sample closet (25 garments)") {
                    SeedData.seed(SeedData.sampleCloset, into: services.repository, imageStore: services.imageStore)
                }
                Button("Clear AI ranking cache") { RankingCache().clear() }
            }
            #endif
        }
        .paperBackground()
        .onChange(of: profile.notificationsEnabled) { _, _ in Task { await updateNotifications() } }
        .onChange(of: profile.notificationHour) { _, _ in Task { await updateNotifications() } }
        .onChange(of: profile.notificationMinute) { _, _ in Task { await updateNotifications() } }
        .onDisappear { services.repository.save() }
        .confirmationDialog("Delete your account?", isPresented: $isDeletePresented, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive, action: deleteAccount)
        } message: {
            Text("All garments, photos, outfits and settings are permanently removed from this device. This can't be undone.")
        }
    }

    private var accountSection: some View {
        Section {
            if auth.isSignedIn {
                Label("Signed in with Apple", systemImage: "checkmark.seal.fill")
                Button("Sign out", role: .destructive) { auth.signOut() }
            } else {
                SignInWithAppleButton(.signIn, onRequest: { auth.configure($0) }) { result in
                    Task {
                        if let name = await auth.handle(result), profile.name.isEmpty { profile.name = name }
                        profile.appleUserID = auth.appleUserID
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                #if DEBUG
                Button("Development sign-in") { Task { await auth.signInForDevelopment() } }
                #endif
            }
            if auth.isWorking { ProgressView() }
            if let error = auth.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Signing in enables automatic recognition, order import and AI-ranked outfits.")
        }
    }

    private var notificationTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: profile.notificationTime) ?? Date() },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                profile.notificationHour = components.hour ?? 7
                profile.notificationMinute = components.minute ?? 30
            }
        )
    }

    private func colorChips(title: String, values: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            ChipSelector(
                options: ColorPalette.names,
                selection: Binding(get: { Set(values.wrappedValue) }, set: { values.wrappedValue = ColorPalette.names.filter($0.contains) }),
                title: { $0.capitalized },
                swatch: { Color.garment($0) }
            )
        }
        .padding(.vertical, 4)
    }

    private func addBrand() {
        let brand = newBrand.trimmingCharacters(in: .whitespaces)
        guard !brand.isEmpty, !profile.favoriteBrands.contains(where: { $0.caseInsensitiveCompare(brand) == .orderedSame }) else { return }
        profile.favoriteBrands.append(brand)
        newBrand = ""
    }

    private func updateNotifications() async {
        notificationError = nil
        guard profile.notificationsEnabled else {
            services.notifications.cancelMorningReminder()
            return
        }
        let scheduled = await services.notifications.scheduleMorningReminder(hour: profile.notificationHour, minute: profile.notificationMinute)
        if !scheduled {
            notificationError = "Notifications are turned off for Wardrobe in Settings."
            profile.notificationsEnabled = false
        }
    }

    private func exportData() {
        exportURL = try? DataExporter.export(repository: services.repository)
    }

    private func deleteAccount() {
        services.notifications.cancelMorningReminder()
        RankingCache().clear()
        auth.signOut()
        services.repository.deleteEverything()
        // A fresh profile brings back onboarding.
        _ = services.repository.profile()
    }
}
