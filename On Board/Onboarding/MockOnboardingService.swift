//
//  MockOnboardingService.swift
//  On Board
//

import Foundation

final class MockOnboardingService: OnboardingService, @unchecked Sendable {
    private let defaults: UserDefaults
    private let statusKeyPrefix = "mock.onboarding.status."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func fetchStatus() async throws -> OnboardingStatus {
        try await Task.sleep(for: .milliseconds(150))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }
        return loadStatus(for: userID)
    }

    func checkHandleAvailable(_ handle: String) async throws -> Bool {
        try await Task.sleep(for: .milliseconds(120))
        let normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HandleRules.isValid(normalized) else { return false }

        let reserved = Set(Profile.samples.map(\.handle).map { $0.lowercased() })
        return !reserved.contains(normalized.lowercased())
    }

    func completeBirthday(birthday: Date, showBirthday: Bool) async throws -> OnboardingStep {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let minAgeDate = Calendar.current.date(byAdding: .year, value: -16, to: Date())!
        if birthday > minAgeDate {
            throw OnboardingError.unknown("You must be at least 16 years old to use On Board.")
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: birthday)

        var status = loadStatus(for: userID)
        status = status.updating(
            birthday: dateString,
            showBirthday: showBirthday,
            onboardingStep: .username
        )
        save(status, for: userID)
        return .username
    }

    func completeUsername(_ handle: String) async throws -> OnboardingStep {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HandleRules.isValid(normalized) else {
            throw OnboardingError.invalidHandle
        }
        guard try await checkHandleAvailable(normalized) else {
            throw OnboardingError.handleUnavailable
        }

        var status = loadStatus(for: userID)
        status = status.updating(
            handle: normalized,
            onboardingStep: .profile
        )
        save(status, for: userID)
        return .profile
    }

    func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        var status = loadStatus(for: userID)
        status = status.updating(
            displayName: normalizedName,
            bio: bio?.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarUrl: avatarUrl,
            onboardingStep: .schoolVerify
        )
        save(status, for: userID)
        return .schoolVerify
    }

    func lookupSchool(for email: String) async throws -> SchoolMatch? {
        try await Task.sleep(for: .milliseconds(120))
        return Self.match(for: email)
    }

    func checkSchoolEmailAvailable(_ email: String) async throws -> Bool {
        try await Task.sleep(for: .milliseconds(120))
        // Same convention as beginSchoolEmailVerification's in-use guard: a
        // local part starting with "taken" simulates a registered email.
        return !EmailNormalizer.normalized(email).hasPrefix("taken")
    }

    func beginSchoolEmailVerification(_ email: String) async throws -> SchoolMatch {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let normalized = EmailNormalizer.normalized(email)
        guard SchoolEmailRules.isValid(normalized) else {
            throw OnboardingError.invalidSchoolEmail
        }
        // Mirrors the live one-account-per-email guard: any local part starting
        // with "taken" simulates an email another profile already verified.
        if normalized.hasPrefix("taken") {
            throw OnboardingError.schoolEmailInUse
        }
        guard let match = Self.match(for: normalized) else {
            throw OnboardingError.schoolUnsupported
        }

        var status = loadStatus(for: userID)
        status = status.updating(
            onboardingStep: .schoolVerify,
            pendingSchoolEmail: normalized,
            schoolName: match.schoolName,
            boardId: match.boardId,
            boardName: match.boardName
        )
        save(status, for: userID)
        return match
    }

    func completeSchoolEmailVerification(_ email: String, token: String) async throws -> OnboardingStep {
        _ = token  // OTP not validated in mock; any code succeeds
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let normalized = EmailNormalizer.normalized(email)
        guard let match = Self.match(for: normalized) else {
            throw OnboardingError.schoolUnsupported
        }

        var status = loadStatus(for: userID)
        guard status.pendingSchoolEmail?.lowercased() == normalized else {
            throw OnboardingError.schoolVerificationIncomplete
        }

        // A local part starting with "vip" simulates a golden-ticket instant
        // admission (live complete_v2 admits instantly when the referrer is
        // admitted with quota) — lands on the board, fires the welcome flow.
        let instantlyAdmitted = normalized.hasPrefix("vip")

        status = OnboardingStatus(
            id: status.id,
            handle: status.handle,
            displayName: status.displayName,
            bio: status.bio,
            avatarUrl: status.avatarUrl,
            birthday: status.birthday,
            showBirthday: status.showBirthday,
            onboardingStep: instantlyAdmitted ? .complete : .waitlist,
            onboardingCompletedAt: instantlyAdmitted ? .now : status.onboardingCompletedAt,
            // Verifying your .edu is what puts you on the waitlist — mirrors the live
            // complete_school_email_verification_v2 RPC, which inserts the waitlist
            // row here. So waitlistJoinedAt is set at verify time, not on a separate
            // "join" tap (there no longer is one — the waitlist screen just confirms).
            waitlistJoinedAt: status.waitlistJoinedAt ?? .now,
            verifiedSchoolEmail: normalized,
            pendingSchoolEmail: nil,
            schoolName: match.schoolName,
            boardId: match.boardId,
            boardName: match.boardName,
            referralCode: status.referralCode,
            verifiedReferralCount: status.verifiedReferralCount,
            instantInvitesRemaining: status.instantInvitesRemaining
        )
        save(status, for: userID)
        return instantlyAdmitted ? .complete : .waitlist
    }

    func joinWaitlist() async throws -> OnboardingStep {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        var status = loadStatus(for: userID)
        status = status.updating(
            onboardingStep: .waitlist,
            waitlistJoinedAt: status.waitlistJoinedAt ?? .now
        )
        save(status, for: userID)
        return .waitlist
    }

    func submitReferralCode(_ code: String) async throws {
        try await Task.sleep(for: .milliseconds(180))
    }

    /// Dev-only lever for the waitlist screen's "Join Board [DEV]" button:
    /// admits the current mock user on the spot, mirroring what an admin
    /// approval does to the live status. Exercises the first-time welcome flow
    /// without needing the vip@ email convention.
    func devAdmitCurrentUser() {
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else { return }
        var status = loadStatus(for: userID)
        status = status.updating(
            onboardingStep: .complete,
            onboardingCompletedAt: .now,
            boardId: SampleBoardID.main,
            boardName: "On Board"
        )
        save(status, for: userID)
    }

    private func loadStatus(for userID: UUID) -> OnboardingStatus {
        let key = statusKeyPrefix + userID.uuidString
        if let data = defaults.data(forKey: key),
           let status = try? BoardJSON.decoder.decode(OnboardingStatus.self, from: data) {
            return status
        }
        return Self.defaultStatus(for: userID)
    }

    private func save(_ status: OnboardingStatus, for userID: UUID) {
        let key = statusKeyPrefix + userID.uuidString
        guard let data = try? BoardJSON.encoder.encode(status) else { return }
        defaults.set(data, forKey: key)
    }

    private static func match(for email: String) -> SchoolMatch? {
        let normalized = EmailNormalizer.normalized(email)
        guard SchoolEmailRules.isValid(normalized),
              normalized.hasSuffix("@example.edu") else {
            return nil
        }

        return SchoolMatch(
            domain: "example.edu",
            schoolName: "Example University",
            boardId: SampleBoardID.main,
            boardName: "On Board"
        )
    }

    private static func defaultStatus(for userID: UUID) -> OnboardingStatus {
        if userID == SampleProfileID.maya || userID == SampleProfileID.leo,
           let profile = Profile.samples.first(where: { $0.id == userID }) {
            return OnboardingStatus(
                id: userID,
                handle: profile.handle,
                displayName: profile.displayName,
                bio: profile.bio,
                avatarUrl: profile.avatarUrl,
                birthday: profile.birthday,
                showBirthday: profile.showBirthday,
                onboardingStep: .complete,
                onboardingCompletedAt: profile.joinedAt,
                waitlistJoinedAt: profile.joinedAt,
                verifiedSchoolEmail: "student@example.edu",
                pendingSchoolEmail: nil,
                schoolName: "Example University",
                boardId: SampleBoardID.main,
                boardName: "On Board",
                referralCode: "maya123",
                verifiedReferralCount: 5,
                instantInvitesRemaining: 3
            )
        }

        return OnboardingStatus(
            id: userID,
            handle: "u_\(userID.uuidString.prefix(12).replacingOccurrences(of: "-", with: "").lowercased())",
            displayName: "",
            bio: nil,
            avatarUrl: nil,
            birthday: nil,
            showBirthday: nil,
            onboardingStep: .birthday,
            onboardingCompletedAt: nil,
            waitlistJoinedAt: nil,
            verifiedSchoolEmail: nil,
            pendingSchoolEmail: nil,
            schoolName: nil,
            boardId: nil,
            boardName: nil,
            referralCode: "newuser1",
            verifiedReferralCount: 0,
            instantInvitesRemaining: 3
        )
    }

    private static func currentUserID(from defaults: UserDefaults) -> UUID? {
        guard let data = defaults.data(forKey: "mock.auth.session"),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return nil
        }
        return session.userId
    }
}

private extension OnboardingStatus {
    func updating(
        handle: String? = nil,
        displayName: String? = nil,
        bio: String?? = nil,
        avatarUrl: String?? = nil,
        birthday: String?? = nil,
        showBirthday: Bool?? = nil,
        onboardingStep: OnboardingStep? = nil,
        onboardingCompletedAt: Date?? = nil,
        waitlistJoinedAt: Date?? = nil,
        verifiedSchoolEmail: String?? = nil,
        pendingSchoolEmail: String?? = nil,
        schoolName: String?? = nil,
        boardId: UUID?? = nil,
        boardName: String?? = nil
    ) -> OnboardingStatus {
        OnboardingStatus(
            id: id,
            handle: handle ?? self.handle,
            displayName: displayName ?? self.displayName,
            bio: bio ?? self.bio,
            avatarUrl: avatarUrl ?? self.avatarUrl,
            birthday: birthday ?? self.birthday,
            showBirthday: showBirthday ?? self.showBirthday,
            onboardingStep: onboardingStep ?? self.onboardingStep,
            onboardingCompletedAt: onboardingCompletedAt ?? self.onboardingCompletedAt,
            waitlistJoinedAt: waitlistJoinedAt ?? self.waitlistJoinedAt,
            verifiedSchoolEmail: verifiedSchoolEmail ?? self.verifiedSchoolEmail,
            pendingSchoolEmail: pendingSchoolEmail ?? self.pendingSchoolEmail,
            schoolName: schoolName ?? self.schoolName,
            boardId: boardId ?? self.boardId,
            boardName: boardName ?? self.boardName,
            referralCode: self.referralCode,
            verifiedReferralCount: self.verifiedReferralCount,
            instantInvitesRemaining: self.instantInvitesRemaining
        )
    }
}
