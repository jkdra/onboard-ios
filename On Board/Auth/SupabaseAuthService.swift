//
//  SupabaseAuthService.swift
//  On Board
//

import AuthenticationServices
import Foundation
import Supabase
import UIKit

// Apple re-sends the full name when a user revokes and re-authorizes the app.
// Only adopt it while the profile has no chosen display name — never overwrite.
enum AppleNameAdoption {
    nonisolated static func shouldAdopt(currentDisplayName: String?) -> Bool {
        (currentDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// Provides a real foreground window as the ASWebAuthenticationSession anchor.
// The SDK's default creates UIWindow() with no scene, which silently fails on iOS 16+.
private final class ForegroundWindowProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = ForegroundWindowProvider()

    // Explicitly nonisolated so the static `shared` initializer can use it
    // without requiring a @MainActor context.
    nonisolated override init() { super.init() }

    @MainActor
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            .flatMap { $0 as? UIWindowScene }?
            .keyWindow ?? ASPresentationAnchor()
    }
}

final class SupabaseAuthService: AuthService, @unchecked Sendable {
    private let configuration: AppConfiguration
    private let client: SupabaseClient?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        self.client = SupabaseClientFactory.client(for: configuration)
    }

    func signIn(with provider: AuthProvider) async throws -> AuthSession {
        guard configuration.isSupabaseConfigured, client != nil else {
            throw AuthError.notConfigured
        }

        switch provider {
        case .apple:
            throw AuthError.unknown("Use the native Sign in with Apple button.")
        case .google:
            return try await signInWithGoogle()
        case .phone:
            throw AuthError.unknown("Use the phone number sign-in flow.")
        case .email:
            throw AuthError.unknown("Use the email sign-in flow.")
        }
    }

    func sendPhoneOTP(phone: String) async throws {
        let client = try requireClient()
        guard let e164 = PhoneNumberNormalizer.e164(from: phone) else {
            throw AuthError.invalidPhoneNumber
        }
        // POST /auth/v1/otp — Supabase forwards to your configured SMS provider (e.g. Twilio).
        try await client.auth.signInWithOTP(phone: e164, channel: .sms)
    }

    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession {
        let client = try requireClient()
        guard let e164 = PhoneNumberNormalizer.e164(from: phone) else {
            throw AuthError.invalidPhoneNumber
        }
        try await client.auth.verifyOTP(phone: e164, token: token, type: .sms)
        return try await requireRefreshedSession()
    }

    func sendEmailOTP(email: String) async throws {
        let client = try requireClient()
        try await client.auth.signInWithOTP(email: email)
    }

    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession {
        let client = try requireClient()
        try await client.auth.verifyOTP(email: email, token: token, type: .email)
        return try await requireRefreshedSession()
    }

    func signInWithPassword(email: String, password: String) async throws -> AuthSession {
        let client = try requireClient()
        do {
            try await client.auth.signIn(email: email, password: password)
        } catch {
            throw Self.mapPasswordError(error)
        }
        return try await requireRefreshedSession()
    }

    func setPassword(_ password: String) async throws -> AuthSession {
        let client = try requireClient()
        do {
            // has_password rides along in user metadata because Supabase never
            // exposes whether an account has a password — the session needs it
            // to decide between "Set Password" and "Change Password".
            _ = try await client.auth.update(
                user: UserAttributes(
                    password: password,
                    data: ["has_password": .bool(true)]
                )
            )
        } catch {
            throw Self.mapPasswordError(error)
        }
        return try await requireRefreshedSession()
    }

    /// Maps GoTrue's password-related API errors to friendly copy.
    private static func mapPasswordError(_ error: Error) -> Error {
        if NetworkErrorClassifier.isConnectivityFailure(error) {
            return AuthError.networkUnavailable
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("invalid login credentials") {
            return AuthError.invalidCredentials
        }
        if message.contains("password") && (message.contains("should be at least") || message.contains("weak")) {
            return AuthError.weakPassword
        }
        if message.contains("different from the old password") {
            return AuthError.unknown("Your new password must be different from your current one.")
        }
        return error
    }

    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession {
        let client = try requireClient()

        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )

        if let fullName {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
            if let userID = client.auth.currentSession?.user.id {
                nonisolated struct NameRow: Decodable {
                    let displayName: String?
                    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
                }
                do {
                    let row: NameRow = try await client
                        .from("profiles")
                        .select("display_name")
                        .eq("id", value: userID.uuidString)
                        .single()
                        .execute()
                        .value
                    if AppleNameAdoption.shouldAdopt(currentDisplayName: row.displayName) {
                        _ = try? await client
                            .from("profiles")
                            .update(["display_name": fullName])
                            .eq("id", value: userID.uuidString)
                            .execute()
                    }
                } catch {
                    // Unknown current name (fetch failed) — never risk overwriting a
                    // chosen display name. The user can set it from their profile.
                }
            }
        }

        return try await requireRefreshedSession()
    }

    func signInWithGoogle() async throws -> AuthSession {
        let client = try requireClient()

        let session: Session

        if let clientID = configuration.googleClientID {
            // Native Google Sign-In: GID SDK presents the account picker, returns an ID token,
            // which we exchange with Supabase directly without opening a browser.
            let credential = try await GoogleSignInService.signIn(clientID: clientID)
            session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: credential.idToken,
                    nonce: credential.nonce
                )
            )
        } else {
            // Fallback: Supabase web OAuth (opens ASWebAuthenticationSession).
            guard configuration.isGoogleOAuthAvailable else {
                throw AuthError.providerUnavailable(.google)
            }
            let provider = ForegroundWindowProvider.shared
            session = try await client.auth.signInWithOAuth(provider: .google) { webSession in
                webSession.presentationContextProvider = provider
                webSession.prefersEphemeralWebBrowserSession = false
            }
        }

        let identities = try await client.auth.userIdentities()
        return Self.mapSession(session, identities: identities)
    }

    func linkApple(idToken: String, nonce: String?) async throws -> AuthSession {
        let client = try requireClient()
        _ = try await client.auth.linkIdentityWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        return try await requireRefreshedSession()
    }

    func linkGoogle() async throws -> AuthSession {
        let client = try requireClient()

        if let clientID = configuration.googleClientID {
            let credential = try await GoogleSignInService.signIn(clientID: clientID)
            _ = try await client.auth.linkIdentityWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: credential.idToken,
                    nonce: credential.nonce
                )
            )
        } else {
            guard configuration.isGoogleOAuthAvailable else {
                throw AuthError.providerUnavailable(.google)
            }
            // `signInWithOAuth` (used by signInWithGoogle's fallback below) starts a
            // fresh sign-in — using it here would swap the session to a different/new
            // account instead of linking. `linkIdentity` is the correct call for
            // attaching an OAuth identity to the currently signed-in user; it opens the
            // browser and completes via the onOpenURL → auth.handle(_:) deep-link path.
            try await client.auth.linkIdentity(provider: .google)
        }

        return try await requireRefreshedSession()
    }

    func sendLinkPhoneOTP(phone: String) async throws {
        let client = try requireClient()
        guard let e164 = PhoneNumberNormalizer.e164(from: phone) else {
            throw AuthError.invalidPhoneNumber
        }
        try await client.auth.update(user: UserAttributes(phone: e164))
    }

    func verifyLinkPhoneOTP(phone: String, token: String) async throws -> AuthSession {
        let client = try requireClient()
        guard let e164 = PhoneNumberNormalizer.e164(from: phone) else {
            throw AuthError.invalidPhoneNumber
        }
        try await client.auth.verifyOTP(phone: e164, token: token, type: .phoneChange)
        return try await requireRefreshedSession()
    }

    func sendLinkEmailOTP(email: String) async throws {
        let client = try requireClient()
        try await client.auth.update(user: UserAttributes(email: email))
    }

    func verifyLinkEmailOTP(email: String, token: String) async throws -> AuthSession {
        let client = try requireClient()
        try await client.auth.verifyOTP(email: email, token: token, type: .emailChange)
        return try await requireRefreshedSession()
    }

    func unlinkIdentity(id: String) async throws -> AuthSession {
        let client = try requireClient()
        let identities = try await client.auth.userIdentities()
        guard let identity = identities.first(where: { $0.id == id }) else {
            throw AuthError.unknown("That sign-in method is no longer linked.")
        }

        try await client.auth.unlinkIdentity(identity)
        _ = try await client.auth.refreshSession()
        return try await requireRefreshedSession()
    }

    func refreshAuthSession() async throws -> AuthSession? {
        let client = try requireClient()
        guard let session = client.auth.currentSession, !session.isExpired else {
            return nil
        }
        return try await mapSession(using: client, session: session)
    }

    func signOut() async throws {
        let client = try requireClient()
        // Unlike account deletion (whose `ON DELETE CASCADE` from auth.users removes
        // device_tokens automatically), signing out keeps the account intact — so this
        // device must be explicitly unregistered or it keeps getting that account's pushes.
        await unregisterCurrentDeviceToken(client: client)
        do {
            try await client.auth.signOut()
        } catch {
            // Whatever the failure (offline, server error), the UI treats sign-out
            // as done — so the local session must actually be cleared or the next
            // launch silently restores it. The refresh token dies at expiry.
            try? await client.auth.signOut(scope: .local)
        }
    }

    func deleteAccount() async throws {
        let client = try requireClient()
        do {
            _ = try await client.rpc("delete_own_account").execute()
        } catch {
            throw AuthError.accountDeletionFailed(
                "We couldn't delete your account right now. Try again later or contact support."
            )
        }
        try await client.auth.signOut()
    }

    func restoreSession() async throws -> AuthSession? {
        let client = try requireClient()

        if let stored = client.auth.currentSession, !stored.isExpired {
            do {
                return try await mapSession(using: client, session: stored)
            } catch where NetworkErrorClassifier.isConnectivityFailure(error) {
                throw AuthError.networkUnavailable
            }
        }

        do {
            let session = try await client.auth.session
            guard !session.isExpired else { return nil }
            return try await mapSession(using: client, session: session)
        } catch where NetworkErrorClassifier.isConnectivityFailure(error) {
            throw AuthError.networkUnavailable
        } catch {
            return nil
        }
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw AuthError.notConfigured }
        return client
    }

    private func unregisterCurrentDeviceToken(client: SupabaseClient) async {
        guard let tokenHex = NotificationService.shared.currentTokenHex else { return }
        _ = try? await client
            .from("device_tokens")
            .delete()
            .eq("token", value: tokenHex)
            .execute()
    }

    private func requireRefreshedSession() async throws -> AuthSession {
        guard let session = try await refreshAuthSession() else {
            throw AuthError.sessionRestoreFailed
        }
        return session
    }

    private func mapSession(using client: SupabaseClient, session: Session) async throws -> AuthSession {
        let identities = try await client.auth.userIdentities()
        return Self.mapSession(session, identities: identities)
    }

    private static func mapSession(_ session: Session, identities: [UserIdentity]) -> AuthSession {
        let user = session.user
        let linkedIdentities = identities.compactMap { identity -> LinkedIdentity? in
            let email = identity.identityData?["email"]?.stringValue
            return LinkedIdentity.fromSupabaseProvider(identity.provider, id: identity.id, email: email)
        }
        let identityProviders = Set(identities.map(\.provider))

        let hasPassword: Bool = if case .bool(true) = user.userMetadata["has_password"] {
            true
        } else {
            false
        }

        return AuthSession(
            userId: user.id,
            primaryProvider: primaryProvider(from: user, identities: identities),
            email: user.email,
            phone: user.phone,
            hasEmailIdentity: identityProviders.contains("email"),
            hasPhoneIdentity: identityProviders.contains("phone"),
            hasPassword: hasPassword,
            linkedIdentities: linkedIdentities
        )
    }

    private static func primaryProvider(from user: User, identities: [UserIdentity]) -> AuthProvider {
        if let identity = identities.first, let provider = AuthProvider(supabaseProvider: identity.provider) {
            return provider
        }

        if let phone = user.phone, !phone.isEmpty {
            return .phone
        }

        if let email = user.email, !email.isEmpty {
            return .email
        }

        if case .string(let value) = user.appMetadata["provider"],
           let provider = AuthProvider(supabaseProvider: value) {
            return provider
        }

        return .phone
    }
}
