//
//  SupabaseAuthServiceTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct SupabaseAuthServiceTests {
    @Test func throwsWhenSupabaseIsNotConfigured() async {
        let service = SupabaseAuthService(
            configuration: AppConfiguration(
                supabaseURL: nil,
                supabaseAnonKey: nil,
                googleClientID: nil
            )
        )

        do {
            _ = try await service.signIn(with: .apple)
            Issue.record("Expected notConfigured error")
        } catch let error as AuthError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
