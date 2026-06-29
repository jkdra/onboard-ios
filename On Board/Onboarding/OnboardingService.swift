//
//  OnboardingService.swift
//  On Board
//

import Foundation

enum OnboardingError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case notAuthenticated
    case handleUnavailable
    case invalidHandle
    case profileIncomplete
    case invalidSchoolEmail
    case schoolUnsupported
    case schoolVerificationIncomplete
    case networkUnavailable
    case sessionExpired
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Onboarding is not configured yet."
        case .notAuthenticated:
            "Sign in to continue onboarding."
        case .handleUnavailable:
            "That username is already taken."
        case .invalidHandle:
            "Usernames must be 2–32 characters and use letters, numbers, periods, or underscores."
        case .profileIncomplete:
            "Add a display name to continue."
        case .invalidSchoolEmail:
            "Use a valid .edu email address."
        case .schoolUnsupported:
            "We don't support that school yet."
        case .schoolVerificationIncomplete:
            "Verify your school email to continue."
        case .networkUnavailable:
            "You're offline. Connect to the internet and try again."
        case .sessionExpired:
            "Your session expired. Sign in again to continue where you left off."
        case .unknown(let message):
            message
        }
    }

}

enum HandleCheckResult: Equatable, Sendable {
    case available
    case taken
    case networkError
}

enum SchoolLookupResult: Equatable, Sendable {
    case matched(SchoolMatch)
    case unsupported
    case networkError
}

protocol OnboardingService: Sendable {
    func fetchStatus() async throws -> OnboardingStatus
    func checkHandleAvailable(_ handle: String) async throws -> Bool
    func completeUsername(_ handle: String) async throws -> OnboardingStep
    func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep
    func lookupSchool(for email: String) async throws -> SchoolMatch?
    func beginSchoolEmailVerification(_ email: String) async throws -> SchoolMatch
    func completeSchoolEmailVerification(_ email: String, token: String) async throws -> OnboardingStep
    func joinWaitlist() async throws -> OnboardingStep
}

enum OnboardingServiceFactory {
    @MainActor
    static func make(configuration: AppConfiguration = .current) -> any OnboardingService {
        if configuration.isSupabaseConfigured {
            SupabaseOnboardingService(configuration: configuration)
        } else {
            MockOnboardingService()
        }
    }
}
