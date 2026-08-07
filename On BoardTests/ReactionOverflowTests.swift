//
//  ReactionOverflowTests.swift
//  On BoardTests
//
//  The overflow layout's rules, pinned against the same logic the bar renders
//  from. These states are all reachable only by having other people's counts
//  land a certain way, which no screenshot pass can stage.
//
//  The rule the tests exist to protect: a reaction that ANYONE has used is
//  always a pill. The first design tried to make one slot show whichever of
//  laugh/hug the viewer had picked — which meant picking hug on a post with
//  12 laughs hid all 12, so a private choice erased the board's loudest
//  signal for an audience of one.
//

import Testing
@testable import On_Board

@MainActor
struct ReactionOverflowTests {

    private let all: [Reaction] = [.like, .dislike, .laugh, .hug]

    /// Calls the bar's own rule — no reimplementation here, or these would pass
    /// happily while the shipped layout drifted underneath them.
    private func split(
        counts: [Reaction: Int],
        selected: Reaction? = nil,
        enabled: [Reaction]? = nil,
        overflowEnabled: Bool = true
    ) -> (visible: [Reaction], hidden: [Reaction]) {
        ReactionBar.partition(
            enabled: enabled ?? all,
            counts: counts,
            selected: selected,
            overflowEnabled: overflowEnabled
        )
    }

    // MARK: - The flag

    @Test func flagShipsInert() {
        #expect(FeatureFlag.reactionOverflow.compiledDefault == false)
    }

    @Test func offIsTodaysFlatBar() {
        let result = split(counts: [.laugh: 9], overflowEnabled: false)
        #expect(result.visible == all)
        #expect(result.hidden.isEmpty)
    }

    // MARK: - Layout

    @Test func freshPostShowsTwoPillsPlusOverflow() {
        let result = split(counts: [:])
        #expect(result.visible == [.like, .dislike])
        #expect(result.hidden == [.laugh, .hug])
    }

    /// The whole point: weight promotes a reaction to a permanent pill.
    @Test func aUsedReactionEarnsItsPill() {
        let result = split(counts: [.laugh: 12])
        #expect(result.visible == [.like, .dislike, .laugh])
        #expect(result.hidden == [.hug])
    }

    @Test func overflowRetiresWhenNothingIsLeftBehindIt() {
        let result = split(counts: [.laugh: 12, .hug: 3])
        #expect(result.visible == all)
        #expect(result.hidden.isEmpty)
    }

    /// The bug the design exists to avoid: picking hug must NOT hide laugh.
    @Test func pickingOneOverflowReactionNeverHidesTheOther() {
        let result = split(counts: [.laugh: 12, .hug: 1], selected: .hug)
        #expect(result.visible.contains(.laugh))
        #expect(result.visible.contains(.hug))
    }

    /// Optimistic window: the pill must not blink out if the count hasn't
    /// caught up with the selection yet.
    @Test func selectionAloneKeepsAPillVisible() {
        let result = split(counts: [:], selected: .hug)
        #expect(result.visible == [.like, .dislike, .hug])
        #expect(result.hidden == [.laugh])
    }

    /// Order follows `enabledReactions`, never the counts — pills that
    /// reshuffle as counts tick move the tap target out from under a finger.
    @Test func visibleOrderIgnoresCountMagnitude() {
        let result = split(counts: [.laugh: 2, .hug: 400])
        #expect(result.visible == [.like, .dislike, .laugh, .hug])
    }

    // MARK: - Composing with enabledReactions

    /// The split is positional, so reordering config changes which two are
    /// permanent — no reaction is special-cased in the bar.
    @Test func configOrderDecidesThePermanentTwo() {
        let result = split(counts: [:], enabled: [.like, .hug, .laugh, .dislike])
        #expect(result.visible == [.like, .hug])
        #expect(result.hidden == [.laugh, .dislike])
    }

    /// A withdrawn reaction stays withdrawn — overflow must not resurrect
    /// something `enabled_reactions` deliberately removed.
    @Test func withdrawnReactionsNeverSurface() {
        let result = split(counts: [.dislike: 50], enabled: [.like, .laugh, .hug])
        #expect(!result.visible.contains(.dislike))
        #expect(!result.hidden.contains(.dislike))
    }

    /// Two or fewer enabled reactions: nothing to overflow, no "+".
    @Test func aShortBarHasNoOverflow() {
        let result = split(counts: [:], enabled: [.like, .dislike])
        #expect(result.visible == [.like, .dislike])
        #expect(result.hidden.isEmpty)
    }
}
