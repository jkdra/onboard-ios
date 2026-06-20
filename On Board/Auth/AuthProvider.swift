//
//  AuthProvider.swift
//  On Board
//

import Foundation

enum AuthProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case google
    case phone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .phone: "Phone"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .google: "g.circle.fill"
        case .phone: "phone.fill"
        }
    }

    var securityLabel: String {
        switch self {
        case .apple: "Sign in with Apple"
        case .google: "Google"
        case .phone: "Phone number"
        }
    }

    /// Providers shown on the primary sign-in screen.
    static var signInOptions: [AuthProvider] {
        [.phone, .apple, .google]
    }
}
