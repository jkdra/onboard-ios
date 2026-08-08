//
//  AppConfigurationTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct AppConfigurationTests {
    @Test func treatsEmptySupabaseValuesAsUnconfigured() {
        let config = AppConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: "",
            googleClientID: ""
        )
        #expect(!config.isSupabaseConfigured)
        #expect(!config.isGoogleSignInConfigured)
    }

    @Test func detectsConfiguredSupabase() {
        let config = AppConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "anon-key",
            googleClientID: "google-client-id"
        )
        #expect(config.isSupabaseConfigured)
        #expect(config.isGoogleSignInConfigured)
    }

    @Test func rejectsUnexpandedXcodePlaceholders() {
        let config = AppConfiguration(
            supabaseURL: URL(string: "https://$(SUPABASE_URL)"),
            supabaseAnonKey: "$(SUPABASE_ANON_KEY)",
            googleClientID: "$(GOOGLE_CLIENT_ID)"
        )
        #expect(!config.isSupabaseConfigured)
        #expect(!config.isGoogleSignInConfigured)
    }

    @Test func loadRejectsPlaceholderStrings() {
        let config = AppConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            googleClientID: nil
        )
        #expect(!config.isSupabaseConfigured)
    }
}
