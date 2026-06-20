//
//  SupabaseAuthService.swift
//  On Board
//

import Foundation
import Supabase

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
            guard configuration.isGoogleSignInConfigured else {
                throw AuthError.providerUnavailable(.google)
            }
            throw AuthError.providerUnavailable(.google)
        case .phone:
            throw AuthError.unknown("Use the phone number sign-in flow.")
        }
    }

    func sendPhoneOTP(phone: String) async throws {
        let client = try requireClient()
        try await client.auth.signInWithOTP(phone: phone)
    }

    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession {
        let client = try requireClient()
        try await client.auth.verifyOTP(phone: phone, token: token, type: .sms)

        guard let session = client.auth.currentSession, !session.isExpired else {
            throw AuthError.sessionRestoreFailed
        }

        return Self.mapSession(session)
    }

    func signInWithApple(idToken: String, fullName: String?) async throws -> AuthSession {
        let client = try requireClient()

        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken
            )
        )

        if let fullName {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
            if let userID = client.auth.currentSession?.user.id {
                _ = try? await client
                    .from("profiles")
                    .update(["display_name": fullName])
                    .eq("id", value: userID.uuidString)
                    .execute()
            }
        }

        guard let session = client.auth.currentSession, !session.isExpired else {
            throw AuthError.sessionRestoreFailed
        }

        return Self.mapSession(session)
    }

    func sendSchoolEmailVerification(to email: String) async throws {
        let client = try requireClient()
        try await client.auth.update(user: UserAttributes(email: email))
    }

    func verifySchoolEmailOTP(email: String, token: String) async throws {
        let client = try requireClient()
        try await client.auth.verifyOTP(email: email, token: token, type: .email)
    }

    func signOut() async throws {
        let client = try requireClient()
        try await client.auth.signOut()
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
            return Self.mapSession(stored)
        }

        do {
            let session = try await client.auth.session
            guard !session.isExpired else { return nil }
            return Self.mapSession(session)
        } catch {
            return nil
        }
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw AuthError.notConfigured }
        return client
    }

    private static func mapSession(_ session: Session) -> AuthSession {
        AuthSession(
            userId: session.user.id,
            provider: provider(from: session.user),
            email: session.user.email
        )
    }

    private static func provider(from user: User) -> AuthProvider {
        if let identity = user.identities?.first {
            switch identity.provider {
            case "apple": return .apple
            case "google": return .google
            case "phone": return .phone
            default: break
            }
        }

        if case .string(let value) = user.appMetadata["provider"] {
            switch value {
            case "apple": return .apple
            case "google": return .google
            case "phone": return .phone
            default: break
            }
        }

        return .apple
    }
}
