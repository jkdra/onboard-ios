//
//  SupabaseAuthService.swift
//  On Board
//
//  Core session lifecycle + phone/email OTP. Split by topic (mirroring
//  SupabaseBoardService): SupabaseAuthService+Password.swift,
//  SupabaseAuthService+Social.swift, SupabaseAuthService+Linking.swift.
//

import Foundation
import Supabase
import UIKit

final class SupabaseAuthService: AuthService, @unchecked Sendable {
    // Not private: the +Social/+Linking extensions read googleClientID /
    // isGoogleOAuthAvailable from it.
    let configuration: AppConfiguration
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
        // redirectTo makes the email's magic link a universal link back to the
        // app (falling back to the web /auth/callback page). The typed 6-digit
        // code remains the primary path; this just fixes link clicks.
        try await client.auth.signInWithOTP(
            email: email,
            redirectTo: AppConfiguration.webAuthCallbackURL
        )
    }

    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession {
        let client = try requireClient()
        try await client.auth.verifyOTP(email: email, token: token, type: .email)
        return try await requireRefreshedSession()
    }

    func checkEmailExists(email: String) async throws -> EmailStatus {
        let client = try requireClient()
        struct CheckEmailRequest: Encodable {
            let p_email: String
        }

        return try await client.rpc(
            "check_email_exists",
            params: CheckEmailRequest(p_email: email)
        ).execute().value
    }

    func checkPhoneExists(phone: String) async throws -> Bool {
        let client = try requireClient()
        struct CheckPhoneRequest: Encodable {
            let p_phone: String
        }

        return try await client.rpc(
            "check_phone_exists",
            params: CheckPhoneRequest(p_phone: phone)
        ).execute().value
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

        await MainActor.run {
            GoogleSignInService.disconnect()
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

    // Not private: shared by the +Password/+Social/+Linking extensions.
    func requireClient() throws -> SupabaseClient {
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

    // Not private: shared by the +Password/+Social/+Linking extensions.
    func requireRefreshedSession() async throws -> AuthSession {
        guard let session = try await refreshAuthSession() else {
            throw AuthError.sessionRestoreFailed
        }
        return session
    }

    private func mapSession(using client: SupabaseClient, session: Session) async throws -> AuthSession {
        let identities = try await client.auth.userIdentities()
        return Self.mapSession(session, identities: identities)
    }

    // Not private: the +Password/+Social extensions map fresh sessions with it.
    static func mapSession(_ session: Session, identities: [UserIdentity]) -> AuthSession {
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
