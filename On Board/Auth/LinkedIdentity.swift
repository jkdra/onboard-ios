//
//  LinkedIdentity.swift
//  On Board
//

import Foundation

struct LinkedIdentity: Equatable, Codable, Identifiable, Sendable {
    let id: String
    let provider: AuthProvider
    let email: String?

    init(id: String, provider: AuthProvider, email: String?) {
        self.id = id
        self.provider = provider
        self.email = email
    }
}

extension LinkedIdentity {
    static func fromSupabaseProvider(_ provider: String, id: String, email: String?) -> LinkedIdentity? {
        guard let authProvider = AuthProvider(supabaseProvider: provider) else { return nil }
        guard authProvider == .apple || authProvider == .google else { return nil }
        return LinkedIdentity(id: id, provider: authProvider, email: email)
    }
}
