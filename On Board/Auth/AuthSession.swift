//
//  AuthSession.swift
//  On Board
//

import Foundation

struct AuthSession: Equatable, Codable, Sendable {
    let userId: UUID
    let primaryProvider: AuthProvider
    let email: String?
    let phone: String?
    let linkedIdentities: [LinkedIdentity]

    /// Backward-compatible alias for the primary sign-in provider.
    var provider: AuthProvider { primaryProvider }

    init(
        userId: UUID,
        primaryProvider: AuthProvider,
        email: String? = nil,
        phone: String? = nil,
        linkedIdentities: [LinkedIdentity] = []
    ) {
        self.userId = userId
        self.primaryProvider = primaryProvider
        self.email = email
        self.phone = phone
        self.linkedIdentities = linkedIdentities
    }

    init(
        userId: UUID,
        provider: AuthProvider,
        email: String? = nil,
        phone: String? = nil,
        linkedIdentities: [LinkedIdentity] = []
    ) {
        self.init(
            userId: userId,
            primaryProvider: provider,
            email: email,
            phone: phone,
            linkedIdentities: linkedIdentities
        )
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case primaryProvider
        case provider
        case email
        case phone
        case linkedIdentities
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        primaryProvider = try container.decodeIfPresent(AuthProvider.self, forKey: .primaryProvider)
            ?? container.decode(AuthProvider.self, forKey: .provider)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        linkedIdentities = try container.decodeIfPresent([LinkedIdentity].self, forKey: .linkedIdentities) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(primaryProvider, forKey: .primaryProvider)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encode(linkedIdentities, forKey: .linkedIdentities)
    }
}
