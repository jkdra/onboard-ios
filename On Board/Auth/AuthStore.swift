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

    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async {
        state = .signingIn(.apple)
        do {
            let session = try await service.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            state = .signedIn(session)
        } catch let error as AuthError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signInWithGoogle() async {
        state = .signingIn(.google)
        do {
            let session = try await service.signInWithGoogle()
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

    func sendEmailOTP(email: String) async throws {
        try await service.sendEmailOTP(email: email)
    }

    func verifyEmailOTP(email: String, token: String) async {
        state = .signingIn(.email)
        do {
            let session = try await service.verifyEmailOTP(email: email, token: token)
            state = .signedIn(session)
        } catch let error as AuthError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func linkApple(idToken: String, nonce: String?) async throws {
        let session = try await service.linkApple(idToken: idToken, nonce: nonce)
        state = .signedIn(session)
    }

    func linkGoogle() async throws {
        let session = try await service.linkGoogle()
        state = .signedIn(session)
    }

    func sendLinkPhoneOTP(phone: String) async throws {
        try await service.sendLinkPhoneOTP(phone: phone)
    }

    func verifyLinkPhoneOTP(phone: String, token: String) async throws {
        let session = try await service.verifyLinkPhoneOTP(phone: phone, token: token)
        state = .signedIn(session)
    }

    func sendLinkEmailOTP(email: String) async throws {
        try await service.sendLinkEmailOTP(email: email)
    }

    func verifyLinkEmailOTP(email: String, token: String) async throws {
        let session = try await service.verifyLinkEmailOTP(email: email, token: token)
        state = .signedIn(session)
    }

    func unlinkIdentity(_ identity: LinkedIdentity) async throws {
        guard let session else {
            throw AuthError.sessionRestoreFailed
        }
        guard session.canUnlinkIdentity(identity) else {
            throw AuthError.cannotUnlinkLastSignInMethod
        }
        let updated = try await service.unlinkIdentity(id: identity.id)
        state = .signedIn(updated)
    }

    func refreshLinkedMethods() async {
        guard isSignedIn else { return }
        do {
            if let session = try await service.refreshAuthSession() {
                state = .signedIn(session)
            }
        } catch {
            // Keep the current session if refresh fails.
        }
    }

    func reportSessionExpired() async {
        try? await service.signOut()
        state = .failed(AuthError.sessionExpired.localizedDescription)
    }

    func reportFailure(_ message: String) {
        state = .failed(message)
    }

    func cancelSignIn() {
        switch state {
        case .signingIn, .failed:
            state = .signedOut
        default:
            break
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
