//
//  MockWeekRolloverTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// The mock rollover stands in for the server-side weekly turnover. Without it
/// `refresh(for:)` is a no-op offline and the reset animation lands on the same posts.
@MainActor
struct MockWeekRolloverTests {
    @Test func rolloverArchivesTheOldWeekAndOpensAnEmptyOne() throws {
        let store = BoardStore.previewBoard()
        let outgoing = try #require(store.activeBoardWeek)
        let outgoingPostCount = store.posts(for: outgoing).count
        #expect(outgoingPostCount > 0)

        #expect(store.devRollOverWeek())

        let incoming = try #require(store.activeBoardWeek)
        #expect(incoming.id != outgoing.id)
        #expect(incoming.status == .active)
        #expect(store.posts(for: incoming).isEmpty)
        #expect(incoming.startsAt <= incoming.endsAt)

        let archived = try #require(store.boardWeeks.first { $0.id == outgoing.id })
        #expect(archived.status == .archived)
        #expect(archived.archivedAt != nil)
        // The old posts survive as read-only records reachable from the Archive.
        let archivedPosts = store.posts(for: archived)
        #expect(archivedPosts.count == outgoingPostCount)
        let allReadOnly = archivedPosts.allSatisfy(\.isReadOnly)
        #expect(allReadOnly)
    }

    @Test func rolledOverBoardReopensPosting() throws {
        let store = BoardStore.previewBoard()
        store.devSetCountdown(seconds: -1)   // already expired
        let expired = try #require(store.activeBoardWeek)
        #expect(!BoardSchedule.phase(weekEnd: expired.endsAt).allowsPosting)

        #expect(store.devRollOverWeek())

        let fresh = try #require(store.activeBoardWeek)
        #expect(BoardSchedule.phase(weekEnd: fresh.endsAt).allowsPosting)
        // And the feed offers an enabled compose card again — remounted under the
        // new week's id, so it enters with the fresh board instead of surviving it.
        #expect(store.feedItems.contains { item in
            if case .newPost(let isEnabled, let weekID) = item {
                return isEnabled && weekID == fresh.id
            }
            return false
        })
    }

    @Test func rolloverIsANoOpOnALiveStore() {
        // Live stores must never fabricate a week client-side.
        let store = BoardStore(boardService: nil)
        #expect(!store.devRollOverWeek())
    }
}
