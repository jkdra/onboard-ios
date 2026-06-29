//
//  Board+Samples.swift
//  On Board
//
//  Stable UUIDs for preview and sample boards/weeks.
//

import Foundation

enum SampleBoardID {
    /// Matches the default `boards.id` in Supabase (`slug = 'main'`).
    nonisolated static let main = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
}

enum SampleBoardWeekID {
    nonisolated static let active = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
    nonisolated static let archived = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
}
