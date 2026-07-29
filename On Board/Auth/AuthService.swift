//
//  AuthService.swift
//  On Board
//

import Foundation

struct EmailStatus: Codable, Sendable {
    let exists: Bool
    let hasPassword: Bool

    init(exists: Bool, hasPassword: Bool) {
        self.exists = exists
        self.hasPassword = hasPassword
    }

    // No snake_case raw values: the Supabase client decoder applies
    // `.convertFromSnakeCase`, which already maps `has_password` → `hasPassword`.
    // Spelling `has_password` in a CodingKey re-introduces the `keyNotFound`
    // landmine (see CLAUDE.md) — decoding would look for a key the strategy has
    // already camel-cased away.
    enum CodingKeys: CodingKey {
        case exists
        case hasPassword
    }

    // `nonisolated` so the Supabase client can decode this off the main actor
    // (the module defaults conformances to MainActor isolation) — same pattern
    // as `Profile`.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exists = try container.decode(Bool.self, forKey: .exists)
        hasPassword = try container.decode(Bool.self, forKey: .hasPassword)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exists, forKey: .exists)
        try container.encode(hasPassword, forKey: .hasPassword)
    }
}

protocol AuthService: Sendable {
    /// Test/mock scaffolding, not a real production entry point — see
    /// `AuthStore.signIn(with:)`'s doc comment. Every provider has its own
    /// dedicated method below; that's what production views call.
    func signIn(with provider: AuthProvider) async throws -> AuthSession
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func sendPhoneOTP(phone: String) async throws
    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession
    func sendEmailOTP(email: String) async throws
    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession
    func checkEmailExists(email: String) async throws -> EmailStatus
    /// Whether `phone` (E.164, with the leading `+`) already has an account —
    /// the phone-flow counterpart to `checkEmailExists`, driving SignInView's
    /// "Account Found!" toast for phone sign-in the same way it already does
    /// for email.
    func checkPhoneExists(phone: String) async throws -> Bool
    func signUpWithPassword(email: String, password: String) async throws -> AuthSession?
    func signInWithPassword(email: String, password: String) async throws -> AuthSession
    /// Sets (or changes) the password on the signed-in account.
    func setPassword(_ password: String) async throws -> AuthSession
    func linkApple(idToken: String, nonce: String?) async throws -> AuthSession
    func linkGoogle() async throws -> AuthSession
    func sendLinkPhoneOTP(phone: String) async throws
    func verifyLinkPhoneOTP(phone: String, token: String) async throws -> AuthSession
    func sendLinkEmailOTP(email: String) async throws
    func verifyLinkEmailOTP(email: String, token: String) async throws -> AuthSession
    func unlinkIdentity(id: String) async throws -> AuthSession
    func revokeApple(authorizationCode: String) async throws
    func refreshAuthSession() async throws -> AuthSession?
    func signOut() async throws
    func deleteAccount() async throws
    func restoreSession() async throws -> AuthSession?
}

enum AuthServiceFactory {
    @MainActor
    static func make(configuration: AppConfiguration = .current) -> any AuthService {
        if configuration.isSupabaseConfigured {
            SupabaseAuthService(configuration: configuration)
        } else {
            MockAuthService()
        }
    }
}
