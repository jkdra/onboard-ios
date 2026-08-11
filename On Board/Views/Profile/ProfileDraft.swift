//
//  ProfileDraft.swift
//  On Board
//
//  Edit-mode working state for ProfileView, pulled out of the view so the
//  validation rules and the debounced handle-availability check are plain,
//  testable logic instead of view plumbing. The view owns one instance and
//  hands it to ProfileEditContent via @Bindable.
//

import Foundation
import Observation
import PhotosUI
import SwiftUI

@Observable
@MainActor
final class ProfileDraft {
    /// Compiled defaults. Instance copies below are what `canSave` reads, so a
    /// remote override can raise or lower the limit without a build.
    static let displayNameLimit = 50
    static let bioLimit = 300

    /// Set from `RemoteConfig` by the owning view. `ProfileDraft` is an
    /// `@Observable` model rather than a `View`, so it can't read the
    /// environment itself — the limits are handed to it instead.
    var displayNameLimit = ProfileDraft.displayNameLimit
    var bioLimit = ProfileDraft.bioLimit

    enum HandleAvailability: Equatable {
        case idle
        case checking
        case available
        case unavailable
        case invalid
        case offline
    }

    var displayName = ""
    var handle = ""
    var bio = ""
    /// The profile's existing avatar URL, until `photo.uploadedURL` replaces
    /// it — same relationship as PostDetailView's `draftImageUrl`/`editPhoto`.
    var avatarUrl: String?
    var birthday: Date?
    var showBirthday = false
    var photo = PhotoAttachmentController(type: .profilePicture)
    var handleAvailability: HandleAvailability = .idle

    private var originalHandle = ""
    private var handleCheckTask: Task<Void, Never>?
    private var checkAvailability: ((String) async -> HandleCheckResult)?

    // yyyy-MM-dd, matching the profiles.birthday column and the onboarding
    // step's encoding — POSIX locale so a device's regional calendar can't
    // shift the parse.
    static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var birthdayString: String? {
        birthday.map { Self.birthdayFormatter.string(from: $0) }
    }

    var canSave: Bool {
        displayName.count <= displayNameLimit
            && bio.count <= bioLimit
            && HandleRules.isValid(handle.trimmed)
            && handleAvailability == .available
            && birthday != nil
    }

    func begin(
        from profile: Profile,
        checkAvailability: @escaping (String) async -> HandleCheckResult
    ) {
        displayName = profile.displayName
        handle = profile.handle
        originalHandle = profile.handle
        // Your own current handle is always valid/available — no need to
        // round-trip a check before the user has actually changed anything.
        handleAvailability = .available
        bio = profile.bio ?? ""
        avatarUrl = profile.avatarUrl
        birthday = profile.birthday.flatMap { Self.birthdayFormatter.date(from: $0) }
        showBirthday = profile.showBirthday
        photo.reset()
        self.checkAvailability = checkAvailability
    }

    func cancel() {
        handleCheckTask?.cancel()
        photo.reset()
        // Harmless: ProfileReadContent reads the store's profile, not
        // draft.avatarUrl, and begin() re-seeds this from the real profile on
        // the next edit — this just leaves nothing stale on the draft itself.
        avatarUrl = nil
    }

    func scheduleHandleAvailabilityCheck() {
        handleCheckTask?.cancel()
        let candidate = handle.trimmed

        if candidate == originalHandle {
            handleAvailability = .available
            return
        }

        guard !candidate.isEmpty, HandleRules.isValid(candidate) else {
            handleAvailability = .invalid
            return
        }

        handleAvailability = .checking
        handleCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let checkAvailability else { return }

            let result = await checkAvailability(candidate)
            guard !Task.isCancelled, handle.trimmed == candidate else { return }
            switch result {
            case .available: handleAvailability = .available
            case .taken: handleAvailability = .unavailable
            case .networkError: handleAvailability = .offline
            }
        }
    }
}
