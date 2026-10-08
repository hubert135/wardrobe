import AuthenticationServices
import Foundation
import Observation

/// Holds the backend session token in the Keychain. Not actor-isolated so the networking layer
/// can read it from any context.
final class SessionTokenStore: SessionTokenProvider {
    private let keychain: KeychainStore
    private let key = "backend.session"
    var onExpired: (() -> Void)?

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    var sessionToken: String? { keychain.string(for: key) }

    func store(_ token: String?) { keychain.set(token, for: key) }

    func sessionExpired() {
        store(nil)
        DispatchQueue.main.async { [weak self] in self?.onExpired?() }
    }
}

/// Sign in with Apple, exchanged for a backend session token.
@MainActor
@Observable
final class AuthService {
    private(set) var isSignedIn: Bool
    private(set) var isWorking = false
    var errorMessage: String?

    private let tokens: SessionTokenStore
    private let api: WardrobeAPI
    private let userIDKey = "auth.appleUserID"

    init(tokens: SessionTokenStore, api: WardrobeAPI) {
        self.tokens = tokens
        self.api = api
        self.isSignedIn = tokens.sessionToken != nil
        tokens.onExpired = { [weak self] in self?.isSignedIn = false }
    }

    var appleUserID: String? { UserDefaults.standard.string(forKey: userIDKey) }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    /// Handles the result of `SignInWithAppleButton`. Returns the given name if Apple provided it.
    @discardableResult
    func handle(_ result: Result<ASAuthorization, Error>) async -> String? {
        errorMessage = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in with Apple failed. Please try again."
            }
            return nil
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple did not return an identity token."
                return nil
            }
            UserDefaults.standard.set(credential.user, forKey: userIDKey)
            await exchange(identityToken: identityToken)
            return credential.fullName?.givenName
        }
    }

    /// Development shortcut: works only when the backend runs with `AUTH_DEV_BYPASS=true`.
    func signInForDevelopment() async {
        errorMessage = nil
        await exchange(identityToken: "dev")
    }

    func signOut() {
        tokens.store(nil)
        UserDefaults.standard.removeObject(forKey: userIDKey)
        isSignedIn = false
    }

    /// Signs out locally if the Apple ID credential was revoked.
    func verifyCredentialState() async {
        guard let userID = appleUserID else { return }
        let state = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
        if state == .revoked || state == .notFound { signOut() }
    }

    private func exchange(identityToken: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await api.createSession(identityToken: identityToken)
            tokens.store(session.sessionToken)
            isSignedIn = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reach the Wardrobe server."
        }
    }
}
