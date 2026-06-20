//
//  MockAuthService.swift
//  On Board
//
//  Local sign-in stand-in until Supabase and provider SDKs are wired.
//  Persists the mock session in UserDefaults so restore can be tested.
//

import Foundation

final class MockAuthService: AuthService, @unchecked Sendable {
    private let defaults: UserDefaults
    private let sessionKey = "mock.auth.session"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func signIn(with provider: AuthProvider) async throws -> AuthSession {
        try await Task.sleep(for: .milliseconds(350))

        let userId: UUID = switch provider {
        case .apple: SampleProfileID.maya
        case .google: SampleProfileID.leo
        case .phone: SampleProfileID.phone
        }

        let session = AuthSession(
            userId: userId,
            provider: provider,
            email: "\(provider.rawValue).mock@onboard.dev"
        )
        persist(session)
        return session
    }

    func signInWithApple(idToken: String, fullName: String?) async throws -> AuthSession {
        _ = idToken
        _ = fullName
        return try await signIn(with: .apple)
    }

    func sendPhoneOTP(phone: String) async throws {
        _ = phone
        try await Task.sleep(for: .milliseconds(250))
    }

    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession {
        _ = phone
        _ = token
        try await Task.sleep(for: .milliseconds(350))
        return try await signIn(with: .phone)
    }

    func sendSchoolEmailVerification(to email: String) async throws {
        _ = email
        try await Task.sleep(for: .milliseconds(250))
    }

    func verifySchoolEmailOTP(email: String, token: String) async throws {
        _ = email
        _ = token
        try await Task.sleep(for: .milliseconds(250))
    }

    func signOut() async throws {
        defaults.removeObject(forKey: sessionKey)
    }

    func deleteAccount() async throws {
        try await Task.sleep(for: .milliseconds(350))
        defaults.removeObject(forKey: sessionKey)
    }

    func restoreSession() async throws -> AuthSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    private func persist(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: sessionKey)
    }
}
