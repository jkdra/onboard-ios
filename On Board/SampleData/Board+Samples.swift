//
//  Board+Samples.swift
//  On Board
//
//  Stable UUIDs for preview and sample boards/weeks.
//

import Foundation

enum SampleBoardID {
    /// Matches the default `boards.id` in Supabase (`slug = 'main'`).
    static let main = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let designCrew = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
}

enum SampleBoardWeekID {
    static let active = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
    static let archived = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
}
