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
    /// True only when a real `email` / `phone` provider identity exists in
    /// `auth.identities` — `email`/`phone` above may be copied from an OAuth
    /// provider and are display-only.
    let hasEmailIdentity: Bool
    let hasPhoneIdentity: Bool
    /// True once the user has set a password (tracked via user metadata —
    /// Supabase doesn't expose password presence directly).
    let hasPassword: Bool
    let linkedIdentities: [LinkedIdentity]

    /// Backward-compatible alias for the primary sign-in provider.
    var provider: AuthProvider { primaryProvider }

    init(
        userId: UUID,
        primaryProvider: AuthProvider,
        email: String? = nil,
        phone: String? = nil,
        hasEmailIdentity: Bool = false,
        hasPhoneIdentity: Bool = false,
        hasPassword: Bool = false,
        linkedIdentities: [LinkedIdentity] = []
    ) {
        self.userId = userId
        self.primaryProvider = primaryProvider
        self.email = email
        self.phone = phone
        self.hasEmailIdentity = hasEmailIdentity
        self.hasPhoneIdentity = hasPhoneIdentity
        self.hasPassword = hasPassword
        self.linkedIdentities = linkedIdentities
    }

    init(
        userId: UUID,
        provider: AuthProvider,
        email: String? = nil,
        phone: String? = nil,
        hasEmailIdentity: Bool = false,
        hasPhoneIdentity: Bool = false,
        linkedIdentities: [LinkedIdentity] = []
    ) {
        self.init(
            userId: userId,
            primaryProvider: provider,
            email: email,
            phone: phone,
            hasEmailIdentity: hasEmailIdentity,
            hasPhoneIdentity: hasPhoneIdentity,
            linkedIdentities: linkedIdentities
        )
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case primaryProvider
        case provider
        case email
        case phone
        case hasEmailIdentity
        case hasPhoneIdentity
        case hasPassword
        case linkedIdentities
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        primaryProvider = try container.decodeIfPresent(AuthProvider.self, forKey: .primaryProvider)
            ?? container.decode(AuthProvider.self, forKey: .provider)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        hasEmailIdentity = try container.decodeIfPresent(Bool.self, forKey: .hasEmailIdentity) ?? false
        hasPhoneIdentity = try container.decodeIfPresent(Bool.self, forKey: .hasPhoneIdentity) ?? false
        hasPassword = try container.decodeIfPresent(Bool.self, forKey: .hasPassword) ?? false
        linkedIdentities = try container.decodeIfPresent([LinkedIdentity].self, forKey: .linkedIdentities) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(primaryProvider, forKey: .primaryProvider)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encode(hasEmailIdentity, forKey: .hasEmailIdentity)
        try container.encode(hasPhoneIdentity, forKey: .hasPhoneIdentity)
        try container.encode(hasPassword, forKey: .hasPassword)
        try container.encode(linkedIdentities, forKey: .linkedIdentities)
    }
}
