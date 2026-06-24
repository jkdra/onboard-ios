//
//  AppConfiguration.swift
//  On Board
//
//  Reads the official On Board Supabase keys from Info.plist (injected via
//  Secrets.xcconfig for maintainer builds). Contributors run the app with mock
//  data and do not need their own backend or schema.
//

import Foundation

struct AppConfiguration: Equatable, Sendable {
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let googleClientID: String?

    nonisolated var isSupabaseConfigured: Bool {
        guard let supabaseURL,
              let host = supabaseURL.host,
              !host.isEmpty,
              supabaseURL.scheme?.hasPrefix("http") == true,
              let anonKey = supabaseAnonKey,
              Self.isResolvedValue(anonKey) else {
            return false
        }
        return true
    }

    nonisolated var isGoogleSignInConfigured: Bool {
        guard let googleClientID, Self.isResolvedValue(googleClientID) else {
            return false
        }
        return true
    }

    /// Google via Supabase OAuth works when the backend is configured (native client ID optional).
    nonisolated var isGoogleOAuthAvailable: Bool {
        isSupabaseConfigured
    }

    nonisolated static let authRedirectURL = URL(string: "onboard://auth-callback")!

    private final class BundleMarker {}

    nonisolated static let current = load()

    nonisolated static func load(from bundle: Bundle = Bundle(for: BundleMarker.self)) -> AppConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let urlString = info["SupabaseURL"] as? String
        let anonKey = info["SupabaseAnonKey"] as? String
        let googleClientID = info["GoogleClientID"] as? String

        return AppConfiguration(
            supabaseURL: urlString.flatMap(Self.resolveURL(from:)),
            supabaseAnonKey: Self.resolveCredential(anonKey),
            googleClientID: Self.resolveCredential(googleClientID)
        )
    }

    nonisolated private static func resolveURL(from string: String) -> URL? {
        guard isResolvedValue(string),
              let url = URL(string: string),
              let host = url.host,
              !host.isEmpty,
              url.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return url
    }

    nonisolated private static func resolveCredential(_ string: String?) -> String? {
        guard let string, isResolvedValue(string) else { return nil }
        return string
    }

    /// Rejects empty values and unexpanded Xcode placeholders like `$(SUPABASE_URL)`.
    nonisolated private static func isResolvedValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return false }
        return true
    }
}
