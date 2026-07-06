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
        case .email: SampleProfileID.maya
        }

        let session = makeSession(
            userId: userId,
            primaryProvider: provider,
            email: provider == .email ? "you@example.com" : nil,
            phone: provider == .phone ? "+15555550100" : nil,
            linkedProviders: provider == .apple || provider == .google ? [provider] : []
        )
        persist(session)
        return session
    }

    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession {
        _ = idToken
        _ = nonce
        _ = fullName
        return try await signIn(with: .apple)
    }

    func signInWithGoogle() async throws -> AuthSession {
        try await signIn(with: .google)
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

    func sendEmailOTP(email: String) async throws {
        _ = email
        try await Task.sleep(for: .milliseconds(250))
    }

    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession {
        _ = email
        _ = token
        try await Task.sleep(for: .milliseconds(350))
        let session = makeSession(
            userId: SampleProfileID.maya,
            primaryProvider: .email,
            email: email,
            phone: nil,
            linkedProviders: []
        )
        persist(session)
        return session
    }

    func signInWithPassword(email: String, password: String) async throws -> AuthSession {
        _ = password
        try await Task.sleep(for: .milliseconds(350))
        let session = makeSession(
            userId: SampleProfileID.maya,
            primaryProvider: .email,
            email: email,
            phone: nil,
            linkedProviders: [],
            hasPassword: true
        )
        persist(session)
        return session
    }

    func setPassword(_ password: String) async throws -> AuthSession {
        _ = password
        try await Task.sleep(for: .milliseconds(350))
        guard let session = try await restoreSession() else {
            throw AuthError.sessionRestoreFailed
        }
        let updated = makeSession(
            userId: session.userId,
            primaryProvider: session.primaryProvider,
            email: session.email,
            phone: session.phone,
            linkedProviders: session.linkedIdentities.map(\.provider),
            hasPassword: true
        )
        persist(updated)
        return updated
    }

    func linkApple(idToken: String, nonce: String?) async throws -> AuthSession {
        _ = idToken
        _ = nonce
        return try await link(provider: .apple)
    }

    func linkGoogle() async throws -> AuthSession {
        try await link(provider: .google)
    }

    func sendLinkPhoneOTP(phone: String) async throws {
        _ = phone
        try await Task.sleep(for: .milliseconds(250))
    }

    func verifyLinkPhoneOTP(phone: String, token: String) async throws -> AuthSession {
        _ = phone
        _ = token
        guard var session = try await restoreSession() else {
            throw AuthError.sessionRestoreFailed
        }
        session = makeSession(
            userId: session.userId,
            primaryProvider: session.primaryProvider,
            email: session.email,
            phone: phone,
            linkedProviders: session.linkedIdentities.map(\.provider)
        )
        persist(session)
        return session
    }

    func sendLinkEmailOTP(email: String) async throws {
        _ = email
        try await Task.sleep(for: .milliseconds(250))
    }

    func verifyLinkEmailOTP(email: String, token: String) async throws -> AuthSession {
        _ = email
        _ = token
        guard var session = try await restoreSession() else {
            throw AuthError.sessionRestoreFailed
        }
        session = makeSession(
            userId: session.userId,
            primaryProvider: session.primaryProvider,
            email: email,
            phone: session.phone,
            linkedProviders: session.linkedIdentities.map(\.provider)
        )
        persist(session)
        return session
    }

    func unlinkIdentity(id: String) async throws -> AuthSession {
        guard let session = try await restoreSession() else {
            throw AuthError.sessionRestoreFailed
        }

        guard let identity = session.linkedIdentities.first(where: { $0.id == id }) else {
            throw AuthError.unknown("That sign-in method is no longer linked.")
        }
        guard session.canUnlinkIdentity(identity) else {
            throw AuthError.cannotUnlinkLastSignInMethod
        }

        let updated = makeSession(
            userId: session.userId,
            primaryProvider: session.primaryProvider,
            email: session.email,
            phone: session.phone,
            linkedProviders: session.linkedIdentities
                .filter { $0.id != id }
                .map(\.provider)
        )
        persist(updated)
        return updated
    }

    func revokeApple(authorizationCode: String) async throws {
        _ = authorizationCode
        try await Task.sleep(for: .milliseconds(350))
    }

    func refreshAuthSession() async throws -> AuthSession? {
        try await restoreSession()
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

    private func link(provider: AuthProvider) async throws -> AuthSession {
        guard let session = try await restoreSession() else {
            throw AuthError.sessionRestoreFailed
        }
        guard !session.hasLinked(provider) else {
            throw AuthError.identityAlreadyLinked(provider)
        }

        var linked = session.linkedIdentities.map(\.provider)
        linked.append(provider)

        let updated = makeSession(
            userId: session.userId,
            primaryProvider: session.primaryProvider,
            email: session.email,
            phone: session.phone,
            linkedProviders: linked
        )
        persist(updated)
        return updated
    }

    private func makeSession(
        userId: UUID,
        primaryProvider: AuthProvider,
        email: String?,
        phone: String?,
        linkedProviders: [AuthProvider],
        hasPassword: Bool = false
    ) -> AuthSession {
        let linkedIdentities = linkedProviders
            .filter { $0 == .apple || $0 == .google }
            .map { provider in
                LinkedIdentity(
                    id: "mock-\(provider.rawValue)",
                    provider: provider,
                    email: email
                )
            }

        return AuthSession(
            userId: userId,
            primaryProvider: primaryProvider,
            email: email,
            phone: phone,
            hasEmailIdentity: email?.isEmpty == false,
            hasPhoneIdentity: phone?.isEmpty == false,
            hasPassword: hasPassword,
            linkedIdentities: linkedIdentities
        )
    }

    private func persist(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: sessionKey)
    }
}
