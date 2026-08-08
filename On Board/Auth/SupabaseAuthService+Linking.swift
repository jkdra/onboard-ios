//
//  SupabaseAuthService+Linking.swift
//  On Board
//
//  Split out of SupabaseAuthService.swift — identity linking/unlinking and
//  the Apple token revocation that must precede an Apple unlink or account
//  deletion.
//

import Foundation
import Supabase

extension SupabaseAuthService {
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

        if identity.provider == "google" {
            await MainActor.run {
                GoogleSignInService.disconnect()
            }
        }

        try await client.auth.unlinkIdentity(identity)
        _ = try await client.auth.refreshSession()
        return try await requireRefreshedSession()
    }

    func revokeApple(authorizationCode: String) async throws {
        let client = try requireClient()
        struct RevokeRequest: Encodable {
            let authorizationCode: String
        }

        do {
            _ = try await client.functions.invoke(
                "revoke-apple",
                options: FunctionInvokeOptions(body: RevokeRequest(authorizationCode: authorizationCode))
            )
        } catch {
            throw AuthError.unknown("Failed to revoke Apple Sign In: \(error.localizedDescription)")
        }
    }
}
