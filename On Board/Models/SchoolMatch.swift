//
//  SchoolMatch.swift
//  On Board
//

import Foundation

// nonisolated so its synthesized Codable conformance isn't main-actor-isolated
// (the project defaults to MainActor isolation, but this is a pure data model that
// the Supabase SDK decodes off the main actor). See project concurrency notes.
nonisolated struct SchoolMatch: Equatable, Codable, Sendable {
    let domain: String
    let schoolName: String
    let boardId: UUID
    let boardName: String
}

enum SchoolEmailRules {
    private static let pattern = "^[^@\\s]+@[^@\\s]+\\.edu$"

    static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
