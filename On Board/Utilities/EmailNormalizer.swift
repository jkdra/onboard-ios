//
//  EmailNormalizer.swift
//  On Board
//

import Foundation

enum EmailNormalizer {
    /// Canonical form used everywhere an email is compared, stored, or sent to
    /// the backend: whitespace-trimmed and lowercased. Live and mock services
    /// must normalize identically (see CLAUDE.md), so both route through here.
    static func normalized(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
