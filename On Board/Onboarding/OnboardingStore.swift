//
//  OnboardingStore.swift
//  On Board
//

import Foundation
import Observation

@Observable
@MainActor
final class OnboardingStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var status: OnboardingStatus?
    private(set) var isSubmitting = false
    private(set) var lastError: String?
    private(set) var lastErrorRecovery: String?
    /// Set when refresh failed but cached onboarding status is still shown.
    private(set) var syncFailure: String?

    private let service: any OnboardingService
    private let auth: AuthStore
    private let network: NetworkMonitor
    private var lastSyncedUserID: UUID?

    var isLoading: Bool { loadState == .loading }
    var hasResolvedStatus: Bool { status != nil }
    var isComplete: Bool { status?.needsOnboarding == false }
    var needsOnboarding: Bool {
        guard let status else { return false }
        return status.needsOnboarding
    }

    init(service: any OnboardingService, auth: AuthStore, network: NetworkMonitor) {
        self.service = service
        self.auth = auth
        self.network = network
    }

    func reset() {
        if let userID = lastSyncedUserID ?? auth.session?.userId {
            OnboardingStatusCache.clear(for: userID)
        }
        lastSyncedUserID = nil
        loadState = .idle
        status = nil
        isSubmitting = false
        lastError = nil
        lastErrorRecovery = nil
        syncFailure = nil
    }

    func clearLastError() {
        lastError = nil
        lastErrorRecovery = nil
    }

    func refresh() async {
        await refresh(force: true)
    }

    func refreshIfOnline() async {
        await refresh(force: false)
    }

    private func refresh(force: Bool) async {
        guard auth.isSignedIn, let userID = auth.session?.userId else {
            loadState = .idle
            status = nil
            return
        }

        if requiresNetwork, !network.isConnected {
            if let cached = OnboardingStatusCache.load(for: userID) {
                status = cached
                loadState = .loaded
                syncFailure = OnboardingError.networkUnavailable.localizedDescription
            } else {
                loadState = .failed(OnboardingError.networkUnavailable.localizedDescription)
                lastError = OnboardingError.networkUnavailable.localizedDescription
            }
            return
        }

        let userChanged = lastSyncedUserID != userID
        if userChanged {
            lastSyncedUserID = userID
            status = nil
            loadState = .idle
        }

        if !force, !userChanged, loadState == .loaded, status != nil {
            return
        }

        loadState = .loading
        lastError = nil
        lastErrorRecovery = nil
        syncFailure = nil

        do {
            let fetched = try await service.fetchStatus()
            status = fetched
            OnboardingStatusCache.save(fetched, for: userID)
            loadState = .loaded
        } catch let error as OnboardingError where error == .notAuthenticated {
            await auth.reportSessionExpired()
            reset()
        } catch let error as OnboardingError {
            applyRefreshFailure(error.localizedDescription, userID: userID)
        } catch {
            applyRefreshFailure(error.localizedDescription, userID: userID)
        }
    }

    func checkHandleAvailable(_ handle: String) async -> HandleCheckResult {
        if requiresNetwork, !network.isConnected {
            return .networkError
        }

        do {
            let isAvailable = try await service.checkHandleAvailable(handle)
            return isAvailable ? .available : .taken
        } catch {
            if NetworkErrorClassifier.isConnectivityFailure(error) {
                return .networkError
            }
            return .taken
        }
    }

    func lookupSchool(for email: String) async -> SchoolLookupResult {
        if requiresNetwork, !network.isConnected {
            return .networkError
        }

        do {
            guard let match = try await service.lookupSchool(for: email) else {
                return .unsupported
            }
            return .matched(match)
        } catch {
            if NetworkErrorClassifier.isConnectivityFailure(error) {
                return .networkError
            }
            return .unsupported
        }
    }

    @discardableResult
    func submitUsername(_ handle: String) async -> Bool {
        guard ensureOnlineForSubmit() else { return false }

        isSubmitting = true
        clearLastError()
        defer { isSubmitting = false }

        do {
            _ = try await service.completeUsername(handle)
            await refresh(force: true)
            return status?.onboardingStep != .username
        } catch let error as OnboardingError where error == .notAuthenticated {
            await auth.reportSessionExpired()
            reset()
            return false
        } catch let error as OnboardingError {
            setLastError(error)
            return false
        } catch {
            let failure = friendlySubmitFailure(error)
            setLastError(message: failure.message, recovery: failure.recovery)
            return false
        }
    }

    @discardableResult
    func submitProfile(displayName: String, bio: String?, avatarUrl: String? = nil) async -> Bool {
        guard ensureOnlineForSubmit() else { return false }

        isSubmitting = true
        clearLastError()
        defer { isSubmitting = false }

        do {
            _ = try await service.completeProfile(
                displayName: displayName,
                bio: bio,
                avatarUrl: avatarUrl
            )
            await refresh(force: true)
            return status?.onboardingStep == .schoolVerify
                || status?.onboardingStep == .waitlist
                || status?.isComplete == true
        } catch let error as OnboardingError where error == .notAuthenticated {
            await auth.reportSessionExpired()
            reset()
            return false
        } catch let error as OnboardingError {
            setLastError(error)
            return false
        } catch {
            let failure = friendlySubmitFailure(error)
            setLastError(message: failure.message, recovery: failure.recovery)
            return false
        }
    }

    @discardableResult
    func sendSchoolVerificationCode(to email: String) async -> Bool {
        guard ensureOnlineForSubmit() else { return false }

        isSubmitting = true
        clearLastError()
        defer { isSubmitting = false }

        do {
            _ = try await service.beginSchoolEmailVerification(email)
            do {
                try await auth.sendSchoolEmailVerification(to: email)
            } catch {
                setLastError(
                    message: """
                    Your school was saved, but the verification email could not be sent. \
                    Tap send again to retry.
                    """,
                    recovery: String(localized: "Tap send again to retry.")
                )
                return false
            }
            await refresh(force: true)
            return true
        } catch let error as OnboardingError where error == .notAuthenticated {
            await auth.reportSessionExpired()
            reset()
            return false
        } catch let error as OnboardingError {
            setLastError(error)
            return false
        } catch {
            let failure = friendlySubmitFailure(error)
            setLastError(message: failure.message, recovery: failure.recovery)
            return false
        }
    }

    @discardableResult
    func verifySchoolEmail(_ email: String, code: String) async -> Bool {
        guard ensureOnlineForSubmit() else { return false }

        isSubmitting = true
        clearLastError()
        defer { isSubmitting = false }

        do {
            try await auth.verifySchoolEmailOTP(email: email, token: code)
            do {
                _ = try await service.completeSchoolEmailVerification(email)
            } catch {
                setLastError(
                    message: """
                    Your email was verified, but we couldn't finish linking your school. \
                    Try again — your code may still work if you resend.
                    """,
                    recovery: String(localized: "Try again, or resend the verification code.")
                )
                await refresh(force: true)
                return false
            }
            await refresh(force: true)
            return status?.onboardingStep == .waitlist || status?.isComplete == true
        } catch let error as OnboardingError where error == .notAuthenticated {
            await auth.reportSessionExpired()
            reset()
            return false
        } catch let error as OnboardingError {
            setLastError(error)
            return false
        } catch {
            let failure = friendlySubmitFailure(error)
            setLastError(message: failure.message, recovery: failure.recovery)
            return false
        }
    }

    @discardableResult
    func joinWaitlist() async -> Bool {
        guard ensureOnlineForSubmit() else { return false }

        isSubmitting = true
        clearLastError()
        defer { isSubmitting = false }

        do {
            _ = try await service.joinWaitlist()
            await refresh(force: true)
            return status?.isComplete == true
        } catch let error as OnboardingError where error == .notAuthenticated {
            await auth.reportSessionExpired()
            reset()
            return false
        } catch let error as OnboardingError {
            setLastError(error)
            return false
        } catch {
            let failure = friendlySubmitFailure(error)
            setLastError(message: failure.message, recovery: failure.recovery)
            return false
        }
    }

    // MARK: - Private

    private var requiresNetwork: Bool {
        AppConfiguration.current.isSupabaseConfigured
    }

    private func ensureOnlineForSubmit() -> Bool {
        guard requiresNetwork else { return true }
        guard network.isConnected else {
            setLastError(.networkUnavailable)
            return false
        }
        return true
    }

    private func setLastError(_ error: OnboardingError) {
        lastError = error.localizedDescription
        lastErrorRecovery = error.recoverySuggestion
    }

    private func setLastError(message: String, recovery: String? = nil) {
        lastError = message
        lastErrorRecovery = recovery
    }

    private func applyRefreshFailure(_ message: String, userID: UUID) {
        if let cached = OnboardingStatusCache.load(for: userID) {
            status = cached
            loadState = .loaded
            syncFailure = message
            lastError = nil
        } else if NetworkErrorClassifier.isConnectivityFailureFromMessage(message) {
            loadState = .failed(OnboardingError.networkUnavailable.localizedDescription)
            lastError = OnboardingError.networkUnavailable.localizedDescription
        } else {
            loadState = .failed(message)
            lastError = message
        }
    }

    private func friendlySubmitFailure(_ error: Error) -> (message: String, recovery: String?) {
        if NetworkErrorClassifier.isConnectivityFailure(error) {
            let networkError = OnboardingError.networkUnavailable
            return (networkError.localizedDescription, networkError.recoverySuggestion)
        }
        return (error.localizedDescription, nil)
    }
}

private extension NetworkErrorClassifier {
    static func isConnectivityFailureFromMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("offline")
            || lower.contains("internet")
            || lower.contains("network")
            || lower.contains("connection")
    }
}
