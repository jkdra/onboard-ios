//
//  SupabaseOnboardingService.swift
//  On Board
//

import Foundation
import Supabase

final class SupabaseOnboardingService: OnboardingService, @unchecked Sendable {
    private let client: SupabaseClient?

    init(configuration: AppConfiguration) {
        self.client = SupabaseClientFactory.client(for: configuration)
    }

    func fetchStatus() async throws -> OnboardingStatus {
        let client = try requireClient()
        let rows: [OnboardingStatus] = try await client
            .rpc("get_onboarding_status")
            .execute()
            .value

        guard let status = rows.first else {
            throw OnboardingError.notAuthenticated
        }
        return status
    }

    func completeBirthday(birthday: Date, showBirthday: Bool) async throws -> OnboardingStep {
        let client = try requireClient()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // We want to extract the selected YYYY-MM-DD exactly as the user chose it on their device,
        // without time zone conversions shifting the day. The DatePicker uses the user's local timezone.
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: birthday)
        
        struct Params: Encodable {
            let pBirthday: String
            let pShowBirthday: Bool
        }
        
        do {
            let step: OnboardingStep = try await client
                .rpc(
                    "complete_onboarding_birthday",
                    params: Params(pBirthday: dateString, pShowBirthday: showBirthday)
                )
                .execute()
                .value
            return step
        } catch {
            if let postgrestError = error as? PostgrestError,
               postgrestError.message.contains("16 years old") {
                throw OnboardingError.unknown("You must be at least 16 years old to use On Board.")
            }
            throw error
        }
    }

    func checkHandleAvailable(_ handle: String) async throws -> Bool {
        let normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HandleRules.isValid(normalized) else { return false }

        let client = try requireClient()
        return try await client
            .rpc("check_handle_available", params: ["p_handle": normalized])
            .execute()
            .value
    }

    func completeUsername(_ handle: String) async throws -> OnboardingStep {
        let normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HandleRules.isValid(normalized) else {
            throw OnboardingError.invalidHandle
        }

        let client = try requireClient()
        let step: OnboardingStep = try await client
            .rpc("complete_onboarding_username", params: ["p_handle": normalized])
            .execute()
            .value
        return step
    }

    func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw OnboardingError.profileIncomplete
        }

        struct Params: Encodable {
            let pDisplayName: String
            let pBio: String?
            let pAvatarUrl: String?
        }

        let client = try requireClient()
        let step: OnboardingStep = try await client
            .rpc(
                "complete_onboarding_profile",
                params: Params(
                    pDisplayName: normalizedName,
                    pBio: bio?.trimmingCharacters(in: .whitespacesAndNewlines),
                    pAvatarUrl: avatarUrl
                )
            )
            .execute()
            .value
        return step
    }

    func joinWaitlist() async throws -> OnboardingStep {
        let client = try requireClient()
        let step: OnboardingStep = try await client
            .rpc("join_waitlist")
            .execute()
            .value
        return step
    }

    func lookupSchool(for email: String) async throws -> SchoolMatch? {
        let normalized = EmailNormalizer.normalized(email)
        guard SchoolEmailRules.isValid(normalized) else { return nil }

        let client = try requireClient()
        let rows: [SchoolMatch] = try await client
            .rpc("lookup_school_for_email", params: ["p_email": normalized])
            .execute()
            .value
        return rows.first
    }

    func beginSchoolEmailVerification(_ email: String) async throws -> SchoolMatch {
        let normalized = EmailNormalizer.normalized(email)
        guard SchoolEmailRules.isValid(normalized) else {
            throw OnboardingError.invalidSchoolEmail
        }
        let client = try requireClient()
        do {
            let match: SchoolMatch = try await client.functions.invoke(
                "send-school-otp",
                options: FunctionInvokeOptions(body: ["email": normalized]),
                decoder: BoardJSON.decoder
            )
            return match
        } catch let error as FunctionsError {
            if case .httpError(let code, _) = error {
                switch code {
                case 400: throw OnboardingError.invalidSchoolEmail
                case 422: throw OnboardingError.schoolUnsupported
                default: break
                }
            }
            throw OnboardingError.unknown(error.localizedDescription)
        }
    }

    func completeSchoolEmailVerification(_ email: String, token: String) async throws -> OnboardingStep {
        let normalized = EmailNormalizer.normalized(email)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = try requireClient()
        let step: OnboardingStep = try await client
            .rpc("complete_school_email_verification_v2", params: [
                "p_email": normalized,
                "p_token": trimmedToken
            ])
            .execute()
            .value
        return step
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw OnboardingError.notConfigured }
        return client
    }
}
