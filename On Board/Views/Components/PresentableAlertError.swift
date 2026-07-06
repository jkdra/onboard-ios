//
//  PresentableAlertError.swift
//  On Board
//
//  Presents failures through SwiftUI's native `.alert(isPresented:error:)` modifier.
//

import AuthenticationServices
import Foundation
import SwiftUI

/// Conform a domain error enum (AuthError, OnboardingError, BoardServiceError,
/// or any future one) to this and it gets first-class treatment in every alert
/// in the app automatically — PresentableAlertError.init checks for
/// `any PresentableDomainError` once, instead of once per concrete type.
protocol PresentableDomainError: LocalizedError {
    nonisolated var recoverySuggestion: String? { get }
}

struct PresentableAlertError: LocalizedError, Identifiable {
    let id = UUID()
    private let storedDescription: String
    private let storedRecoverySuggestion: String?

    // Errors must stay nonisolated — they're thrown/caught across actor
    // boundaries constantly — but this project defaults new declarations to
    // @MainActor (SWIFT_DEFAULT_ACTOR_ISOLATION), so these need to opt out
    // explicitly to satisfy LocalizedError's nonisolated requirements.
    nonisolated var errorDescription: String? { storedDescription }
    nonisolated var recoverySuggestion: String? { storedRecoverySuggestion }

    /// Returns nil for user cancellation — no alert should be shown.
    static func from(_ error: Error) -> PresentableAlertError? {
        if isCanceled(error) { return nil }
        return PresentableAlertError(error)
    }

    init(_ error: Error) {
        if let apple = error as? ASAuthorizationError {
            let nsError = apple as NSError
            storedDescription = Self.description(for: apple, nsError: nsError)
            storedRecoverySuggestion = nsError.localizedRecoverySuggestion
        } else if let code = Self.appleCode(from: error) {
            let nsError = error as NSError
            storedDescription = Self.description(forCode: code, nsError: nsError)
            storedRecoverySuggestion = nsError.localizedRecoverySuggestion
        } else if let domainError = error as? any PresentableDomainError {
            storedDescription = domainError.localizedDescription
            storedRecoverySuggestion = domainError.recoverySuggestion
        } else if let localized = error as? LocalizedError,
                  let description = localized.errorDescription, !description.isEmpty {
            storedDescription = description
            storedRecoverySuggestion = localized.recoverySuggestion
        } else {
            let text = error.localizedDescription
            storedDescription = text.isEmpty
                ? String(localized: "Something went wrong. Try again.")
                : text
            storedRecoverySuggestion = (error as NSError).localizedRecoverySuggestion
        }
    }

    init(message: String, recoverySuggestion: String? = nil) {
        storedDescription = message
        storedRecoverySuggestion = recoverySuggestion
    }

    // MARK: - Apple authorization

    private static func isCanceled(_ error: Error) -> Bool {
        if let apple = error as? ASAuthorizationError {
            return apple.code == .canceled
        }
        if let code = appleCode(from: error) {
            return code == .canceled
        }
        return false
    }

    private static func appleCode(from error: Error) -> ASAuthorizationError.Code? {
        let ns = error as NSError
        guard ns.domain == ASAuthorizationError.errorDomain else { return nil }
        return ASAuthorizationError.Code(rawValue: ns.code)
    }

    private static func description(for apple: ASAuthorizationError, nsError: NSError) -> String {
        description(forCode: apple.code, nsError: nsError)
    }

    private static func description(forCode code: ASAuthorizationError.Code, nsError: NSError) -> String {
        let appleText = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appleText.isEmpty { return appleText }
        return fallbackMessage(for: code)
    }

    private static func fallbackMessage(for code: ASAuthorizationError.Code) -> String {
        switch code {
        case .canceled:
            return ""
        case .failed:
            return String(localized: "Sign in with Apple failed.")
        case .invalidResponse:
            return String(localized: "Sign in with Apple received an invalid response.")
        case .notHandled:
            return String(localized: "Sign in with Apple could not be completed.")
        case .notInteractive:
            return String(localized: "Sign in with Apple requires the app to be open.")
        case .unknown:
            return String(localized: "Sign in with Apple failed for an unknown reason.")
        case .matchedExcludedCredential:
            return String(localized: "This passkey is already registered.")
        case .credentialImport:
            return String(localized: "The passkey could not be imported.")
        case .credentialExport:
            return String(localized: "The passkey could not be exported.")
        case .preferSignInWithApple:
            return String(localized: "Continue with Sign in with Apple.")
        case .deviceNotConfiguredForPasskeyCreation:
            return String(localized: "This device is not set up to create a passkey.")
        @unknown default:
            return String(localized: "Sign in with Apple failed.")
        }
    }
}

extension AuthError: PresentableDomainError {
    nonisolated var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            String(localized: "Check your connection and try again.")
        case .sessionExpired:
            String(localized: "Sign in again to continue.")
        case .notConfigured:
            String(localized: "Add your Supabase keys to Secrets.xcconfig.")
        default:
            nil
        }
    }
}

extension OnboardingError: PresentableDomainError {
    nonisolated var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            String(localized: "Check your connection and try again.")
        case .sessionExpired, .notAuthenticated:
            String(localized: "Sign in again to continue.")
        case .handleUnavailable:
            String(localized: "Pick a different username.")
        case .invalidHandle:
            String(localized: "Use 2–32 characters: letters, numbers, periods, or underscores.")
        case .invalidSchoolEmail:
            String(localized: "Use your school-issued .edu address.")
        case .schoolUnsupported:
            String(localized: "Try a different .edu email or contact support.")
        case .schoolVerificationIncomplete:
            String(localized: "Enter the code from your verification email.")
        case .profileIncomplete:
            String(localized: "Add a display name to continue.")
        default:
            nil
        }
    }
}

extension BoardServiceError: PresentableDomainError {
    nonisolated var recoverySuggestion: String? {
        switch self {
        case .notAuthenticated, .sessionExpired:
            String(localized: "Sign in again to continue.")
        case .notConfigured:
            String(localized: "Add your Supabase keys to Secrets.xcconfig.")
        case .missingActiveWeek:
            nil
        }
    }
}

extension View {
    func presentableErrorAlert(
        error: Binding<PresentableAlertError?>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        alert(
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        error.wrappedValue = nil
                        onDismiss?()
                    }
                }
            ),
            error: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {
                error.wrappedValue = nil
                onDismiss?()
            }
        } message: { alertError in
            if let recovery = alertError.recoverySuggestion, !recovery.isEmpty {
                Text(recovery)
            }
        }
    }
}
