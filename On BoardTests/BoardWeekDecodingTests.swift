//
//  BoardWeekDecodingTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct BoardWeekDecodingTests {
    @Test func missingBoardIdFailsInsteadOfSubstitutingDevBoard() {
        let json = """
        {"id":"\(UUID().uuidString)","startsAt":"2026-06-29T07:00:00Z","endsAt":"2026-07-06T07:00:00Z","status":"active"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(BoardWeek.self, from: Data(json.utf8))
        }
    }
}
