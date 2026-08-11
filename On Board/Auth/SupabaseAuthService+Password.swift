//
//  SupabaseAuthService+Password.swift
//  On Board
//
//  Split out of SupabaseAuthService.swift — email + password sign-up,
//  sign-in, and password management.
//

import Foundation
import Supabase

extension SupabaseAuthService {
    func signUpWithPassword(email: String, password: String) async throws -> AuthSession? {
        let client = try requireClient()
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                let identities = try await client.auth.userIdentities()
                return Self.mapSession(session, identities: identities)
            } else {
                return nil
            }
        } catch {
            throw Self.mapPasswordError(error)
        }
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
}
