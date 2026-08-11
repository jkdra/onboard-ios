//
//  BoardPhaseTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// Pins the expiry hole: every window predicate used to be written as
/// `remaining > 0 && remaining < window`, so the instant the clock reached zero all of
/// them reported false and the board fell back to wide-open styling and — much worse —
/// a re-enabled compose button on a week that had already ended.
@MainActor
struct BoardPhaseTests {
    private let weekEnd = Date(timeIntervalSince1970: 1_800_000_000)

    private func phase(secondsBeforeEnd: TimeInterval) -> BoardPhase {
        BoardSchedule.phase(weekEnd: weekEnd, from: weekEnd.addingTimeInterval(-secondsBeforeEnd))
    }

    @Test func openWellBeforeTheDeadline() {
        #expect(phase(secondsBeforeEnd: 86_400) == .open)
        #expect(phase(secondsBeforeEnd: 10_801) == .open)
    }

    @Test func clearingSoonInsideFinalThreeHours() {
        #expect(phase(secondsBeforeEnd: 10_799) == .clearingSoon)
        #expect(phase(secondsBeforeEnd: 3_601) == .clearingSoon)
    }

    @Test func finalHourInsideLastHour() {
        #expect(phase(secondsBeforeEnd: 3_599) == .finalHour)
        #expect(phase(secondsBeforeEnd: 1) == .finalHour)
    }

    @Test func expiredAtAndAfterTheDeadline() {
        #expect(phase(secondsBeforeEnd: 0) == .expired)
        #expect(phase(secondsBeforeEnd: -1) == .expired)
        #expect(phase(secondsBeforeEnd: -86_400) == .expired)
    }

    /// The regression itself. Posting must stay closed from the final hour straight
    /// through expiry — never reopen because the counter hit zero.
    @Test func postingStaysClosedThroughExpiry() {
        #expect(phase(secondsBeforeEnd: 10_799).allowsPosting)
        #expect(!phase(secondsBeforeEnd: 3_599).allowsPosting)
        #expect(!phase(secondsBeforeEnd: 0).allowsPosting)
        #expect(!phase(secondsBeforeEnd: -3_600).allowsPosting)
    }

    /// Same for the urgency treatment — an ended board must not render as calm.
    @Test func urgencyPersistsThroughExpiry() {
        #expect(!phase(secondsBeforeEnd: 86_400).isUrgent)
        #expect(phase(secondsBeforeEnd: 10_799).isUrgent)
        #expect(phase(secondsBeforeEnd: 0).isUrgent)
        #expect(phase(secondsBeforeEnd: -600).isUrgent)
    }

    @Test func isClearingSoonCoversExpiry() {
        #expect(BoardSchedule.isClearingSoon(weekEnd: weekEnd, from: weekEnd))
        #expect(BoardSchedule.isExpired(weekEnd: weekEnd, from: weekEnd))
        // isWithinFinalHour stays narrow — it means "the last hour", not "closed".
        #expect(!BoardSchedule.isWithinFinalHour(weekEnd: weekEnd, from: weekEnd))
    }
}
