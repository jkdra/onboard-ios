//
//  RemoteConfigStore.swift
//  On Board
//
//  Owns the fetch, caching, and resolution of RemoteConfig.
//
//  Persisted in UserDefaults rather than CacheEnvelope on purpose. CLAUDE.md's
//  "one envelope, one file" rule governs cached *board entities*; config has
//  different lifetime semantics and does not belong there:
//
//   - CacheEnvelope is deleted by clearDiskCache() on sign-out. Config must
//     survive sign-out — it is app configuration, not account data, and there is
//     nothing to leak between accounts in values every client receives.
//   - CacheEnvelope is BoardStore-owned and hydrated asynchronously off-main.
//     The version gate and any auth-flow flag must be readable *before* sign-in
//     and *synchronously* at launch — a broken sign-in is exactly when they matter.
//   - The payload is ~20 short strings. It needs no async hydration.
//

import Foundation
import OSLog
import Supabase

private let logger = Logger(subsystem: "org.onboardapp.onboard", category: "RemoteConfig")

@Observable
@MainActor
final class RemoteConfigStore {
    static let storageKey = "remoteConfig.values"
    private static let identityKey = "remoteConfig.installIdentity"

    private(set) var config: RemoteConfig = .empty

    /// Stable per-install id used to bucket feature flags before sign-in, so a
    /// staged rollout behaves consistently on the sign-in screen too.
    private(set) var installIdentity: UUID

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.string(forKey: Self.identityKey),
           let identity = UUID(uuidString: stored) {
            installIdentity = identity
        } else {
            let identity = UUID()
            defaults.set(identity.uuidString, forKey: Self.identityKey)
            installIdentity = identity
        }

        if let stored = defaults.object(forKey: Self.storageKey) as? [String: String] {
            config = RemoteConfig(values: stored)
        }
    }

    /// Fire-and-forget. Never throws to the caller and never blocks rendering —
    /// a failed fetch leaves the last-known (or compiled-default) config in
    /// place, which is always a usable app.
    func refresh() async {
        guard let client = SupabaseClientFactory.client(for: .current) else { return }
        do {
            let values: [String: String] = try await client
                .rpc("get_app_config")
                .execute()
                .value
            apply(values)
        } catch {
            logger.debug("Remote config fetch failed, keeping last known: \(error.localizedDescription)")
        }
    }

    /// Applies fetched values, writing to storage only when something actually
    /// changed — this runs on every foreground, and most calls just reconfirm
    /// what is already stored.
    func apply(_ values: [String: String]) {
        let updated = RemoteConfig(values: values)
        guard updated != config else { return }
        config = updated
        defaults.set(values, forKey: Self.storageKey)
    }

    /// Resolves a flag against the signed-in user when there is one, and the
    /// per-install identity otherwise.
    func isEnabled(_ flag: FeatureFlag, for userID: UUID?) -> Bool {
        config.isEnabled(flag, for: userID ?? installIdentity)
    }
}
