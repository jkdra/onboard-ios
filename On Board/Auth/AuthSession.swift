//
//  AuthSession.swift
//  On Board
//

import Foundation

struct AuthSession: Equatable, Codable, Sendable {
    let userId: UUID
    let provider: AuthProvider
    let email: String?
}
