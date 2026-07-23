//
//  OnboardingStore.swift
//  On Board
//

import Foundation
import Observation

/// A referral code captured from an invite deep link before the user reaches
/// the profile step. Lives in UserDefaults (not the store) so it survives the
/// sign-in flow; cleared on successful submission and on sign-out so it can't
/// leak into a different account's onboarding on the same device.
enum PendingReferralCode {
    static let key = "pendingReferralCode"

    static func store(_ code: String) {
        UserDefaults.standard.set(code, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

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

    /// How long a fetched status stays "fresh". `refreshIfOnline()` refetches
    /// past this age so foregrounding the app picks up server-side changes
    /// (e.g. waitlist approval). Settable for tests.
    var statusStaleInterval: TimeInterval = 60
    private var lastFetchedAt: Date?

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
        lastFetchedAt = nil
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

    /// Foreground-refresh policy. A user still in onboarding — most importantly one
    /// parked on the waitlist — must pick up a server-side change the instant they
    /// bring the app forward: an admin admission assigns their board and flips them
    /// to `complete`, and `RootView` reactively swaps in `BoardListView`. So bypass
    /// the staleness guard until they're fully onboarded (this is also what makes
    /// tapping the "You're On Board!" push land them straight on their board, since
    /// the tap foregrounds the app). Fully onboarded users keep the throttled path
    /// to avoid a status RPC on every foreground.
    func refreshOnForeground() async {
        if isComplete {
            await refreshIfOnline()
        } else {
            await refresh(force: true)
        }
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

        let isFresh = lastFetchedAt.map { Date.now.timeIntervalSince($0) < statusStaleInterval } ?? false
        if !force, !userChanged, loadState == .loaded, status != nil, isFresh {
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
            lastFetchedAt = .now
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

    /// Inline pre-check for the school email step, mirroring
    /// `checkHandleAvailable`. Unlike the handle check, an indeterminate error
    /// resolves to `.available` — the guard in begin_school_email_verification
    /// is authoritative and re-checks at send, so a transient failure here
    /// shouldn't strand the user behind a disabled button.
    func checkSchoolEmailAvailable(_ email: String) async -> HandleCheckResult {
        if requiresNetwork, !network.isConnected {
            return .networkError
        }

        do {
            let isAvailable = try await service.checkSchoolEmailAvailable(email)
            return isAvailable ? .available : .taken
        } catch {
            if NetworkErrorClassifier.isConnectivityFailure(error) {
                return .networkError
            }
            return .available
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
    func submitBirthday(birthday: Date, showBirthday: Bool) async -> Bool {
        await performSubmit {
            _ = try await service.completeBirthday(birthday: birthday, showBirthday: showBirthday)
            await refresh(force: true)
            return status?.onboardingStep != .birthday
        }
    }

    @discardableResult
    func submitUsername(_ handle: String) async -> Bool {
        await performSubmit {
            _ = try await service.completeUsername(handle)
            await refresh(force: true)
            return status?.onboardingStep != .username
        }
    }

    @discardableResult
    func submitProfile(displayName: String, bio: String?, avatarUrl: String? = nil, referralCode: String? = nil) async -> Bool {
        await performSubmit {
            // Referral code goes first: if it's invalid the user gets the error
            // while the field is still on screen to fix or clear — a swallowed
            // failure here would silently never credit the referrer. The RPC is
            // idempotent for the same code, so a retry after a completeProfile
            // failure doesn't error on the already-applied code.
            if let referralCode, !referralCode.isEmpty {
                try await service.submitReferralCode(referralCode)
            }
            _ = try await service.completeProfile(
                displayName: displayName,
                bio: bio,
                avatarUrl: avatarUrl
            )
            PendingReferralCode.clear()
            await refresh(force: true)
            return status?.onboardingStep == .schoolVerify
                || status?.onboardingStep == .waitlist
                || status?.isComplete == true
        }
    }

    @discardableResult
    func sendSchoolVerificationCode(to email: String) async -> Bool {
        await performSubmit {
            _ = try await service.beginSchoolEmailVerification(email)
            await refresh(force: true)
            return true
        }
    }

    @discardableResult
    func verifySchoolEmail(_ email: String, code: String) async -> Bool {
        await performSubmit {
            _ = try await service.completeSchoolEmailVerification(email, token: code)
            await refresh(force: true)
            return status?.onboardingStep == .waitlist || status?.isComplete == true
        }
    }

    @discardableResult
    func joinWaitlist() async -> Bool {
        await performSubmit {
            _ = try await service.joinWaitlist()
            await refresh(force: true)
            return status?.isComplete == true
        }
    }

    /// Shared wrapper for the onboarding submit RPCs: the online guard, the in-flight
    /// flag, and error mapping (session-expired → reset, OnboardingError → its message,
    /// anything else → a friendly message). `operation` runs the RPC (+ refresh) and
    /// returns whether it advanced the user.
    private func performSubmit(_ operation: () async throws -> Bool) async -> Bool {
        guard ensureOnlineForSubmit() else { return false }

        isSubmitting = true
        clearLastError()
        defer { isSubmitting = false }

        do {
            return try await operation()
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
