//
//  AuthError.swift
//  On Board
//

import Foundation

enum AuthError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case cancelled
    case providerUnavailable(AuthProvider)
    case sessionRestoreFailed
    case sessionExpired
    case networkUnavailable
    case accountDeletionFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Sign-in is not configured yet. Copy Secrets.xcconfig.example to Secrets.xcconfig and add your Supabase keys."
        case .cancelled:
            "Sign-in was cancelled."
        case .providerUnavailable(let provider):
            "\(provider.label) sign-in is not available right now."
        case .sessionRestoreFailed:
            "Could not restore your previous session."
        case .sessionExpired:
            "Your session expired. Sign in again to continue where you left off."
        case .networkUnavailable:
            "You're offline. Connect to the internet and try again."
        case .accountDeletionFailed(let message):
            message
        case .unknown(let message):
            message
        }
    }
}
