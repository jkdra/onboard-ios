//
//  AuthState.swift
//  On Board
//

import Foundation

enum AuthState: Equatable, Sendable {
    case signedOut
    case signingIn(AuthProvider)
    case signedIn(AuthSession)
    /// A session exists locally but couldn't be verified because the network is
    /// unreachable. RootView shows OfflineGateView and retries on reconnect.
    case restoreFailedOffline
    case failed(String)

    var session: AuthSession? {
        if case .signedIn(let session) = self { return session }
        return nil
    }

    var isSignedIn: Bool {
        session != nil
    }
}
