//
//  AuthService.swift
//  On Board
//

import Foundation

protocol AuthService: Sendable {
    func signIn(with provider: AuthProvider) async throws -> AuthSession
    func signInWithApple(idToken: String, fullName: String?) async throws -> AuthSession
    func sendPhoneOTP(phone: String) async throws
    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession
    func sendSchoolEmailVerification(to email: String) async throws
    func verifySchoolEmailOTP(email: String, token: String) async throws
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
