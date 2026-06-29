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
        guard !normalizedName.isEmpty else {
            throw OnboardingError.profileIncomplete
        }

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

    func beginSchoolEmailVerification(_ email: String) async throws -> SchoolMatch {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard SchoolEmailRules.isValid(normalized) else {
            throw OnboardingError.invalidSchoolEmail
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

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = Self.match(for: normalized) else {
            throw OnboardingError.schoolUnsupported
        }

        var status = loadStatus(for: userID)
        guard status.pendingSchoolEmail?.lowercased() == normalized else {
            throw OnboardingError.schoolVerificationIncomplete
        }

        status = OnboardingStatus(
            id: status.id,
            handle: status.handle,
            displayName: status.displayName,
            bio: status.bio,
            avatarUrl: status.avatarUrl,
            onboardingStep: .waitlist,
            onboardingCompletedAt: status.onboardingCompletedAt,
            waitlistJoinedAt: status.waitlistJoinedAt,
            verifiedSchoolEmail: normalized,
            pendingSchoolEmail: nil,
            schoolName: match.schoolName,
            boardId: match.boardId,
            boardName: match.boardName
        )
        save(status, for: userID)
        return .waitlist
    }

    func joinWaitlist() async throws -> OnboardingStep {
        try await Task.sleep(for: .milliseconds(180))
        guard let userID = MockOnboardingService.currentUserID(from: defaults) else {
            throw OnboardingError.notAuthenticated
        }

        var status = loadStatus(for: userID)
        status = status.updating(
            onboardingStep: .complete,
            onboardingCompletedAt: status.onboardingCompletedAt ?? .now,
            waitlistJoinedAt: status.waitlistJoinedAt ?? .now
        )
        save(status, for: userID)
        return .complete
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
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                onboardingStep: .complete,
                onboardingCompletedAt: profile.joinedAt,
                waitlistJoinedAt: profile.joinedAt,
                verifiedSchoolEmail: "student@example.edu",
                pendingSchoolEmail: nil,
                schoolName: "Example University",
                boardId: SampleBoardID.main,
                boardName: "On Board"
            )
        }

        return OnboardingStatus(
            id: userID,
            handle: "u_\(userID.uuidString.prefix(12).replacingOccurrences(of: "-", with: "").lowercased())",
            displayName: "New member",
            bio: nil,
            avatarUrl: nil,
            onboardingStep: .username,
            onboardingCompletedAt: nil,
            waitlistJoinedAt: nil,
            verifiedSchoolEmail: nil,
            pendingSchoolEmail: nil,
            schoolName: nil,
            boardId: nil,
            boardName: nil
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
            onboardingStep: onboardingStep ?? self.onboardingStep,
            onboardingCompletedAt: onboardingCompletedAt ?? self.onboardingCompletedAt,
            waitlistJoinedAt: waitlistJoinedAt ?? self.waitlistJoinedAt,
            verifiedSchoolEmail: verifiedSchoolEmail ?? self.verifiedSchoolEmail,
            pendingSchoolEmail: pendingSchoolEmail ?? self.pendingSchoolEmail,
            schoolName: schoolName ?? self.schoolName,
            boardId: boardId ?? self.boardId,
            boardName: boardName ?? self.boardName
        )
    }
}
