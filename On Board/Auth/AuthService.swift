//
//  AuthService.swift
//  On Board
//

import Foundation

struct EmailStatus: Codable, Sendable {
    let exists: Bool
    let hasPassword: Bool
    
    enum CodingKeys: String, CodingKey {
        case exists
        case hasPassword = "has_password"
    }
}

protocol AuthService: Sendable {
    func signIn(with provider: AuthProvider) async throws -> AuthSession
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func sendPhoneOTP(phone: String) async throws
    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession
    func sendEmailOTP(email: String) async throws
    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession
    func checkEmailExists(email: String) async throws -> EmailStatus
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
