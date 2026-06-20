//
//  AuthState.swift
//  On Board
//

import Foundation

enum AuthState: Equatable, Sendable {
    case signedOut
    case signingIn(AuthProvider)
    case signedIn(AuthSession)
    case failed(String)

    var session: AuthSession? {
        if case .signedIn(let session) = self { return session }
        return nil
    }

    var isSignedIn: Bool {
        session != nil
    }
}
