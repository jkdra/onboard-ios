//
//  AuthStore.swift
//  On Board
//

import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    private(set) var state: AuthState = .signedOut

    private let service: any AuthService

    var session: AuthSession? { state.session }
    var isSignedIn: Bool { state.isSignedIn }

    init(service: any AuthService) {
        self.service = service
    }

    func restoreSession() async {
        do {
            if let session = try await service.restoreSession() {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signIn(with provider: AuthProvider) async {
        state = .signingIn(provider)
        do {
            let session = try await service.signIn(with: provider)
            state = .signedIn(session)
        } catch let error as AuthError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signInWithApple(idToken: String, fullName: String?) async {
        state = .signingIn(.apple)
        do {
            let session = try await service.signInWithApple(idToken: idToken, fullName: fullName)
            state = .signedIn(session)
        } catch let error as AuthError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func sendPhoneOTP(phone: String) async throws {
        try await service.sendPhoneOTP(phone: phone)
    }

    func verifyPhoneOTP(phone: String, token: String) async {
        state = .signingIn(.phone)
        do {
            let session = try await service.verifyPhoneOTP(phone: phone, token: token)
            state = .signedIn(session)
        } catch let error as AuthError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func sendSchoolEmailVerification(to email: String) async throws {
        try await service.sendSchoolEmailVerification(to: email)
    }

    func verifySchoolEmailOTP(email: String, token: String) async throws {
        try await service.verifySchoolEmailOTP(email: email, token: token)
    }

    func reportSessionExpired() async {
        try? await service.signOut()
        state = .failed(AuthError.sessionExpired.localizedDescription)
    }

    func reportFailure(_ message: String) {
        state = .failed(message)
    }

    func cancelSignIn() {
        if case .signingIn = state {
            state = .signedOut
        }
    }

    func signOut() async {
        do {
            try await service.signOut()
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func deleteAccount() async {
        do {
            try await service.deleteAccount()
            state = .signedOut
        } catch let error as AuthError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
