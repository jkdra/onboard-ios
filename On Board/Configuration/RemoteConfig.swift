//
//  RemoteConfig.swift
//  On Board
//
//  Server-supplied values that parameterize shipped native behavior.
//
//  THE DEFAULT IS ALWAYS CURRENT SHIPPED BEHAVIOR. Every accessor falls back to
//  the value that was compiled in, so a server returning `{}` — or a failed
//  fetch, or an unparseable value — is indistinguishable from a build with no
//  remote config at all. Never add an accessor whose fallback causes the caller
//  to skip behavior it does today.
//
//  The wire shape is an untyped string map on purpose: unknown keys are ignored
//  (so a newer server can't break an older client) and missing keys fall back
//  (so an older server can't break a newer client). Call sites never see a
//  string — this is the only file in the app that contains config key literals.
//

import Foundation

struct RemoteConfig: Sendable, Equatable {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    static let empty = RemoteConfig(values: [:])

    /// The raw map, for persistence only.
    var storedValues: [String: String] { values }

    // MARK: - Timing

    var feedPollSeconds: TimeInterval { double("feed_poll_seconds") ?? 45 }
    /// Single-sourced across all four OTP resend sites (sign-in, provider
    /// linking, and both school-email paths), which previously carried 60s and
    /// 30s independently.
    ///
    /// Note: Supabase Auth applies its own server-side resend rate limit
    /// (commonly 60s by default). If this is set below that, the client will
    /// re-enable the button before the server will accept the request, and the
    /// user gets a rate-limit error instead of a code. Raise this key rather
    /// than shipping a build if that shows up.
    var otpCooldownSeconds: Int { int("otp_cooldown_seconds") ?? 30 }

    // MARK: - Referral ladder

    var referralOneMonthThreshold: Int { int("referral_one_month_threshold") ?? 4 }
    var referralThreeMonthThreshold: Int { int("referral_three_month_threshold") ?? 5 }
    var referralDisclosureThreshold: Int { int("referral_disclosure_threshold") ?? 3 }
    var referralShareMessage: String? { values["referral_share_message"] }
    var referralShareMessageInstant: String? { values["referral_share_message_instant"] }

    // MARK: - Board schedule
    //
    // Mirrors server-side rules. The server stays authoritative — a stale client
    // shows a slightly wrong countdown, it never lets a write succeed that the
    // server would reject.

    var boardClearingSoonHours: Int { int("board_clearing_soon_hours") ?? 3 }
    var boardFinalHourLockoutHours: Int { int("board_final_hour_lockout_hours") ?? 1 }

    // MARK: - Account rules (mirrors of server rules)

    var handleChangeWindowDays: Int { int("handle_change_window_days") ?? 14 }
    var handleChangeMaxPerWindow: Int { int("handle_change_max_per_window") ?? 2 }

    // MARK: - Field limits
    //
    // Display hints only. If the server also enforces a limit it is the
    // authority; a client value larger than the server's produces a confusing
    // rejection, so raise the server first.

    var commentMaxLength: Int { int("comment_max_length") ?? 280 }
    var bioMaxLength: Int { int("bio_max_length") ?? 300 }
    var displayNameMaxLength: Int { int("display_name_max_length") ?? 50 }

    // MARK: - Cache

    var maxCachedArchiveWeeks: Int { int("max_cached_archive_weeks") ?? 3 }

    // MARK: - Version gate

    var minSupportedVersion: String? { values["min_supported_version"] }
    var recommendedVersion: String? { values["recommended_version"] }

    // MARK: - Raw access (feature flags only)

    /// Feature flags are read through `FeatureFlag`, which needs the raw string.
    /// Nothing else should use this — add a typed accessor instead.
    func rawValue(for key: String) -> String? { values[key] }

    // MARK: - Parsing

    private func int(_ key: String) -> Int? {
        guard let raw = values[key], let value = Int(raw) else { return nil }
        return value
    }

    private func double(_ key: String) -> Double? {
        guard let raw = values[key], let value = Double(raw) else { return nil }
        return value
    }
}

// MARK: - Version gating

enum AppVersion {
    /// Current `CFBundleShortVersionString`, e.g. "1.1.1".
    nonisolated static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Numeric, component-wise comparison. A plain string compare reads "1.10"
    /// as older than "1.9", which would lock users out of a *newer* build.
    ///
    /// Returns `false` for anything unparseable — never gate someone out of the
    /// app because a version string was malformed.
    nonisolated static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) }
        let right = rhs.split(separator: ".").map { Int($0) }
        guard !left.contains(nil), !right.contains(nil), !left.isEmpty, !right.isEmpty else {
            return false
        }
        let l = left.compactMap { $0 }
        let r = right.compactMap { $0 }
        for index in 0..<max(l.count, r.count) {
            let a = index < l.count ? l[index] : 0
            let b = index < r.count ? r[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}

enum UpdateRequirement: Equatable, Sendable {
    case none
    /// Dismissible prompt. The default posture.
    case recommended
    /// Blocking screen. Reserved for builds that are actively harmful —
    /// data corruption, not cosmetic bugs.
    case required
}

extension RemoteConfig {
    func updateRequirement(forCurrentVersion current: String = AppVersion.current) -> UpdateRequirement {
        if let minimum = minSupportedVersion, AppVersion.isOlder(current, than: minimum) {
            return .required
        }
        if let recommended = recommendedVersion, AppVersion.isOlder(current, than: recommended) {
            return .recommended
        }
        return .none
    }
}
