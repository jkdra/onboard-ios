//
//  AuthProvider.swift
//  On Board
//

import Foundation

enum AuthProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case google
    case phone
    case email

    var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .phone: "Phone"
        case .email: "Email"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .google: "g.circle.fill"
        case .phone: "phone.fill"
        case .email: "envelope.fill"
        }
    }

    var securityLabel: String {
        switch self {
        case .apple: "Sign in with Apple"
        case .google: "Google"
        case .phone: "Phone number"
        case .email: "Email"
        }
    }

    /// Providers shown on the primary sign-in screen (phone is default; email is a secondary toggle).
    static var signInOptions: [AuthProvider] {
        [.phone, .email, .apple, .google]
    }

    /// OAuth providers that can be linked or unlinked in account settings.
    static var linkableOAuthProviders: [AuthProvider] {
        [.apple, .google]
    }

    init?(supabaseProvider: String) {
        switch supabaseProvider.lowercased() {
        case "apple": self = .apple
        case "google": self = .google
        case "phone": self = .phone
        case "email": self = .email
        default: return nil
        }
    }
}
