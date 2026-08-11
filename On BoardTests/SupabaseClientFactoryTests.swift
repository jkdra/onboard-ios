//
//  SupabaseClientFactoryTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct SupabaseClientFactoryTests {
    @Test func returnsNilWhenUnconfigured() {
        let config = AppConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            googleClientID: nil
        )
        #expect(SupabaseClientFactory.client(for: config) == nil)
    }

    @Test func returnsSharedClientForSameConfiguration() {
        let config = AppConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "test-key",
            googleClientID: nil
        )
        let first = SupabaseClientFactory.client(for: config)
        let second = SupabaseClientFactory.client(for: config)
        #expect(first != nil)
        #expect(first === second)
    }
}
