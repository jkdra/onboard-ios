//
//  PostTone.swift
//  On Board
//

import SwiftUI

/// The tint a post is rendered with on the board.
///
/// Stored on `Post` (round-trips with Supabase via `Codable`) so the
/// post's color follows the data — same tone in the grid, detail view,
/// and across app launches. Users can either pick a tone in the composer
/// or leave it on "Any Color!", in which case the client assigns a
/// random tone at submit time.
enum PostTone: String, CaseIterable, Identifiable, Codable {
    case blue, purple, pink, orange, green, teal, mint, red, yellow, indigo

    var id: String { rawValue }

    /// Capitalized form for UI labels — "Blue", "Mint", etc.
    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        case .mint: .mint
        case .red: .red
        case .yellow: .yellow
        case .indigo: .indigo
        }
    }

    static func random() -> PostTone {
        allCases.randomElement() ?? .blue
    }
}
