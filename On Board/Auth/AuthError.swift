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
    case cannotUnlinkLastSignInMethod
    case identityAlreadyLinked(AuthProvider)
    case invalidPhoneNumber
    case unknown(String)

    nonisolated var errorDescription: String? {
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
        case .cannotUnlinkLastSignInMethod:
            "Add a phone number, email, or another sign-in method before removing this one. You can also delete your account from Account Management."
        case .identityAlreadyLinked(let provider):
            "\(provider.label) is already linked to your account."
        case .invalidPhoneNumber:
            "Enter a valid phone number with country code, e.g. +1 555 555 0100."
        case .unknown(let message):
            message
        }
    }
}
