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

    /// True while the app is deliberately ending the session (sign out, delete,
    /// session-expired handling). The SDK emits a `.signedOut` auth event during
    /// these, which the app-level observer must ignore so it doesn't treat our
    /// own sign-out as an externally-revoked session.
    @ObservationIgnored private var isPerformingIntentionalSignOut = false

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
        } catch let error as AuthError where error == .networkUnavailable {
            state = .restoreFailedOffline
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

    func signInWithPassword(email: String, password: String) async {
        state = .signingIn(.email)
        do {
            let session = try await service.signInWithPassword(email: email, password: password)
            state = .signedIn(session)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Sets or changes the account password. Throws so the settings sheet can
    /// present the failure inline without disturbing the signed-in state.
    func setPassword(_ password: String) async throws {
        let session = try await service.setPassword(password)
        state = .signedIn(session)
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

    func revokeApple(authorizationCode: String) async throws {
        try await service.revokeApple(authorizationCode: authorizationCode)
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
        isPerformingIntentionalSignOut = true
        defer { isPerformingIntentionalSignOut = false }
        try? await service.signOut()
        state = .failed(AuthError.sessionExpired.localizedDescription)
    }

    /// Called by the app-level `authStateChanges` observer when the SDK reports a
    /// `.signedOut` the app didn't initiate (refresh token revoked, password
    /// changed on another device, admin revoke). Drives the UI to a signed-out
    /// error state instead of leaving a dead session showing the feed.
    func handleExternalSignOut() async {
        guard !isPerformingIntentionalSignOut, isSignedIn else { return }
        await reportSessionExpired()
    }

    func cancelSignIn() {
        switch state {
        case .signingIn, .failed, .restoreFailedOffline:
            state = .signedOut
        default:
            break
        }
    }

    func signOut() async {
        isPerformingIntentionalSignOut = true
        defer { isPerformingIntentionalSignOut = false }
        do {
            try await service.signOut()
        } catch {
            // Local session is cleared best-effort by the service; never strand
            // the user in a failed state over a network blip during sign-out.
        }
        state = .signedOut
    }

    func deleteAccount() async throws {
        isPerformingIntentionalSignOut = true
        defer { isPerformingIntentionalSignOut = false }
        try await service.deleteAccount()
        state = .signedOut
    }
}
