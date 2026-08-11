//
//  BoardRouteIsLivePostDestinationTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// `isLivePostDestination` drives what a board-clear reset evicts from the nav
/// stack (ContentView.triggerBoardReset) — only a route pointing at a post that
/// stops existing the moment the board rolls over should be popped. Archive,
/// Settings, and a profile are all still valid on the new week, and evicting
/// someone from Settings because a timer fired would be its own bug. No direct
/// test existed for this predicate despite the reset logic depending on it.
@MainActor
struct BoardRouteIsLivePostDestinationTests {
    private let week = BoardWeek(
        startsAt: .now,
        endsAt: .now.addingTimeInterval(3600),
        status: .active
    )

    @Test func postRoutesAreLive() {
        #expect(BoardRoute.post(UUID()).isLivePostDestination)
        #expect(BoardRoute.postFromProfile(postID: UUID(), profileID: UUID()).isLivePostDestination)
    }

    @Test func nonPostRoutesSurviveAReset() {
        #expect(!BoardRoute.archive.isLivePostDestination)
        #expect(!BoardRoute.archivedWeek(week).isLivePostDestination)
        #expect(!BoardRoute.profile(Profile.samples[0]).isLivePostDestination)
        #expect(!BoardRoute.settings.isLivePostDestination)
    }
}
